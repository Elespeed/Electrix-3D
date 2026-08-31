import binascii
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sk3d_package import Asset, MAGIC, PackageError, _read_asset, build_package, mif_text


class Sk3dPackageTests(unittest.TestCase):
    def test_layout_alignment_crc_and_mif(self):
        a = Asset("blade", struct.pack("<4I", 0x534B3344, 1, 1, 4), 1, 4)
        b = Asset("robotss", struct.pack("<4I", 0x534B3344, 2, 2, 4) + b"abcd", 5, 4)
        image, entries = build_package([a, b])
        self.assertEqual(struct.unpack_from("<I", image)[0], MAGIC)
        self.assertEqual(entries[0]["offset"] % 16, 0)
        self.assertEqual(entries[1]["offset"] % 16, 0)
        self.assertEqual(entries[1]["crc32"], f"0x{binascii.crc32(b.payload) & 0xffffffff:08x}")
        self.assertEqual(b"".join(struct.pack("<I", int(line, 2)) for line in mif_text(image).splitlines()), image)

    def test_rejects_duplicate_name_and_overflow(self):
        payload = struct.pack("<4I", 0x534B3344, 1, 1, 4)
        with self.assertRaises(PackageError):
            build_package([Asset("same", payload, 1, 4), Asset("same", payload, 1, 4)])
        with self.assertRaises(PackageError):
            build_package([Asset(str(index), payload, 1, 4) for index in range(17)])

    def test_rejects_unsupported_version(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "old.s3d.bin"
            path.write_bytes(struct.pack("<4I", 0x534B3344, 1, 1, 1))
            with self.assertRaisesRegex(PackageError, "V2/V3/V4"):
                _read_asset(path)
