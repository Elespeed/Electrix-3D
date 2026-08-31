#!/usr/bin/env python3
"""Build the repository-wide 3D asset provenance manifest."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSET_ROOT = ROOT / "assets/3d"


def file_record(path: Path) -> dict[str, str]:
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def mif_counts(path: Path) -> dict[str, int]:
    words = [int(line.strip(), 2) for line in path.read_text(encoding="ascii").splitlines()[:4]]
    if len(words) != 4 or words[0] != 0x534B3344:
        raise ValueError(f"not an SK3D image: {path}")
    version = words[3] & 0xFF
    return {
        "vertices": words[1],
        "triangles": words[2],
        "meshes": ((words[3] >> 8) & 0xFF) if version == 4 else 1,
    }


def generation_command(asset: str, variant: str) -> str:
    if variant == "legacy_v3":
        return "legacy-import: preserve the pre-migration bytes"
    target = "convert-v4" if variant == "v4" else "convert-v3"
    return f"make -f tools/3d_gen/Makefile ASSET={asset} {target}"


def main() -> None:
    assets = []
    generated_root = ASSET_ROOT / "generated"
    for asset_dir in sorted(path for path in generated_root.iterdir() if path.is_dir() and not path.name.startswith("_")):
        source_dir = ASSET_ROOT / "sources" / asset_dir.name
        variants = []
        for variant_dir in sorted(path for path in asset_dir.iterdir() if path.is_dir()):
            mif_files = sorted(variant_dir.glob("*.s3d.mif"))
            representative = next((path for path in mif_files if "_shade" in path.stem), mif_files[0] if mif_files else None)
            if representative is None:
                continue
            version_word = int(representative.read_text(encoding="ascii").splitlines()[3], 2)
            variants.append({
                "id": variant_dir.name,
                "format_version": version_word & 0xFF,
                "counts": mif_counts(representative),
                "generation_command": generation_command(asset_dir.name, variant_dir.name),
                "outputs": [file_record(path) for path in sorted(variant_dir.iterdir()) if path.is_file()],
            })
        assets.append({
            "asset_id": asset_dir.name,
            "source_files": [file_record(path) for path in sorted(source_dir.iterdir()) if path.is_file()] if source_dir.exists() else [],
            "variants": variants,
        })

    package_dir = ASSET_ROOT / "packages" / "br01"
    fixtures_dir = ASSET_ROOT / "fixtures"
    manifest = {
        "schema": "sketchbook-3d-assets",
        "schema_version": 1,
        "assets": assets,
        "packages": [{
            "package_id": "br01",
            "generation_command": "make -f tools/3d_gen/Makefile package-br01",
            "files": [file_record(path) for path in sorted(package_dir.iterdir()) if path.is_file()],
        }],
        "fixtures": [file_record(path) for path in sorted(fixtures_dir.iterdir()) if path.is_file()],
    }
    (ASSET_ROOT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
