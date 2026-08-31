#!/usr/bin/env python
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from manifest_utils import DEFAULT_MODELSIM_ROOT, default_manifest_path, load_manifest, profile_patterns, resolve_profiles


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a temporary VCD cfg based on a checked-in preset and manifest profiles.")
    parser.add_argument("--modelsim-root", default=str(DEFAULT_MODELSIM_ROOT))
    parser.add_argument("--manifest")
    parser.add_argument("--tb", required=True)
    parser.add_argument("--base", default="lite")
    parser.add_argument("--phase")
    parser.add_argument("--profile", action="append", default=[])
    parser.add_argument("--add", action="append", default=[])
    parser.add_argument("--tag", default="ai")
    return parser.parse_args()


def normalize_line(text: str) -> str:
    return text.strip()


def expand_cfg(modelsim_root: Path, manifest_path: Path, tb: str, base: str, phase: str | None, profiles: list[str], add: list[str], tag: str) -> dict[str, object]:
    base_file = modelsim_root / "vcdcfg" / f"{tb}.{base}.lst"
    if not base_file.exists():
        raise FileNotFoundError(base_file)

    manifest = load_manifest(manifest_path)
    selected_profiles = resolve_profiles(manifest, tb, phase, profiles)
    profile_lines = profile_patterns(manifest, tb, selected_profiles)

    lines = base_file.read_text(encoding="utf-8").splitlines()
    merged: list[str] = []
    seen: set[str] = set()

    for line in lines:
        norm = normalize_line(line)
        if not norm or norm.startswith("#"):
            merged.append(line)
            continue
        if norm not in seen:
            seen.add(norm)
            merged.append(norm)

    added: list[str] = []
    for extra in profile_lines + add:
        norm = normalize_line(extra)
        if norm and norm not in seen:
            seen.add(norm)
            merged.append(norm)
            added.append(norm)

    digest_src = "\n".join(selected_profiles + sorted(added)).encode("utf-8")
    digest = hashlib.sha1(digest_src).hexdigest()[:8]
    cfg_name = f"{base}_{tag}_{digest}"
    out_dir = modelsim_root / "build" / "ai_vcdcfg"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{tb}.{cfg_name}.lst"
    out_file.write_text("\n".join(merged) + "\n", encoding="utf-8")

    return {
        "ok": True,
        "tb": tb,
        "base": base,
        "phase": phase,
        "selected_profiles": selected_profiles,
        "cfg_name": cfg_name,
        "vcdcfg_dir": str(out_dir),
        "cfg_file": str(out_file),
        "added": added,
        "line_count": len(merged),
    }


def main() -> None:
    args = parse_args()
    modelsim_root = Path(args.modelsim_root).resolve()
    manifest_path = Path(args.manifest).resolve() if args.manifest else default_manifest_path(modelsim_root).resolve()
    try:
        payload = expand_cfg(modelsim_root, manifest_path, args.tb, args.base, args.phase, args.profile, args.add, args.tag)
    except FileNotFoundError as exc:
        print(json.dumps({"ok": False, "error": {"code": "BASE_CFG_NOT_FOUND", "message": str(exc)}}))
        sys.exit(1)
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
