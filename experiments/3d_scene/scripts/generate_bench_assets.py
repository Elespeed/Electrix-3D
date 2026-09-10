#!/usr/bin/env python3
"""Generate deterministic, bounded SK3D-v4 benchmark assets S0..S4."""
from __future__ import annotations
import argparse, hashlib, json, struct
from pathlib import Path

# Benchmark scale is geometry-only: keep every scene a single mesh so the
# comparison does not measure multi-mesh scheduling or command overhead.
SIZES = {"S0": (16,24,1), "S1": (32,48,1), "S2": (64,96,1), "S3": (96,144,1), "S4": (128,192,1)}
MAGIC = 0x534B3344  # SK3D (the v4 marker is carried in header word3)

def words_for(v: int, t: int, m: int) -> list[int]:
    words = [MAGIC, v, t, 4 | (m << 8)]
    vb = tb = 0
    for mesh in range(m):
        nv = v // m + (mesh < v % m); nt = t // m + (mesh < t % m)
        words += [vb, nv, tb, nt]; vb += nv; tb += nt
    for index in range(v):
        # Q8.8 coordinates in a deterministic, non-degenerate ring.
        x = ((index * 37) % 181 - 90) << 8; y = ((index * 61) % 151 - 75) << 8; z = ((index * 29) % 121 - 60) << 8
        words += [((x & 0xffff) << 16) | (y & 0xffff), z & 0xffff]
    for index in range(t):
        base = (index * 3) % v
        words += [base | (((base + 1) % v) << 8) | (((base + 2) % v) << 16), (index * 29) & 0xff]
    return words

def write_model(root: Path, name: str, dims: tuple[int,int,int]) -> dict:
    out = root / "experiments" / "3d_scene" / "assets" / name
    out.mkdir(parents=True, exist_ok=True)
    words = words_for(*dims)
    binary = b"".join(struct.pack("<I", word) for word in words)
    (out / "model.s3d.bin").write_bytes(binary)
    (out / "model.s3d.mif").write_text("".join(f"{word:032b}\n" for word in words), encoding="ascii")
    return {"id": name, "V": dims[0], "T": dims[1], "M": dims[2], "bytes": len(binary), "path": str((out / "model.s3d.bin").relative_to(root)).replace("\\", "/"), "sha256": hashlib.sha256(binary).hexdigest()}

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--root", type=Path, required=True); args = ap.parse_args()
    models = [write_model(args.root, key, value) for key, value in SIZES.items()]
    manifest = {"schema": "scene-controller-assets/v1", "generator": "generate_bench_assets.py/v1", "models": models}
    path = args.root / "experiments" / "3d_scene" / "assets" / "manifest.json"; path.parent.mkdir(parents=True, exist_ok=True)
    # The tracked manifest uses CRLF; preserve it on both Windows and WSL.
    path.write_bytes((json.dumps(manifest, indent=2) + "\n").replace("\n", "\r\n").encode("utf-8"))
    print(path)
    return 0
if __name__ == "__main__": raise SystemExit(main())
