#!/usr/bin/env python
from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


DEFAULT_MODELSIM_ROOT = Path(r"D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim")


def default_manifest_path(modelsim_root: Path) -> Path:
    return modelsim_root / "vcdcfg" / "manifest.yaml"


def load_manifest(path: str | Path) -> dict[str, Any]:
    manifest_path = Path(path).resolve()
    data = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Manifest at {manifest_path} must be a mapping")
    return data


def substitute_tb(text: str, tb: str) -> str:
    return text.replace("{tb}", tb)


def unique_ordered(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def resolve_profiles(manifest: dict[str, Any], tb: str, phase: str | None, explicit_profiles: list[str]) -> list[str]:
    profiles = list(explicit_profiles)
    if phase:
        phase_cfg = manifest.get("phases", {}).get(phase, {})
        profiles = list(phase_cfg.get("profiles", [])) + profiles
    return unique_ordered([name for name in profiles if name])


def profile_patterns(manifest: dict[str, Any], tb: str, profile_names: list[str]) -> list[str]:
    profiles = manifest.get("profiles", {})
    patterns: list[str] = []
    for name in profile_names:
        profile = profiles.get(name, {})
        for pattern in profile.get("patterns", []):
            patterns.append(substitute_tb(str(pattern), tb))
    return unique_ordered(patterns)


def snapshot_signals(manifest: dict[str, Any], tb: str, phase: str | None, profile_names: list[str]) -> list[str]:
    signals: list[str] = []
    if phase:
        phase_cfg = manifest.get("phases", {}).get(phase, {})
        for signal in phase_cfg.get("snapshot_signals", []):
            signals.append(substitute_tb(str(signal), tb))
    profiles = manifest.get("profiles", {})
    for name in profile_names:
        profile = profiles.get(name, {})
        for signal in profile.get("snapshot_signals", []):
            signals.append(substitute_tb(str(signal), tb))
    return unique_ordered(signals)


def checkpoint_regex(manifest: dict[str, Any]) -> str:
    return str(manifest.get("checkpoint_rules", {}).get("regex", r"\[GRU_TB\]\s+(?P<checkpoint>[A-Z0-9_]+)"))


def phase_from_checkpoint(manifest: dict[str, Any], checkpoint: str | None) -> str | None:
    if not checkpoint:
        return None
    phase_map = manifest.get("checkpoint_rules", {}).get("phase_map", {})
    if checkpoint in phase_map:
        return str(phase_map[checkpoint])
    phase_prefixes = manifest.get("checkpoint_rules", {}).get("phase_prefixes", {})
    for prefix, phase in phase_prefixes.items():
        if checkpoint.startswith(prefix):
            return str(phase)
    return None


def noise_rules(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    rules = manifest.get("noise_rules", [])
    if not isinstance(rules, list):
        raise ValueError("noise_rules must be a list")
    return [rule for rule in rules if isinstance(rule, dict)]
