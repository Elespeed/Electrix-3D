#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from manifest_utils import DEFAULT_MODELSIM_ROOT, default_manifest_path, load_manifest, resolve_profiles
from vcd_cfg_expand import expand_cfg


def fail(message: str, code: str = "ERROR", **extra: object) -> None:
    payload = {"ok": False, "error": {"code": code, "message": message}}
    if extra:
        payload.update(extra)
    print(json.dumps(payload, indent=2))
    sys.exit(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the project-specific ModelSim batch flow.")
    parser.add_argument("--modelsim-root", default=str(DEFAULT_MODELSIM_ROOT))
    parser.add_argument("--manifest")
    parser.add_argument("--tb", required=True)
    parser.add_argument("--target", default="run-batch", choices=["run-batch", "compile"])
    parser.add_argument("--vcd", action="store_true")
    parser.add_argument("--cfg", default="lite")
    parser.add_argument("--phase")
    parser.add_argument("--profile", action="append", default=[])
    parser.add_argument("--vcdcfg-dir")
    parser.add_argument("--vcd-root")
    parser.add_argument("--out")
    parser.add_argument("--start")
    parser.add_argument("--end")
    parser.add_argument("--trigger")
    parser.add_argument("--pre")
    parser.add_argument("--post")
    parser.add_argument("--extra-var", action="append", default=[])
    parser.add_argument("--check-only", action="store_true")
    return parser.parse_args()


def path_token(text: str) -> str:
    token = text.strip()
    for src, dst in (("/", "_"), ("\\", "_"), (":", "_"), ("*", "all"), ("?", "q"), (" ", ""), (".", "_")):
        token = token.replace(src, dst)
    while "__" in token:
        token = token.replace("__", "_")
    return token.strip("_")


def detect_mode(args: argparse.Namespace) -> str:
    if args.trigger:
        return "trigger"
    if args.start or args.end:
        return "window"
    return "full" if args.vcd else "disabled"


def validate_inputs(args: argparse.Namespace) -> None:
    mode = detect_mode(args)
    if args.target == "compile":
        return
    if mode == "window":
        if not args.start or not args.end:
            fail("Window mode requires both --start and --end", "INVALID_ARGS")
        if args.pre or args.post:
            fail("Window mode does not allow --pre/--post", "INVALID_ARGS")
    if mode == "trigger":
        if args.start or args.end:
            fail("Trigger mode does not allow --start/--end", "INVALID_ARGS")
        if not args.pre or not args.post:
            fail("Trigger mode requires both --pre and --post", "INVALID_ARGS")


def check_project(root: Path, tb: str, cfg: str, vcdcfg_dir: Path | None, manifest_path: Path) -> dict[str, object]:
    makefile = root / "Makefile"
    readme = root / "README.md"
    batch_script = root / "scripts" / "run_batch.do"
    snapshot_script = root / "scripts" / "snapshot.do"
    tb_file = root / "filelist" / f"tb_{tb}.f"
    preset_dir = vcdcfg_dir or (root / "vcdcfg")
    preset_file = preset_dir / f"{tb}.{cfg}.lst"
    checks = {
        "modelsim_root": str(root),
        "makefile": str(makefile),
        "readme": str(readme),
        "batch_script": str(batch_script),
        "snapshot_script": str(snapshot_script),
        "tb_file": str(tb_file),
        "preset_file": str(preset_file),
        "manifest": str(manifest_path),
        "exists": {
            "modelsim_root": root.exists(),
            "makefile": makefile.exists(),
            "readme": readme.exists(),
            "batch_script": batch_script.exists(),
            "snapshot_script": snapshot_script.exists(),
            "tb_file": tb_file.exists(),
            "preset_file": preset_file.exists(),
            "manifest": manifest_path.exists(),
        },
    }
    return checks


def derive_vcd_path(root: Path, tb: str, cfg: str, mode: str, args: argparse.Namespace) -> Path | None:
    if not args.vcd:
        return None
    if args.out:
        return Path(args.out).resolve()
    vcd_root = Path(args.vcd_root).resolve() if args.vcd_root else (root / "vcd").resolve()
    tb_dir = vcd_root / tb
    if mode == "full":
        name = f"{cfg}.vcd"
    elif mode == "window":
        name = f"{cfg}__{path_token(args.start)}__{path_token(args.end)}.vcd"
    else:
        name = f"{cfg}__trigger.vcd"
    return tb_dir / name


def maybe_expand_cfg(args: argparse.Namespace, modelsim_root: Path, manifest_path: Path) -> tuple[str, Path | None, list[str]]:
    selected_profiles: list[str] = []
    if manifest_path.exists():
        manifest = load_manifest(manifest_path)
        selected_profiles = resolve_profiles(manifest, args.tb, args.phase, args.profile)
    if not args.vcd or not selected_profiles:
        return args.cfg, Path(args.vcdcfg_dir).resolve() if args.vcdcfg_dir else None, selected_profiles
    payload = expand_cfg(modelsim_root, manifest_path, args.tb, args.cfg, args.phase, args.profile, [], "phase")
    return str(payload["cfg_name"]), Path(str(payload["vcdcfg_dir"])).resolve(), selected_profiles


def maybe_build_result_json(root: Path, manifest_path: Path, tb: str, result_json: Path, transcript: Path, vcd_path: Path | None, effective_cfg: str, selected_profiles: list[str], mode: str, phase: str | None, exit_code: int) -> None:
    if result_json.exists() or not transcript.exists():
        return
    builder = root / "scripts" / "build_result_json.py"
    if not builder.exists():
        return
    ok_flag = "1" if exit_code == 0 else "0"
    command = [
        sys.executable,
        str(builder),
        "--transcript",
        str(transcript),
        "--result",
        str(result_json),
        "--manifest",
        str(manifest_path),
        "--tb",
        tb,
        "--compile-ok",
        ok_flag,
        "--load-ok",
        ok_flag,
        "--run-ok",
        ok_flag,
        "--vcd-path",
        str(vcd_path) if vcd_path else "",
        "--selected-cfg",
        effective_cfg,
        "--selected-profiles",
        ",".join(selected_profiles),
        "--capture-mode",
        mode,
        "--phase",
        phase or "",
    ]
    subprocess.run(command, capture_output=True, text=True, shell=False)


def main() -> None:
    args = parse_args()
    validate_inputs(args)

    root = Path(args.modelsim_root).resolve()
    manifest_path = Path(args.manifest).resolve() if args.manifest else default_manifest_path(root).resolve()
    effective_cfg, effective_vcdcfg_dir, selected_profiles = maybe_expand_cfg(args, root, manifest_path)
    checks = check_project(root, args.tb, effective_cfg, effective_vcdcfg_dir, manifest_path)
    missing = [name for name, ok in checks["exists"].items() if not ok]
    if missing:
        fail("Project preflight failed", "PREFLIGHT_FAILED", checks=checks, missing=missing)

    mode = detect_mode(args)
    transcript = (root / "logs" / f"transcript_{args.tb}.log").resolve()
    result_json = (root / "logs" / f"result_{args.tb}.json").resolve()
    vcd_path = derive_vcd_path(root, args.tb, effective_cfg, mode, args)

    if args.check_only:
        payload = {
            "ok": True,
            "check_only": True,
            "tb": args.tb,
            "target": args.target,
            "phase": args.phase,
            "selected_profiles": selected_profiles,
            "mode": mode,
            "checks": checks,
            "transcript": str(transcript),
            "result_json": str(result_json),
            "vcd_path": str(vcd_path) if vcd_path else None,
            "effective_cfg": effective_cfg,
            "effective_vcdcfg_dir": str(effective_vcdcfg_dir) if effective_vcdcfg_dir else None,
        }
        print(json.dumps(payload, indent=2))
        return

    command = ["make", "-C", str(root), f"TB={args.tb}"]
    if args.vcd:
        command.extend(["VCD=1", f"VCD_CFG={effective_cfg}"])
    if args.out:
        command.append(f"VCD_OUT={args.out}")
    if args.start:
        command.append(f"VCD_START={args.start}")
    if args.end:
        command.append(f"VCD_END={args.end}")
    if args.trigger:
        command.append(f"VCD_TRIGGER={args.trigger}")
    if args.pre:
        command.append(f"VCD_PRE={args.pre}")
    if args.post:
        command.append(f"VCD_POST={args.post}")
    if effective_vcdcfg_dir:
        command.append(f"VCDCFG_DIR={effective_vcdcfg_dir}")
    if args.vcd_root:
        command.append(f"VCD_ROOT={args.vcd_root}")
    if args.phase:
        command.append(f"PHASE={args.phase}")
    if selected_profiles:
        command.append(f"PROFILES={','.join(selected_profiles)}")
    command.append(f"MANIFEST_PATH={manifest_path}")
    command.append(f"RESULT_JSON={result_json}")
    command.extend(args.extra_var)
    command.append(args.target)

    proc = subprocess.run(command, capture_output=True, text=True, shell=False)
    maybe_build_result_json(root, manifest_path, args.tb, result_json, transcript, vcd_path, effective_cfg, selected_profiles, mode, args.phase, proc.returncode)
    result = None
    if result_json.exists():
        try:
            result = json.loads(result_json.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            result = None

    payload = {
        "ok": proc.returncode == 0,
        "tb": args.tb,
        "target": args.target,
        "phase": args.phase,
        "selected_profiles": selected_profiles,
        "mode": mode,
        "effective_cfg": effective_cfg,
        "command": command,
        "exit_code": proc.returncode,
        "transcript": {
            "path": str(transcript),
            "exists": transcript.exists(),
        },
        "result_json": {
            "path": str(result_json),
            "exists": result_json.exists(),
            "data": result,
        },
        "vcd": {
            "enabled": args.vcd,
            "cfg": effective_cfg if args.vcd else None,
            "path": str(vcd_path) if vcd_path else None,
            "exists": vcd_path.exists() if vcd_path else False,
        },
        "stdout_tail": proc.stdout.splitlines()[-20:],
        "stderr_tail": proc.stderr.splitlines()[-20:],
    }
    print(json.dumps(payload, indent=2))
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
