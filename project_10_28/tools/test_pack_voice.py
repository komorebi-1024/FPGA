"""Station packing tests; all generated WAVs/images live in temporary folders."""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import tempfile
import unittest
import wave
import zlib

from pack_audio import ROOT, SECTOR, u16, u32
from pack_voice import pack_image


def layout(image):
    part = u32(image, 454)
    boot = image[part * SECTOR:(part + 1) * SECTOR]
    reserved, size = u16(boot, 14), u32(boot, 36)
    fat_start = part + reserved
    data_start = fat_start + 2 * size
    clusters = u32(boot, 32) - reserved - 2 * size
    fat = image[fat_start * SECTOR:(fat_start + size) * SECTOR]
    return part, boot, fat_start, size, data_start, clusters, fat


def chain(first, fat):
    result, seen = [], set()
    while first < 0x0ffffff8:
        assert 2 <= first < len(fat) // 4 and first not in seen
        seen.add(first)
        result.append(first)
        first = u32(fat, first * 4) & 0x0fffffff
    return result


def directory(image):
    _, boot, _, _, data_start, _, fat = layout(image)
    root = chain(u32(boot, 44), fat)
    content = b''.join(image[(data_start + c - 2) * SECTOR:(data_start + c - 1) * SECTOR] for c in root)
    return root, content


class VoicePackingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = ROOT / '01_Assets/WestLake_TF_Audio_128MiB.img'
        cls.original_hash = hashlib.sha256(cls.original.read_bytes()).hexdigest()

    @classmethod
    def tearDownClass(cls):
        assert hashlib.sha256(cls.original.read_bytes()).hexdigest() == cls.original_hash

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='westlake-voice-test-')
        self.folder = Path(self.temporary.name)
        self.voice = self.folder / 'Voice'
        self.voice.mkdir()
        self.output = self.folder / 'voice.img'
        self.metadata = {'sample_rate': 48000, 'stations': []}
        self.raw = []
        for index, frames in enumerate((132, 257, 129, 385)):
            raw = bytes((j * 29 + index * 73) & 255 for j in range(frames * 4))
            self.raw.append(raw)
            name = f'station{index + 1:02d}.wav'
            with wave.open(str(self.voice / name), 'wb') as stream:
                stream.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
                stream.writeframes(raw)
            cues = (0, 31, 93, frames)
            self.metadata['stations'].append({'id': index, 'wav': name, 'segments': [
                {'text': text, 'start_frame': cues[i], 'end_frame': cues[i + 1]}
                for i, text in enumerate(('本站测试站。', '山水之间，风景如画。', '请带好随身物品。'))]})
        self.write_metadata()

    def tearDown(self):
        self.temporary.cleanup()

    def write_metadata(self):
        (self.voice / 'narration.json').write_text(json.dumps(self.metadata, ensure_ascii=False), 'utf-8')

    def image_copy(self):
        source = self.folder / 'source.img'
        shutil.copyfile(self.original, source)
        return source

    def check_image(self, source):
        before, after = source.read_bytes(), self.output.read_bytes()
        self.assertEqual(len(after), 128 * 1024 * 1024)
        self.assertEqual(after[:512], before[:512])
        self.assertEqual(after[2056 * SECTOR:2058 * SECTOR], before[2056 * SECTOR:2058 * SECTOR])
        part, boot, fat_start, size, data_start, clusters, fat = layout(after)
        self.assertEqual(fat, after[(fat_start + size) * SECTOR:data_start * SECTOR])
        new_root, new_directory = directory(after)
        old_root, old_directory = directory(before)
        self.assertEqual(new_root[:len(old_root)], old_root)
        old_files = 0
        for offset in range(0, len(old_directory), 32):
            entry = old_directory[offset:offset + 32]
            if entry[0] == 0:
                break
            if entry[0] == 0xe5 or entry[11] == 0x0f:
                continue
            self.assertEqual(new_directory[offset:offset + 32], entry)
            old_files += 1
            first = u16(entry, 26) | u16(entry, 20) << 16
            if u32(entry, 28):
                for cluster in chain(first, fat):
                    pos = (data_start + cluster - 2) * SECTOR
                    self.assertEqual(after[pos:pos + SECTOR], before[pos:pos + SECTOR])
        self.assertGreaterEqual(old_files, 26)  # 24 pictures and at least the two selected songs.
        self.assertIn(0, new_directory[::32])
        catalog = after[2058 * SECTOR:2059 * SECTOR]
        self.assertEqual(catalog[:16], b'WLVOC001' + bytes((4, 2, 16, 3)) + struct.pack('<I', 48000))
        self.assertEqual(catalog[144:], bytes(368))
        for index, raw in enumerate(self.raw):
            start = 16 + index * 32
            lba, frames, cue1, cue2, crc = struct.unpack_from('<IIIII', catalog, start)
            self.assertEqual((frames, cue1, cue2, crc), (len(raw) // 4, 31, 93, zlib.crc32(raw) & 0xffffffff))
            self.assertEqual(catalog[start + 20:start + 23], bytes(len(s['text']) for s in self.metadata['stations'][index]['segments']))
            self.assertEqual(catalog[start + 23:start + 32], bytes(9))
            name = f'VOICE{index + 1:02d} PCM'.encode()
            offset = next(o for o in range(0, len(new_directory), 32) if new_directory[o:o + 11] == name)
            entry = new_directory[offset:offset + 32]
            first = u16(entry, 26) | u16(entry, 20) << 16
            run = chain(first, fat)
            self.assertEqual(run, list(range(first, first + (len(raw) + 511) // 512)))
            self.assertEqual((lba, u32(entry, 28)), (data_start + first - 2, len(raw)))
            self.assertEqual(after[lba * SECTOR:lba * SECTOR + len(raw)], raw)
            self.assertEqual(after[lba * SECTOR + len(raw):(lba + len(run)) * SECTOR], bytes(len(run) * SECTOR - len(raw)))
        free = sum((u32(fat, c * 4) & 0x0fffffff) == 0 for c in range(2, clusters + 2))
        next_free = next((c for c in range(2, clusters + 2) if u32(fat, c * 4) & 0x0fffffff == 0), 0xffffffff)
        for lba in (part + u16(boot, 48), part + u16(boot, 50) + u16(boot, 48)):
            self.assertEqual(struct.unpack_from('<II', after, lba * SECTOR + 488), (free, next_free))
        return len(new_root)

    def test_four_voices_preserve_music_and_repeat(self):
        report = pack_image(self.original, self.output, self.voice)
        self.assertEqual(len(report), 4)
        self.check_image(self.original)
        digest = hashlib.sha256(self.output.read_bytes()).hexdigest()
        pack_image(self.original, self.output, self.voice)
        self.assertEqual(hashlib.sha256(self.output.read_bytes()).hexdigest(), digest)
        self.assertEqual(report[0]['pcm_sha256'], hashlib.sha256(self.raw[0]).hexdigest())

    def test_full_root_directory_is_extended(self):
        source = self.image_copy()
        data = bytearray(source.read_bytes())
        root, content = directory(data)
        _, _, _, _, data_start, _, _ = layout(data)
        content = bytearray(content)
        ended = False
        for offset in range(0, len(content), 32):
            ended = ended or content[offset] == 0
            if ended:
                entry = bytearray(32)
                entry[:11] = (f'D{offset:07d}' + 'TXT').encode()
                entry[11] = 0x20  # Valid zero-length file, no data cluster.
                content[offset:offset + 32] = entry
        for index, cluster in enumerate(root):
            offset = (data_start + cluster - 2) * SECTOR
            data[offset:offset + SECTOR] = content[index * SECTOR:(index + 1) * SECTOR]
        source.write_bytes(data)
        pack_image(source, self.output, self.voice)
        self.assertEqual(self.check_image(source), len(root) + 1)

    def test_bad_cues_and_character_counts_preserve_existing_output(self):
        self.output.write_bytes(b'previous-good-output')
        original = json.loads(json.dumps(self.metadata))
        mutations = [
            lambda: self.metadata['stations'][0]['segments'][0].update(start_frame=1),
            lambda: self.metadata['stations'][0]['segments'][1].update(end_frame=31),
            lambda: self.metadata['stations'][0]['segments'][2].update(end_frame=131),
            lambda: self.metadata['stations'][0]['segments'][0].update(text=''),
            lambda: self.metadata['stations'][0]['segments'][0].update(text='字' * 32),
            lambda: self.metadata['stations'][0].update(id=1),
            lambda: self.metadata['stations'][0].update(wav='../station01.wav'),
        ]
        for mutate in mutations:
            self.metadata = json.loads(json.dumps(original))
            mutate()
            self.write_metadata()
            with self.assertRaises(ValueError):
                pack_image(self.original, self.output, self.voice)
            self.assertEqual(self.output.read_bytes(), b'previous-good-output')

    def test_invalid_wav_is_rejected(self):
        with wave.open(str(self.voice / 'station01.wav'), 'wb') as stream:
            stream.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
            stream.writeframes(b'\0' * 264)
        with self.assertRaisesRegex(ValueError, '48000 Hz'):
            pack_image(self.original, self.output, self.voice)
        self.assertFalse(self.output.exists())

    def test_invalid_metadata_structure_is_rejected(self):
        for metadata in ([], None, {'sample_rate': 48000, 'stations': [None] * 4},
                         {'sample_rate': 48000, 'stations': [{'id': 0}] * 4}):
            (self.voice / 'narration.json').write_text(json.dumps(metadata), 'utf-8')
            with self.assertRaises(ValueError):
                pack_image(self.original, self.output, self.voice)
            self.assertFalse(self.output.exists())

    def test_occupied_catalog_and_voice_name_collision_are_rejected(self):
        source = self.image_copy()
        with source.open('r+b') as stream:
            stream.seek(2058 * SECTOR)
            stream.write(b'UNKNOWN!')
        with self.assertRaisesRegex(ValueError, 'reserved sector'):
            pack_image(source, self.output, self.voice)
        shutil.copyfile(self.original, source)
        data = bytearray(source.read_bytes())
        root, content = directory(data)
        _, _, _, _, data_start, _, _ = layout(data)
        slot = next(o for o in range(0, len(content), 32) if content[o] == 0)
        sector = slot // SECTOR
        pos = (data_start + root[sector] - 2) * SECTOR + slot % SECTOR
        data[pos:pos + 11] = b'VOICE01 PCM'
        data[pos + 11] = 0x20
        source.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'already contains'):
            pack_image(source, self.output, self.voice)

    def test_fragmented_or_full_free_space_is_rejected(self):
        source = self.image_copy()
        initial = source.read_bytes()
        for fragmented in (True, False):
            data = bytearray(initial)
            _, _, fat_start, size, _, clusters, fat = layout(data)
            modified = bytearray(fat)
            for cluster in range(2, clusters + 2):
                if u32(fat, cluster * 4) & 0x0fffffff == 0:
                    value = 0 if fragmented and cluster % 2 == 0 else 0x0fffffff
                    struct.pack_into('<I', modified, cluster * 4, value)
            for start in (fat_start, fat_start + size):
                data[start * SECTOR:(start + size) * SECTOR] = modified
            source.write_bytes(data)
            self.output.write_bytes(b'retain-on-failure')
            with self.assertRaisesRegex(ValueError, 'contiguous free space'):
                pack_image(source, self.output, self.voice)
            self.assertEqual(self.output.read_bytes(), b'retain-on-failure')

    def test_bad_fat_and_in_place_output_are_rejected(self):
        source = self.image_copy()
        with source.open('r+b') as stream:
            stream.seek(2080 * SECTOR + 8)
            stream.write(b'\0\0\0\0')
        with self.assertRaisesRegex(ValueError, 'FAT copies'):
            pack_image(source, self.output, self.voice)
        with self.assertRaisesRegex(ValueError, 'must differ'):
            pack_image(self.original, self.original, self.voice)


if __name__ == '__main__':
    unittest.main()
