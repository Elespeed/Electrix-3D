#!/usr/bin/env python
#Runner for the Verilator batch flow (task book §8).
#
# Verilator counterpart of skill/modelsim-batch-debug/scripts/modelsim_run.py.
# Thin orchestration on top of `make -C fpga/verilator`: parse args, build the
# make command (TB / VCD / PERF overrides), run it, then read the result JSON the
# Makefile always emits (even on failure) and print a compact summary. The skill
# scripts delegate here (single source of truth).
#
#   python fpga/verilator/scripts/verilator_run.py --tb gru_gdu_blit_contention_tb --check-only
#   python fpga/verilator/scripts/verilator_run.py --tb gru_gdu_blit_contention_tb
#   python fpga/verilator/scripts/verilator_run.py --tb gru_gdu_blit_contention_tb --vcd --cfg lite
#   python fpga/verilator/scripts/verilator_run.py --tb gru_gdu_blit_contention_tb --perf-mode --repeat-count 1 --frame-count 2
from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_VERILATOR_ROOT = SCRIPT_DIR.parent                       # fpga/verilator
DEFAULT_REPO_ROOT = DEFAULT_VERILATOR_ROOT.parents[1]            # repo root
TIME_TO_PS = {
    "fs": 1 // 1000,
    "ps": 1,
    "ns": 1_000,
    "us": 1_000_000,
    "ms": 1_000_000_000,
    "s": 1_000_000_000_000,
}
DEBUG_VCD_MAX_WINDOW_PS = 1_000_000_000  # 1 ms; depth-3 SoC traces grow quickly.


def fail(message: str, code: str = "ERROR", **extra: object) -> None:
    payload = {"ok": False, "error": {"code": code, "message": message}}
    if extra:
        payload.update(extra)
    print(json.dumps(payload, indent=2))
    sys.exit(1)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run the Verilator batch flow and report a compact JSON.")
    p.add_argument("--verilator-root", default=str(DEFAULT_VERILATOR_ROOT))
    p.add_argument("--repo-root", default=str(DEFAULT_REPO_ROOT))
    p.add_argument("--tb", required=True, help="Testbench name with filelist/tb_<TB>.f")
    p.add_argument("--target", default="run-batch", choices=["run-batch", "compile", "lint"])
    p.add_argument("--vcd", action="store_true")
    p.add_argument("--cfg", default="lite")
    p.add_argument("--start", help="VCD_START window lower bound (e.g. 70us); custom main crops the dump")
    p.add_argument("--end", help="VCD_END window upper bound (e.g. 85us); custom main crops the dump")
    p.add_argument("--allow-large-vcd-window", action="store_true",
                   help="Allow a debug VCD window wider than 1ms (may create a very large file)")
    p.add_argument("--phase", help="recorded into result JSON phase_hint")
    p.add_argument("--profile", action="append", default=[], help="recorded; Stage-1 has no manifest filtering")
    p.add_argument("--perf-mode", action="store_true")
    p.add_argument("--repeat-count", type=int, default=3)
    p.add_argument("--warmup-frames", type=int, default=0)
    p.add_argument("--frame-count", type=int, default=8)
    p.add_argument("--run-id", type=int, default=0)
    p.add_argument("--verilator-extra", action="append", default=[], help="Extra Verilator argument; repeat as needed")
    p.add_argument("--keep-frame-output", action="store_true", help="Do not clear sim/frame_output before run-batch")
    p.add_argument("--quiet", action="store_true", help="Suppress live compiler/simulator output; retain transcript only")
    p.add_argument("--check-only", action="store_true")
    return p.parse_args()


def time_to_ps(value: str) -> int:
    """Match verilator_build.sh's accepted integer time syntax."""
    match = re.fullmatch(r"(\d+)(fs|ps|ns|us|ms|s)?", value)
    if not match:
        raise ValueError(f"invalid time '{value}'; use an integer with fs/ps/ns/us/ms/s")
    magnitude, unit = match.groups()
    return int(magnitude) * TIME_TO_PS[unit or "ps"]


def validate_vcd_window(args: argparse.Namespace) -> None:
    if not args.vcd or not args.start or not args.end:
        return
    try:
        start_ps = time_to_ps(args.start)
        end_ps = time_to_ps(args.end)
    except ValueError as exc:
        fail(str(exc), "INVALID_VCD_WINDOW")
    if end_ps <= start_ps:
        fail("VCD --end must be later than --start", "INVALID_VCD_WINDOW")
    if (args.cfg == "debug" and end_ps - start_ps > DEBUG_VCD_MAX_WINDOW_PS
            and not args.allow_large_vcd_window):
        fail("debug VCD window exceeds 1ms; narrow it or pass --allow-large-vcd-window",
             "VCD_WINDOW_TOO_LARGE", start=args.start, end=args.end)


def capture_mode(args: argparse.Namespace) -> str:
    if not args.vcd:
        return "disabled"
    # The custom main crops to [start,end] in ps (task §11.3, implemented); a
    # bounded window -> "window", otherwise the full run.
    if args.start and args.end:
        return "window"
    return "full_run"


def wsl_capture(cmd: str, timeout: int = 60) -> tuple[int | None, str]:
    """Run a command inside WSL; return (returncode, stdout). Best-effort.

    Captures bytes and decodes with errors replaced: wsl.exe prepends a UTF-16
    proxy banner that crashes the GBK default codec on zh-CN Windows."""
    try:
        proc = subprocess.run(
            ["wsl", "--", "bash", "-lc", cmd],
            capture_output=True, timeout=timeout,
        )
        out = proc.stdout.decode("utf-8", errors="replace")
        return proc.returncode, out
    except FileNotFoundError:
        return None, ""          # wsl.exe not on PATH
    except subprocess.TimeoutExpired:
        return None, "TIMEOUT"


def first_meaningful_line(text: str, needle: str = "") -> str | None:
    for raw in text.splitlines():
        line = raw.strip().replace("\x00", "")
        if not line:
            continue
        if "�" in line:
            # decode-replacement debris from wsl.exe's UTF-16 proxy banner
            continue
        printable = sum(1 for c in line if 32 <= ord(c) < 127)
        if printable < max(4, len(line) // 2):
            continue
        if needle and needle not in line:
            continue
        return line
    return None


def tool_versions() -> dict[str, object]:
    rc_v, out_v = wsl_capture("verilator --version 2>/dev/null")
    verilator_version = first_meaningful_line(out_v, "Verilator") if rc_v == 0 else None
    rc_g, out_g = wsl_capture("g++ --version 2>/dev/null | head -1")
    gpp_version = first_meaningful_line(out_g) if rc_g == 0 else None
    rc_w, out_w = wsl_capture("echo ok 2>/dev/null")
    return {
        "wsl_available": rc_w == 0,
        "verilator_version": verilator_version,
        "verilator_available": verilator_version is not None,
        "gpp_version": gpp_version,
        "gpp_available": gpp_version is not None,
    }


def check_project(root: Path, repo: Path, tb: str) -> dict[str, object]:
    makefile = root / "Makefile"
    readme = root / "README.md"
    build_sh = root / "scripts" / "verilator_build.sh"
    result_builder = root / "scripts" / "build_result_json.py"
    perf_builder = root / "scripts" / "build_perf_result_json.py"
    vcd_query = root / "scripts" / "vcd_query.py"
    tb_filelist = root / "filelist" / f"tb_{tb}.f"
    # Unit/integration TBs live under sim/test, while standalone performance
    # benchmarks live under sim/benchmark.  Keep the direct sim/test path as
    # the common fast path, then search both supported roots for nested TBs.
    tb_src = repo / "sim" / "test" / f"{tb}.sv"
    if not tb_src.exists():
        tb_roots = (repo / "sim" / "test", repo / "sim" / "benchmark")
        matches = [match for tb_root in tb_roots if tb_root.exists()
                   for match in tb_root.rglob(f"{tb}.sv")]
        if matches:
            tb_src = sorted(matches)[0]
    checks = {
        "repo_root": str(repo),
        "verilator_root": str(root),
        "makefile": str(makefile),
        "readme": str(readme),
        "build_script": str(build_sh),
        "result_builder": str(result_builder),
        "perf_builder": str(perf_builder),
        "vcd_query": str(vcd_query),
        "tb_filelist": str(tb_filelist),
        "tb_src": str(tb_src),
        "build_dir": str(root / "build"),
        "log_dir": str(root / "logs"),
        "vcd_dir": str(root / "vcd"),
        "tools": tool_versions(),
        "exists": {
            "repo_root": repo.exists(),
            "verilator_root": root.exists(),
            "makefile": makefile.exists(),
            "readme": readme.exists(),
            "build_script": build_sh.exists(),
            "result_builder": result_builder.exists(),
            "perf_builder": perf_builder.exists(),
            "vcd_query": vcd_query.exists(),
            "tb_filelist": tb_filelist.exists(),
            "tb_src": tb_src.exists(),
        },
    }
    return checks


def preflight_status(checks: dict[str, object]) -> tuple[list[str], list[str], list[str]]:
    """Return (required_missing, optional_missing, missing_tools)."""
    required = ("repo_root", "verilator_root", "makefile", "build_script",
                "result_builder", "perf_builder", "vcd_query", "tb_filelist", "tb_src")
    exists = checks["exists"]
    required_missing = [name for name in required if not exists[name]]
    optional_missing = ["readme"] if not exists["readme"] else []
    tools = checks["tools"]
    missing_tools = [name for name in ("verilator_available", "gpp_available", "wsl_available")
                     if not tools.get(name)]
    return required_missing, optional_missing, missing_tools


def compact_summary(result: dict[str, object] | None, transcript: Path, vcd_file: Path | None) -> dict[str, object]:
    """Expose the run facts agents otherwise have to reconstruct manually."""
    if result is None:
        return {"result_available": False, "transcript": str(transcript)}
    samples = result.get("samples", {})
    warnings = result.get("warning_counts", {})
    # A %Fatal assertion line is the actionable diagnostic; only fall back to the
    # generic "%Error ... Verilog $stop" echo when no fatal message was captured.
    fatal_msgs = result.get("fatal_messages") or []
    first_error = fatal_msgs[0] if fatal_msgs else (samples.get("error_marker") or [None])[0]
    return {
        "result_available": True,
        "pass_fail": result.get("pass_fail"),
        "compile_rc": result.get("compile_rc"),
        "run_rc": result.get("run_rc"),
        "first_error": first_error,
        "fatal_messages": fatal_msgs,
        "pass_marker": (samples.get("pass_marker") or [None])[0],
        "warning_count": warnings.get("warning"),
        "vcd_path": str(vcd_file) if vcd_file else None,
        "transcript": str(transcript),
    }


def build_make_command(args: argparse.Namespace, root: Path, result_json: Path, vcd_file: Path) -> list[str]:
    cmd = ["make", "-C", str(root).replace("\\", "/"), "PYTHON=python", f"TB={args.tb}", f"RESULT_JSON=logs/{result_json.name}"]
    if args.verilator_extra:
        cmd.append(f"VERILATOR_EXTRA={' '.join(args.verilator_extra)}")
    if args.keep_frame_output:
        cmd.append("CLEAN_FRAME_OUTPUT=0")
    if args.quiet:
        cmd.append("LIVE_LOG=0")
    if args.target == "lint":
        cmd.append("lint")
        return cmd
    if args.target == "compile":
        cmd.append("compile")
        return cmd
    if args.vcd:
        cmd += ["VCD=1", f"VCD_CFG={args.cfg}", f"VCD_FILE={str(vcd_file).replace('\\', '/')}"]
        if args.start:
            cmd.append(f"VCD_START={args.start}")
        if args.end:
            cmd.append(f"VCD_END={args.end}")
    if args.perf_mode:
        cmd += [
            "PERF_MODE=1",
            f"PERF_REPEAT_COUNT={args.repeat_count}",
            f"PERF_WARMUP_FRAMES={args.warmup_frames}",
            f"PERF_FRAME_COUNT={args.frame_count}",
            f"PERF_RUN_ID={args.run_id}",
        ]
    if args.phase:
        cmd.append(f"PHASE={args.phase}")
    if args.profile:
        cmd.append(f"PROFILES={','.join(args.profile)}")
    cmd.append("run-batch")
    return cmd


def main() -> None:
    args = parse_args()
    validate_vcd_window(args)
    root = Path(args.verilator_root).resolve()
    repo = Path(args.repo_root).resolve()
    checks = check_project(root, repo, args.tb)

    required_missing, optional_missing, missing_tools = preflight_status(checks)

    if args.check_only:
        transcript = (root / "logs" / f"transcript_{args.tb}.log").resolve()
        result_json = (root / "logs" / f"result_{args.tb}.json").resolve()
        vcd_file = (root / "vcd" / args.tb / f"{args.cfg}.vcd").resolve()
        payload = {
            "ok": not required_missing and not missing_tools,
            "check_only": True,
            "tb": args.tb,
            "target": args.target,
            "phase": args.phase,
            "mode": capture_mode(args),
            "perf_mode": args.perf_mode,
            "verilator_extra": args.verilator_extra,
            "keep_frame_output": args.keep_frame_output,
            "checks": checks,
            "required_missing": required_missing,
            "optional_missing": optional_missing,
            "missing_files": required_missing,
            "missing_tools": missing_tools,
            "transcript": str(transcript),
            "result_json": str(result_json),
            "vcd_path": str(vcd_file) if args.vcd else None,
        }
        print(json.dumps(payload, indent=2))
        return

    if required_missing or missing_tools:
        fail("Verilator project preflight failed", "PREFLIGHT_FAILED", checks=checks,
             required_missing=required_missing, optional_missing=optional_missing, missing_tools=missing_tools)

    transcript = (root / "logs" / f"transcript_{args.tb}.log").resolve()
    result_json = (root / "logs" / f"result_{args.tb}.json").resolve()
    vcd_file = (root / "vcd" / args.tb / f"{args.cfg}.vcd").resolve()
    command = build_make_command(args, root, result_json, vcd_file)
    # Run make through PowerShell. In this environment `make -C fpga/verilator`
    # works correctly from PowerShell, while extra shell hops through Git Bash
    # introduce path and PATH mismatches around the WSL bridge and helper Python.
    fs_command = [str(c).replace("\\", "/") for c in command]
    shell_cmd = " ".join(shlex.quote(c) for c in fs_command)
    started_at = time.time()
    if args.quiet:
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-Command", shell_cmd],
            capture_output=True, shell=False, cwd=str(repo),
        )
        stdout = proc.stdout.decode("utf-8", errors="replace") if proc.stdout else ""
        stderr = proc.stderr.decode("utf-8", errors="replace") if proc.stderr else ""
    else:
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-Command", shell_cmd],
            shell=False, cwd=str(repo),
        )
        stdout = ""
        stderr = ""

    result = None
    result_is_current = False
    if args.target == "run-batch" and result_json.exists() and result_json.stat().st_mtime >= started_at - 1:
        try:
            result = json.loads(result_json.read_text(encoding="utf-8"))
            result_is_current = True
        except json.JSONDecodeError:
            result = None

    payload = {
        "ok": proc.returncode == 0,
        "tb": args.tb,
        "target": args.target,
        "phase": args.phase,
        "mode": capture_mode(args),
        "perf_mode": args.perf_mode,
        "verilator_extra": args.verilator_extra,
        "keep_frame_output": args.keep_frame_output,
        "live_log": not args.quiet,
        "effective_cfg": args.cfg if args.vcd else None,
        "command": ["powershell", "-NoProfile", "-Command", shell_cmd],
        "exit_code": proc.returncode,
        "transcript": {"path": str(transcript), "exists": transcript.exists()},
        "result_json": {"path": str(result_json), "exists": result_json.exists(), "current_run": result_is_current, "data": result},
        "summary": compact_summary(result, transcript, vcd_file if args.vcd else None),
        "vcd": {
            "enabled": args.vcd,
            "cfg": args.cfg if args.vcd else None,
            "path": str(vcd_file) if args.vcd else None,
            "exists": vcd_file.exists() if args.vcd else False,
        },
        "stdout_tail": stdout.splitlines()[-20:],
        "stderr_tail": stderr.splitlines()[-20:],
    }
    print(json.dumps(payload, indent=2))
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
