"""Add four station narrations to a COPY of the existing music image.

Reads 48 kHz/16-bit/stereo PCM WAVs and three sample-counted subtitle cues
per station. No physical SD disk is opened. Existing picture/music files and
their catalogs are retained; repeated runs start from the same music image.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import struct
import tempfile
import zlib

from pack_audio import ROOT, SECTOR, read_pcm, u16, u32, volume_layout

CATALOG_LBA = 2058
MAGIC = b'WLVOC001'


def load_narrations(voice_dir, narration_path=None):
    voice_dir = Path(voice_dir)
    narration_path = Path(narration_path) if narration_path else voice_dir / 'narration.json'
    metadata = json.loads(narration_path.read_text('utf-8'))
    if not isinstance(metadata, dict):
        raise ValueError('Narration metadata must be a JSON object')
    stations = metadata.get('stations')
    if metadata.get('sample_rate') != 48000 or not isinstance(stations, list) or len(stations) != 4:
        raise ValueError('Narration metadata must specify sample_rate 48000 and four stations')
    if any(type(s.get('id')) is not int for s in stations if isinstance(s, dict)) or any(not isinstance(s, dict) for s in stations):
        raise ValueError('Station IDs must be integers 0 through 3')
    if sorted(s.get('id', -1) for s in stations) != [0, 1, 2, 3]:
        raise ValueError('Station IDs must be unique 0 through 3')
    result = []
    for station in sorted(stations, key=lambda s: s['id']):
        index = station['id']
        expected = f'station{index + 1:02d}.wav'
        if station.get('wav') != expected:
            raise ValueError(f'Station {index}: expected local WAV filename {expected}')
        pcm = read_pcm(voice_dir / expected)
        frames = len(pcm) // 4
        segments = station.get('segments')
        if not isinstance(segments, list) or len(segments) != 3:
            raise ValueError(f'{expected}: exactly three narration segments are required')
        previous = 0
        for segment in segments:
            if not isinstance(segment, dict):
                raise ValueError(f'{expected}: invalid narration segment')
            text, start, end = (segment.get(k) for k in ('text', 'start_frame', 'end_frame'))
            if not isinstance(text, str) or not 1 <= len(text) <= 31 or any(c in text for c in '\r\n\t'):
                raise ValueError(f'{expected}: each single-line subtitle must contain 1..31 characters')
            if type(start) is not int or type(end) is not int or start != previous or not start < end <= frames:
                raise ValueError(f'{expected}: cues must be nonempty, contiguous sample-frame ranges')
            previous = end
        if previous != frames:
            raise ValueError(f'{expected}: final cue must end at the WAV sample-frame count')
        result.append((station, pcm))
    return result


def pack_image(source, output, voice_dir, narration_path=None):
    source, output = Path(source), Path(output)
    if source.resolve() == output.resolve():
        raise ValueError('Source and output must differ; the music image is retained')
    if source.suffix.lower() != '.img' or output.suffix.lower() != '.img' or not source.is_file():
        raise ValueError('Source and output must be ordinary .img files')
    narrations = load_narrations(voice_dir, narration_path)
    image = bytearray(source.read_bytes())
    part, reserved, fat_size, data_lba, clusters, fat, root_chain, directory, fs_lba, backup = volume_layout(image)
    if any(image[CATALOG_LBA * SECTOR:(CATALOG_LBA + 1) * SECTOR]):
        raise ValueError('Voice reserved sector is already occupied; use the music-only source image')
    names = [f'VOICE{number:02d} PCM'.encode('ascii') for number in range(1, 5)]
    slots = []
    ended = False
    for offset in range(0, len(directory), 32):
        first = directory[offset]
        if first == 0:
            ended = True
        if ended:
            # Entries after a FAT end marker are not files, including stale bytes.
            directory[offset:offset + 32] = bytes(32)
            slots.append(offset)
        elif first == 0xe5:
            slots.append(offset)
        elif directory[offset:offset + 11] in names:
            raise ValueError('Source already contains VOICExx.PCM; use the music-only source image')
    entries = [u32(fat, c * 4) & 0x0fffffff for c in range(clusters + 2)]

    def set_fat(cluster, value):
        entries[cluster] = value
        struct.pack_into('<I', fat, cluster * 4, value)

    # Four file slots plus one untouched end marker. Extend a full directory
    # instead of overwriting another file or writing a 32nd entry without a marker.
    while len(slots) < 5:
        free_cluster = next((c for c in range(2, clusters + 2) if entries[c] == 0), None)
        if free_cluster is None:
            raise ValueError('No free cluster for root-directory extension')
        set_fat(root_chain[-1], free_cluster)
        set_fat(free_cluster, 0x0fffffff)
        root_chain.append(free_cluster)
        begin = len(directory)
        directory.extend(bytes(SECTOR))
        slots.extend(range(begin, begin + SECTOR, 32))

    catalog = bytearray(SECTOR)
    catalog[:8] = MAGIC
    catalog[8:12] = bytes((4, 2, 16, 3))
    struct.pack_into('<I', catalog, 12, 48000)
    report = []
    for index, (station, pcm) in enumerate(narrations):
        needed = (len(pcm) + SECTOR - 1) // SECTOR
        first, run_length = None, 0
        for cluster in range(2, clusters + 2):
            run_length = run_length + 1 if entries[cluster] == 0 else 0
            if run_length == needed:
                first = cluster - needed + 1
                break
        if first is None:
            raise ValueError(f'{station["wav"]}: insufficient contiguous free space')
        for cluster in range(first, first + needed):
            set_fat(cluster, cluster + 1 if cluster < first + needed - 1 else 0x0fffffff)
        lba = data_lba + first - 2
        frames = len(pcm) // 4
        cue1, cue2 = (station['segments'][i]['end_frame'] for i in (0, 1))
        characters = [len(segment['text']) for segment in station['segments']]
        crc = zlib.crc32(pcm) & 0xffffffff
        record = 16 + index * 32
        struct.pack_into('<IIIII', catalog, record, lba, frames, cue1, cue2, crc)
        catalog[record + 20:record + 23] = bytes(characters)
        entry = bytearray(32)
        entry[:11], entry[11] = names[index], 0x20
        struct.pack_into('<H', entry, 20, first >> 16)
        struct.pack_into('<H', entry, 26, first & 65535)
        struct.pack_into('<I', entry, 28, len(pcm))
        directory[slots[index]:slots[index] + 32] = entry
        image[lba * SECTOR:(lba + needed) * SECTOR] = pcm + bytes(needed * SECTOR - len(pcm))
        report.append({'id': index, 'source': station['wav'], 'file': f'VOICE{index + 1:02d}.PCM',
                       'lba': lba, 'sample_frames': frames, 'cue1': cue1, 'cue2': cue2,
                       'characters': characters, 'crc32': f'{crc:08x}',
                       'pcm_sha256': hashlib.sha256(pcm).hexdigest(),
                       'wav_sha256': hashlib.sha256((Path(voice_dir) / station['wav']).read_bytes()).hexdigest()})
    for copy in range(2):
        offset = (part + reserved + copy * fat_size) * SECTOR
        image[offset:offset + len(fat)] = fat
    for index, cluster in enumerate(root_chain):
        offset = (data_lba + cluster - 2) * SECTOR
        image[offset:offset + SECTOR] = directory[index * SECTOR:(index + 1) * SECTOR]
    free = sum(value == 0 for value in entries[2:])
    next_free = next((c for c in range(2, clusters + 2) if entries[c] == 0), 0xffffffff)
    for lba in (part + fs_lba, part + backup + fs_lba):
        struct.pack_into('<II', image, lba * SECTOR + 488, free, next_free)
    image[CATALOG_LBA * SECTOR:(CATALOG_LBA + 1) * SECTOR] = catalog

    # Commit only after every input, allocation and cue has passed validation.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / '01_Assets/WestLake_TF_Audio_128MiB.img')
    parser.add_argument('--output', type=Path, default=ROOT / '01_Assets/WestLake_TF_Voice_128MiB.img')
    parser.add_argument('--voice-dir', type=Path, default=ROOT / '01_Assets/Voice')
    parser.add_argument('--narration', type=Path, help='Optional override for narration.json')
    args = parser.parse_args()
    try:
        result = pack_image(args.source, args.output, args.voice_dir, args.narration)
    except (OSError, ValueError, KeyError, TypeError, struct.error) as error:
        parser.exit(1, f'ERROR: {error}\n')
    print(json.dumps({'output': str(args.output), 'count': len(result), 'stations': result}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
