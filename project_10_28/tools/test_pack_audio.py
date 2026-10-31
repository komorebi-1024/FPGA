"""Tests use temporary WAVs/images only; the user's image is read-only input."""
from pathlib import Path
import hashlib
import shutil
import struct
import tempfile
import unittest
import wave
import zlib

from pack_audio import ROOT, pack_image, read_pcm, write_test_tone


def u16(data, offset):
    return struct.unpack_from('<H', data, offset)[0]


def u32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]


class AudioPackingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = ROOT / '01_Assets/WestLake_TF_128MiB.img'
        cls.original_hash = hashlib.sha256(cls.original.read_bytes()).hexdigest()

    @classmethod
    def tearDownClass(cls):
        assert hashlib.sha256(cls.original.read_bytes()).hexdigest() == cls.original_hash

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='westlake-audio-test-')
        self.directory = Path(self.temporary.name)
        self.audio = self.directory / 'Audio'
        self.audio.mkdir()
        self.output = self.directory / 'audio.img'

    def tearDown(self):
        self.temporary.cleanup()

    def wav(self, number, frames, channels=2, width=2, rate=48000):
        path = self.audio / f'music{number:02d}.wav'
        raw = bytes((i * 37 + number) & 255 for i in range(frames * channels * width))
        with wave.open(str(path), 'wb') as stream:
            stream.setparams((channels, width, rate, 0, 'NONE', 'not compressed'))
            stream.writeframes(raw)
        return raw

    def image_copy(self):
        path = self.directory / 'source.img'
        shutil.copyfile(self.original, path)
        return path

    def check_image(self, source, expected):
        before, after = source.read_bytes(), self.output.read_bytes()
        self.assertEqual(len(after), len(before))
        self.assertEqual(after[:512], before[:512])
        self.assertEqual(after[2056 * 512:2057 * 512], before[2056 * 512:2057 * 512])
        boot = after[2048 * 512:2049 * 512]
        reserved, fat_size = u16(boot, 14), u32(boot, 36)
        fat_start = 2048 + reserved
        data_start = fat_start + fat_size * 2
        clusters = u32(boot, 32) - reserved - fat_size * 2
        fat = after[fat_start * 512:(fat_start + fat_size) * 512]
        self.assertEqual(fat, after[(fat_start + fat_size) * 512:data_start * 512])
        for lba in (2048, 2054):
            self.assertEqual(after[lba * 512:(lba + 1) * 512], before[lba * 512:(lba + 1) * 512])

        def chain(first):
            result = []
            while first < 0x0ffffff8:
                self.assertGreaterEqual(first, 2)
                self.assertLess(first, clusters + 2)
                self.assertNotIn(first, result)
                result.append(first)
                first = u32(fat, first * 4) & 0x0fffffff
            return result

        root = chain(u32(boot, 44))
        directory = b''.join(after[(data_start + c - 2) * 512:(data_start + c - 1) * 512] for c in root)
        old_directory = b''.join(before[(data_start + c - 2) * 512:(data_start + c - 1) * 512] for c in root)
        # All old live directory entries and their data must remain byte-identical.
        for offset in range(0, len(old_directory), 32):
            entry = old_directory[offset:offset + 32]
            if entry[0] == 0:
                break
            if entry[0] == 0xe5 or entry[11] == 0x0f:
                continue
            self.assertEqual(directory[offset:offset + 32], entry)
            first = u16(entry, 26) | (u16(entry, 20) << 16)
            for c in chain(first):
                pos = (data_start + c - 2) * 512
                self.assertEqual(after[pos:pos + 512], before[pos:pos + 512])
        catalog = after[2057 * 512:2058 * 512]
        self.assertEqual(catalog[:16], b'WLPCM001' + bytes((len(expected), 2, 16, 0)) + struct.pack('<I', 48000))
        self.assertEqual(catalog[16 + 16 * len(expected):], bytes(496 - 16 * len(expected)))
        for index, raw in enumerate(expected):
            lba, frames, crc, zero = struct.unpack_from('<IIII', catalog, 16 + index * 16)
            self.assertEqual((frames, crc, zero), (len(raw) // 4, zlib.crc32(raw) & 0xffffffff, 0))
            name = f'MUSIC{index + 1:02d} PCM'.encode()
            offset = next(o for o in range(0, len(directory), 32) if directory[o:o + 11] == name)
            entry = directory[offset:offset + 32]
            self.assertEqual(entry[11], 0x20)
            self.assertEqual(u32(entry, 28), len(raw))
            first = u16(entry, 26) | (u16(entry, 20) << 16)
            run = chain(first)
            self.assertEqual(run, list(range(first, first + (len(raw) + 511) // 512)))
            self.assertEqual(lba, data_start + first - 2)
            self.assertEqual(after[lba * 512:lba * 512 + len(raw)], raw)
            self.assertEqual(after[lba * 512 + len(raw):(lba + len(run)) * 512], bytes(len(run) * 512 - len(raw)))
        free = sum((u32(fat, c * 4) & 0x0fffffff) == 0 for c in range(2, clusters + 2))
        next_free = next((c for c in range(2, clusters + 2) if u32(fat, c * 4) & 0x0fffffff == 0), 0xffffffff)
        for lba in (2049, 2055):
            self.assertEqual(struct.unpack_from('<II', after, lba * 512 + 488), (free, next_free))
            self.assertEqual(after[lba * 512:lba * 512 + 488], before[lba * 512:lba * 512 + 488])

    def test_four_tracks_and_repeat(self):
        raws = [self.wav(n, frames) for n, frames in enumerate((1, 130, 257, 129), 1)]
        report = pack_image(self.original, self.output, self.audio)
        self.assertEqual(len(report), 4)
        self.check_image(self.original, raws)
        first_hash = hashlib.sha256(self.output.read_bytes()).hexdigest()
        pack_image(self.original, self.output, self.audio)
        self.assertEqual(hashlib.sha256(self.output.read_bytes()).hexdigest(), first_hash)

    def test_empty_directory_is_silent(self):
        self.assertEqual(pack_image(self.original, self.output, self.audio), [])
        self.check_image(self.original, [])

    def test_existing_extra_file_and_fragmented_free_space(self):
        source = self.image_copy()
        data = bytearray(source.read_bytes())
        boot = data[2048 * 512:2049 * 512]
        fat_size, fat_start = u32(boot, 36), 2048 + u16(boot, 14)
        data_start = fat_start + 2 * fat_size
        fat = data[fat_start * 512:(fat_start + fat_size) * 512]
        first_free = next(c for c in range(2, len(fat) // 4) if u32(fat, c * 4) == 0)
        occupied = first_free + 1
        for start in (fat_start, fat_start + fat_size):
            struct.pack_into('<I', data, start * 512 + occupied * 4, 0x0fffffff)
        entry = bytearray(32)
        entry[:11], entry[11] = b'EXTRA   BIN', 0x20
        struct.pack_into('<H', entry, 20, occupied >> 16)
        struct.pack_into('<H', entry, 26, occupied & 65535)
        struct.pack_into('<I', entry, 28, 512)
        root_start = data_start * 512
        data[root_start + 24 * 32:root_start + 25 * 32] = entry
        data[(data_start + occupied - 2) * 512:(data_start + occupied - 1) * 512] = b'X' * 512
        source.write_bytes(data)
        raw = self.wav(1, 129)  # two clusters cannot fit in the one-cluster hole
        report = pack_image(source, self.output, self.audio)
        self.assertEqual(report[0]['lba'], data_start + occupied + 1 - 2)
        self.check_image(source, [raw])

    def test_invalid_wavs_and_numbering(self):
        for kwargs in ({'channels': 1}, {'width': 1}, {'rate': 44100}):
            with self.subTest(kwargs=kwargs):
                self.wav(1, 8, **kwargs)
                with self.assertRaisesRegex(ValueError, '48000 Hz'):
                    pack_image(self.original, self.output, self.audio)
                self.assertFalse(self.output.exists())
        self.wav(1, 8)
        path = self.audio / 'music01.wav'
        data = bytearray(path.read_bytes())
        struct.pack_into('<H', data, 20, 3)  # IEEE float rather than PCM
        path.write_bytes(data)
        with self.assertRaises(ValueError):
            read_pcm(path)
        path.write_bytes(data[:-1])
        with self.assertRaisesRegex(ValueError, 'RIFF length'):
            read_pcm(path)
        path.unlink()
        self.wav(2, 8)
        with self.assertRaisesRegex(ValueError, 'consecutive'):
            pack_image(self.original, self.output, self.audio)
        self.wav(5, 8)
        with self.assertRaisesRegex(ValueError, 'music04'):
            pack_image(self.original, self.output, self.audio)

    def test_overwrite_and_invalid_fat_rejected(self):
        with self.assertRaisesRegex(ValueError, 'must differ'):
            pack_image(self.original, self.original, self.audio)
        source = self.image_copy()
        with source.open('r+b') as stream:
            boot = source.read_bytes()[2048 * 512:2049 * 512]
            fat_start = 2048 + u16(boot, 14)
            stream.seek(fat_start * 512 + 8)
            stream.write(b'\x11')
        with self.assertRaisesRegex(ValueError, 'FAT copies differ'):
            pack_image(source, self.output, self.audio)
        self.assertFalse(self.output.exists())

    def test_no_space_or_directory_slot_does_not_touch_output(self):
        source = self.image_copy()
        data = bytearray(source.read_bytes())
        boot = data[2048 * 512:2049 * 512]
        fat_start, fat_size = 2048 + u16(boot, 14), u32(boot, 36)
        clusters = u32(boot, 32) - u16(boot, 14) - 2 * fat_size
        for copy in range(2):
            for c in range(2, clusters + 2):
                offset = (fat_start + copy * fat_size) * 512 + c * 4
                if u32(data, offset) == 0:
                    struct.pack_into('<I', data, offset, 0x0fffffff)
        source.write_bytes(data)
        self.wav(1, 8)
        self.output.write_bytes(b'existing output preserved on failure')
        with self.assertRaisesRegex(ValueError, 'contiguous free space'):
            pack_image(source, self.output, self.audio)
        self.assertEqual(self.output.read_bytes(), b'existing output preserved on failure')
        shutil.copyfile(self.original, source)
        with source.open('r+b') as stream:
            start = (fat_start + 2 * fat_size) * 512 + 24 * 32
            stream.seek(start)
            stream.write(b'OCCUPIEDBIN\x20' + bytes(20))
            for slot in range(25, 32):
                stream.write(b'OCCUPIEDBIN\x20' + bytes(20))
        with self.assertRaisesRegex(ValueError, 'free entries'):
            pack_image(source, self.output, self.audio)

    def test_owned_name_collision_and_explicit_tone(self):
        raw = self.wav(1, 8)
        pack_image(self.original, self.output, self.audio)
        self.check_image(self.original, [raw])
        with self.assertRaisesRegex(ValueError, 'already contains MUSIC'):
            pack_image(self.output, self.directory / 'other.img', self.audio)
        with tempfile.TemporaryDirectory(prefix='westlake-tone-test-') as directory:
            write_test_tone(directory)
            tone = read_pcm(Path(directory) / 'music01.wav')
            self.assertEqual(len(tone), 48000 * 4)
            self.assertNotEqual(tone, bytes(len(tone)))
            pack_image(self.original, self.output, directory)
            self.check_image(self.original, [tone])


if __name__ == '__main__':
    unittest.main()
