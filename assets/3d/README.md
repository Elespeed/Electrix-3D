# Shared 3D assets

This directory is the repository-wide source of truth for SketchBook 3D assets.

- `sources/<asset>/` contains hand-authored OBJ, MTL, pivot, and V4 manifest inputs.
- `generated/<asset>/v3|v4/` contains deterministic JSON, MIF, BIN, and SVH outputs.
- `generated/<asset>/legacy_v3/` preserves byte-distinct pre-migration assets still consumed by regression testbenches. Do not delete them merely because a same-named `v3` output exists.
- `packages/br01/` contains the S3PK JSON, MIF/BIN image, and generated C catalog header.
- `fixtures/` contains hand-authored, non-generated simulation fixtures.
- `previews/` contains generated PNG/GIF/report output and is intentionally ignored by Git.

Common commands, run from the repository root:

```powershell
make -f tools/3d_gen/Makefile ASSET=blade convert
make -f tools/3d_gen/Makefile ASSET=robotss convert
make -f tools/3d_gen/Makefile package-br01
python tools/3d_gen/build_asset_manifest.py
```

The Python generators consume `sources` and write `generated`; standalone and SoC testbenches consume MIF files from `generated`, `packages`, or `fixtures`; `sk_os` consumes `packages/br01/br01_catalog.h`. `manifest.json` records source and output paths, V/T/M counts, generation commands, and SHA-256 values.
