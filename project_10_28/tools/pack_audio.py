"""Add up to four 48 kHz/16-bit/stereo WAVs to a COPY of the image.

Always use the original picture image as --source. Repeated runs rebuild the
separate output from that source; existing files are never removed or replaced
inside the FAT volume. No physical disk is opened by this tool.
"""
from pathlib import Path
import argparse
import json
import math
import os
import re
import struct
import tempfile
import wave
import zlib

ROOT = Path(__file__).resolve().parent.parent
SECTOR = 512
DISK_BYTES = 128 * 1024 * 1024
CATALOG_LBA = 2057
MAGIC = b'WLPCM001'


def u16(data, offset):
    return struct.unpack_from('<H', data, offset)[0]


def u32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]


def read_pcm(path):
    """Read RIFF PCM, allowing ordinary metadata chunks but no compression."""
    data = Path(path).read_bytes()
    if len(data) < 12 or data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        raise ValueError(f'{path}: expected a RIFF WAVE file')
    end = u32(data, 4) + 8
    if end != len(data):
        raise ValueError(f'{path}: truncated WAV or inconsistent RIFF length')
    position = 12
    fmt = pcm = None
    while position < end:
        if position + 8 > end:
            raise ValueError(f'{path}: truncated WAV chunk header')
        name = data[position:position + 4]
        length = u32(data, position + 4)
        begin = position + 8
        if begin + length > end:
            raise ValueError(f'{path}: truncated WAV chunk')
        if name == b'fmt ':
            if fmt is not None or length < 16:
                raise ValueError(f'{path}: invalid WAV format chunk')
            fmt = struct.unpack_from('<HHIIHH', data, begin)
        elif name == b'data':
            if pcm is not None:
                raise ValueError(f'{path}: multiple WAV data chunks are unsupported')
            pcm = data[begin:begin + length]
        position = begin + length + (length & 1)
    if position != end or fmt != (1, 2, 48000, 192000, 4, 16):
        raise ValueError(f'{path}: WAV must be uncompressed PCM, 48000 Hz, 16-bit stereo')
    if pcm is None or not pcm or len(pcm) % 4:
        raise ValueError(f'{path}: PCM must contain complete nonempty stereo sample frames')
    return pcm


def load_tracks(audio_dir):
    audio_dir = Path(audio_dir)
    paths = {}
    if audio_dir.exists() and not audio_dir.is_dir():
        raise ValueError(f'Audio input is not a directory: {audio_dir}')
    if audio_dir.is_dir():
        for path in audio_dir.iterdir():
            match = re.fullmatch(r'music(\d+)\.wav', path.name, re.IGNORECASE)
            if match:
                number = int(match[1])
                if not 1 <= number <= 4 or match[1] != f'{number:02d}' or number in paths:
                    raise ValueError('Use music01.wav through music04.wav, without duplicates')
                paths[number] = path
    if paths and sorted(paths) != list(range(1, len(paths) + 1)):
        raise ValueError('Music numbering must be consecutive, starting with music01.wav')
    return [(path.name, read_pcm(path)) for _, path in sorted(paths.items())]


def volume_layout(image):
    """Validate the layout used by prepare_assets.py before allocating clusters."""
    if len(image) != DISK_BYTES or image[510:512] != b'\x55\xaa':
        raise ValueError('Expected the original 128 MiB WestLake image')
    part, volume = u32(image, 454), u32(image, 458)
    if part != 2048 or part + volume != len(image) // SECTOR:
        raise ValueError('Unexpected partition bounds')
    boot = image[part * SECTOR:(part + 1) * SECTOR]
    reserved, fatsize = u16(boot, 14), u32(boot, 36)
    if (u16(boot, 11) != SECTOR or boot[13] != 1 or boot[16] != 2
            or boot[510:512] != b'\x55\xaa' or u32(boot, 32) != volume
            or reserved < 10 or reserved > volume or not fatsize):
        raise ValueError('Expected FAT32 with 512-byte clusters and two FAT copies')
    fat_lba = part + reserved
    data_lba = fat_lba + 2 * fatsize
    clusters = volume - reserved - 2 * fatsize
    if clusters < 65525 or (clusters + 2) * 4 > fatsize * SECTOR:
        raise ValueError('Invalid FAT32 allocation bounds')
    fat = bytearray(image[fat_lba * SECTOR:(fat_lba + fatsize) * SECTOR])
    if fat != image[(fat_lba + fatsize) * SECTOR:data_lba * SECTOR]:
        raise ValueError('FAT copies differ')
    root_chain, seen = [], set()
    cluster = u32(boot, 44)
    while cluster < 0x0ffffff8:
        if cluster < 2 or cluster >= clusters + 2 or cluster in seen:
            raise ValueError('Invalid root directory FAT chain')
        seen.add(cluster)
        root_chain.append(cluster)
        cluster = u32(fat, cluster * 4) & 0x0fffffff
    if not root_chain:
        raise ValueError('Missing root directory')
    directory = bytearray().join(image[(data_lba + c - 2) * SECTOR:
                                       (data_lba + c - 1) * SECTOR] for c in root_chain)
    catalog = image[2056 * SECTOR:2057 * SECTOR]
    if catalog[:10] != b'WLAV0002\x18\x18':
        raise ValueError('Expected the 24-picture WLAV0002 catalog')
    old_audio = image[CATALOG_LBA * SECTOR:(CATALOG_LBA + 1) * SECTOR]
    if any(old_audio) and old_audio[:8] != MAGIC:
        raise ValueError('Audio reserved sector already contains unrecognized data')
    fs_lba, backup = u16(boot, 48), u16(boot, 50)
    if not 0 < fs_lba < reserved or not 0 < backup < reserved or backup + fs_lba >= reserved:
        raise ValueError('Invalid primary/backup FSINFO positions')
    for lba in (part + fs_lba, part + backup + fs_lba):
        info = image[lba * SECTOR:(lba + 1) * SECTOR]
        if (u32(info, 0), u32(info, 484), u32(info, 508)) != (0x41615252, 0x61417272, 0xaa550000):
            raise ValueError('Invalid FSINFO signatures')
    return part, reserved, fatsize, data_lba, clusters, fat, root_chain, directory, fs_lba, backup


def pack_image(source, output, audio_dir):
    source, output = Path(source), Path(output)
    if source.resolve() == output.resolve():
        raise ValueError('Source and output must differ; the original picture image is preserved')
    if source.suffix.lower() != '.img' or output.suffix.lower() != '.img' or not source.is_file():
        raise ValueError('Source and output must be ordinary .img files')
    tracks = load_tracks(audio_dir)
    image = bytearray(source.read_bytes())
    part, reserved, fatsize, data_lba, clusters, fat, root_chain, directory, fs_lba, backup = volume_layout(image)
    names = [f'MUSIC{n:02d} PCM'.encode('ascii') for n in range(1, 5)]
    slots, ended = [], False
    for offset in range(0, len(directory), 32):
        first = directory[offset]
        if first == 0:
            ended = True
        if ended or first == 0xe5:
            slots.append(offset)
        elif directory[offset:offset + 11] in names:
            raise ValueError('Source already contains MUSICxx.PCM; use the original picture image')
    if len(slots) < len(tracks):
        raise ValueError('Root directory has insufficient free entries; no files were changed')
    entries = [u32(fat, c * 4) & 0x0fffffff for c in range(clusters + 2)]
    catalog = bytearray(SECTOR)
    catalog[:8] = MAGIC
    catalog[8:12] = bytes((len(tracks), 2, 16, 0))
    struct.pack_into('<I', catalog, 12, 48000)
    report = []
    for index, (wav_name, pcm) in enumerate(tracks):
        needed = (len(pcm) + SECTOR - 1) // SECTOR
        first, run = None, 0
        for c in range(2, clusters + 2):
            run = run + 1 if entries[c] == 0 else 0
            if run == needed:
                first = c - needed + 1
                break
        if first is None:
            raise ValueError(f'{wav_name}: insufficient contiguous free space in 128 MiB image')
        for c in range(first, first + needed):
            entries[c] = c + 1 if c < first + needed - 1 else 0x0fffffff
            struct.pack_into('<I', fat, c * 4, entries[c])
        lba = data_lba + first - 2
        crc = zlib.crc32(pcm) & 0xffffffff
        struct.pack_into('<IIII', catalog, 16 + index * 16, lba, len(pcm) // 4, crc, 0)
        entry = bytearray(32)
        entry[:11], entry[11] = names[index], 0x20
        struct.pack_into('<H', entry, 20, first >> 16)
        struct.pack_into('<H', entry, 26, first & 65535)
        struct.pack_into('<I', entry, 28, len(pcm))
        directory[slots[index]:slots[index] + 32] = entry
        image[lba * SECTOR:(lba + needed) * SECTOR] = pcm + bytes(needed * SECTOR - len(pcm))
        report.append({'source': wav_name, 'file': f'MUSIC{index + 1:02d}.PCM',
                       'lba': lba, 'sample_frames': len(pcm) // 4, 'crc32': f'{crc:08x}'})
    for copy in range(2):
        start = (part + reserved + copy * fatsize) * SECTOR
        image[start:start + len(fat)] = fat
    for index, cluster in enumerate(root_chain):
        start = (data_lba + cluster - 2) * SECTOR
        image[start:start + SECTOR] = directory[index * SECTOR:(index + 1) * SECTOR]
    free = sum(value == 0 for value in entries[2:])
    next_free = next((c for c in range(2, clusters + 2) if entries[c] == 0), 0xffffffff)
    for lba in (part + fs_lba, part + backup + fs_lba):
        struct.pack_into('<II', image, lba * SECTOR + 488, free, next_free)
    image[CATALOG_LBA * SECTOR:(CATALOG_LBA + 1) * SECTOR] = catalog
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=output.name + '.', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(image)
        os.replace(temporary, output)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return report


def write_test_tone(directory):
    """Explicit diagnostic only: one second of 1 kHz at -18 dBFS."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    pcm = bytearray()
    for frame in range(48000):
        sample = round(4096 * math.sin(2 * math.pi * 1000 * frame / 48000))
        pcm.extend(struct.pack('<hh', sample, sample))
    with wave.open(str(directory / 'music01.wav'), 'wb') as stream:
        stream.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
        stream.writeframes(pcm)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / '01_Assets/WestLake_TF_128MiB.img')
    parser.add_argument('--output', type=Path, default=ROOT / '01_Assets/WestLake_TF_Audio_128MiB.img')
    parser.add_argument('--audio-dir', type=Path, default=ROOT / '01_Assets/Audio')
    parser.add_argument('--test-tone', action='store_true', help='Pack a diagnostic tone generated only inside a temporary directory')
    args = parser.parse_args()
    try:
        if args.test_tone:
            with tempfile.TemporaryDirectory(prefix='westlake-test-tone-') as directory:
                write_test_tone(directory)
                report = pack_image(args.source, args.output, directory)
        else:
            report = pack_image(args.source, args.output, args.audio_dir)
    except (OSError, ValueError, struct.error) as error:
        parser.exit(1, f'ERROR: {error}\n')
    print(json.dumps({'output': str(args.output), 'count': len(report), 'test_tone': args.test_tone, 'tracks': report}, indent=2))
    if not report:
        print('No music WAVs found: valid zero-count catalog written; music playback will be silent.')


if __name__ == '__main__':
    main()
