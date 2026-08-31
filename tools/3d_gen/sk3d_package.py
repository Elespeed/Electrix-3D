#!/usr/bin/env python3
"""Pack independent SK3D assets into one S3PK ExtRAM image."""
from __future__ import annotations

import argparse
import binascii
import json
from dataclasses import dataclass
from pathlib import Path
import struct
from typing import Sequence

MAGIC = 0x5333504B  # S3PK
VERSION = 1
HEADER_BYTES = 16
ENTRY_BYTES = 32
ALIGNMENT = 16
SK3D_MAGIC = 0x534B3344
SUPPORTED_SK3D_VERSIONS = {2, 3, 4}


class PackageError(ValueError):
    pass


@dataclass(frozen=True)
class Asset:
    name: str
    payload: bytes
    mesh_count: int
    version: int


def _align(value: int) -> int:
    return (value + ALIGNMENT - 1) & -ALIGNMENT


def _read_asset(path: Path, name: str | None = None) -> Asset:
    payload = path.read_bytes()
    if len(payload) < 16 or len(payload) % 4:
        raise PackageError(f"{path}: SK3D payload must be a non-empty 32-bit word stream")
    magic, _, _, version = struct.unpack_from("<4I", payload)
    version = version & 0xff
    if magic != SK3D_MAGIC or version not in SUPPORTED_SK3D_VERSIONS:
        raise PackageError(f"{path}: only SK3D V2/V3/V4 assets can be packaged")
    metadata_path = path.with_suffix("").with_suffix(".json") if path.name.endswith(".s3d.bin") else path.with_suffix(".json")
    if not metadata_path.is_file():
        raise PackageError(f"{path}: missing companion metadata {metadata_path.name}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("format") == "SK3D" and metadata.get("version") == version:
        mesh_count = metadata.get("mesh_count")
        if not isinstance(mesh_count, int):
            raise PackageError(f"{metadata_path}: expected SK3D metadata with mesh_count")
    elif version in {2, 3} and metadata.get("format") == "lowpoly-model" and metadata.get("version") == 1:
        mesh_count = 1
    else:
        raise PackageError(f"{metadata_path}: expected metadata compatible with payload version {version}")
    return Asset(name or path.stem.removesuffix(".s3d"), payload, mesh_count, version)


def build_package(assets: Sequence[Asset]) -> tuple[bytes, list[dict]]:
    if not assets:
        raise PackageError("at least one asset is required")
    if len(assets) > 16:
        raise PackageError("S3PK V1 supports at most 16 catalog entries")
    names = [asset.name for asset in assets]
    if len(set(names)) != len(names):
        raise PackageError("catalog asset names must be unique")
    if any(not name or len(name.encode("ascii", "strict")) > 16 for name in names):
        raise PackageError("catalog names must be non-empty ASCII strings of at most 16 bytes")
    directory_bytes = len(assets) * ENTRY_BYTES
    payload_offset = _align(HEADER_BYTES + directory_bytes)
    image = bytearray(payload_offset)
    struct.pack_into("<4I", image, 0, MAGIC, VERSION | (len(assets) << 16), directory_bytes, payload_offset)
    entries: list[dict] = []
    offset = payload_offset
    for model_id, asset in enumerate(assets):
        offset = _align(offset)
        if len(image) < offset:
            image.extend(b"\0" * (offset - len(image)))
        crc32 = binascii.crc32(asset.payload) & 0xffffffff
        name_field = asset.name.encode("ascii").ljust(16, b"\0")
        entry_offset = HEADER_BYTES + model_id * ENTRY_BYTES
        struct.pack_into("<4I16s", image, entry_offset,
                         model_id | (asset.version << 8) | (asset.mesh_count << 16),
                         offset, len(asset.payload), crc32, name_field)
        image.extend(asset.payload)
        entries.append({"model_id": model_id, "name": asset.name, "offset": offset,
                        "size": len(asset.payload), "sk3d_version": asset.version,
                        "mesh_count": asset.mesh_count, "crc32": f"0x{crc32:08x}"})
        offset += len(asset.payload)
    return bytes(image), entries


def mif_text(image: bytes) -> str:
    if len(image) % 4:
        raise PackageError("package image must be 32-bit aligned")
    return "".join(f"{word:032b}\n" for (word,) in struct.iter_unpack("<I", image))


def write_catalog_header(path: Path, package_name: str, entries: list[dict]) -> None:
    guard = f"{package_name.upper()}_CATALOG_H"
    lines = [f"#ifndef {guard}", f"#define {guard}", "", "#include \"common_func.h\"", "",
             f"#define {package_name.upper()}_CATALOG_COUNT {len(entries)}u"]
    for entry in entries:
        token = entry["name"].upper().replace("-", "_")
        lines += [f"#define {package_name.upper()}_MODEL_{token} {entry['model_id']}u",
                  f"#define {package_name.upper()}_OFFSET_{token} 0x{entry['offset']:08x}u",
                  f"#define {package_name.upper()}_SIZE_{token} {entry['size']}u"]
    lines += ["", "#endif", ""]
    path.write_text("\n".join(lines), encoding="ascii", newline="\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="package base name, e.g. br01")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("assets", nargs="+", help="SK3D .s3d.bin files, optionally NAME=PATH")
    args = parser.parse_args(argv)
    try:
        assets = []
        for value in args.assets:
            name, separator, raw_path = value.partition("=")
            assets.append(_read_asset(Path(raw_path if separator else value), name if separator else None))
        image, entries = build_package(assets)
    except (OSError, json.JSONDecodeError, PackageError, UnicodeError) as exc:
        parser.error(str(exc))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    base = args.output_dir / args.name
    base.with_suffix(".s3dpkg.bin").write_bytes(image)
    base.with_suffix(".s3dpkg.mif").write_text(mif_text(image), encoding="ascii", newline="\n")
    base.with_suffix(".json").write_text(json.dumps({"format": "S3PK", "version": VERSION,
        "name": args.name, "size": len(image), "entry_count": len(entries), "entries": entries}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_catalog_header(base.with_name(f"{args.name}_catalog.h"), args.name, entries)
    print(f"Wrote {base.with_suffix('.s3dpkg.bin')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
