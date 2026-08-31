# Verilator Project Reference

Project root:

- `fpga/verilator` (WSL-reachable at `/mnt/<drive>/.../Blade-of-Chip/fpga/verilator`)

Default batch command (runs from the repo root on Windows, no `wsl` prefix — the
Makefile bridges into WSL transparently):

```powershell
make -C fpga/verilator TB=gru_gdu_blit_contention_tb run-batch
```

Stable project facts:

- Batch driver (WSL side): `scripts/verilator_build.sh` (lint / compile / run)
- Transcript path pattern: `logs/transcript_<TB>.log`
- Result path pattern: `logs/result_<TB>.json`
- Perf result path pattern: `logs/perf_result_<TB>.json`
- TB filelist pattern: `filelist/tb_<TB>.f`
- VCD path pattern: `vcd/<TB>/<VCD_CFG>.vcd`
- Exit-code markers in transcript: `VERILATOR_LINT_RC`, `VERILATOR_COMPILE_RC`, `VERILATOR_RUN_RC`, `VERILATOR_VCD_PATH`

Supported Makefile knobs:

- `TB`
- `VCD`, `VCD_CFG`, `VCD_OUT`, `VCD_OUT_REL`, `VCD_FILE`, `VCD_START`, `VCD_END`, `VCD_ROOT`
- `PHASE`, `PROFILES`
- `PERF_MODE`, `PERF_REPEAT_COUNT`, `PERF_WARMUP_FRAMES`, `PERF_FRAME_COUNT`, `PERF_RUN_ID`, `PERF_RESULT_JSON`
- `VERILATOR_EXTRA`, `JOBS`, `VERILATOR`
- `CLEAN_FRAME_OUTPUT`, `FRAME_OUTPUT_DIR`, `RESULT_JSON`
- `LOG_DIR`, `BUILD_DIR`

## Architecture: transparent WSL bridge

Verilator + g++ live only in WSL. The Makefile runs every compile/run target as
`wsl --cd <win-fpga/verilator> bash scripts/verilator_build.sh ...`; `MSYS_NO_PATHCONV=1`
stops Git Bash mangling path args and `2>/dev/null` swallows wsl.exe's UTF-16
proxy banner. Transcript + result JSON land on the shared DrvFs under
`fpga/verilator/{build,logs,vcd}`, where the Windows Python helpers read them.
`verilator_build.sh` reuses an existing binary in `run` mode **unless** the trace
config changed (run `make compile` to force a rebuild after RTL/TB edits).

Filelist conventions differ from ModelSim because Verilator resolves from
`fpga/verilator` (2 levels deep): paths use `../../` (not `../../../`) and nested
`-f filelist/base.f` (relative to CWD, not the including file).

## cfg → trace-depth mapping (task §11.2)

Verilator tracing is compile-time. `VCD_CFG` selects `--trace-depth`:

| cfg    | trace-depth | scope                                  |
|--------|-------------|----------------------------------------|
| lite   | 1           | top-level TB signals (gru_s_*/gdu_s_* AXI handshakes) |
| debug  | 3           | top + a couple of sub-scopes           |
| full   | (none)      | whole design (large/slow)              |

`lite` is meaningful for this contention TB: the top-level `gru_s_*`/`gdu_s_*`
AXI handshake signals (arvalid/arready, awvalid/awready, …) are exactly what a
contention/backpressure diagnosis queries. The full run is ~400 MB at depth-1, so
always pass `VCD_START`/`VCD_END`: the custom main crops the dump window in ps
(passed through as `VLT_TRACE_START_PS`/`VLT_TRACE_END_PS`), yielding a small,
fast-to-query VCD (`capture_mode=window`; without a window, `full_run`).

## VERILATOR_BUILD compatibility layer (task §7)

`+define+VERILATOR_BUILD` is passed to every Verilator compile. Minimal,
commented shims (ModelSim/synthesis keep the original `else` branch):

- **`gru_gdu_blit_contention_tb.sv`** — `TB_HAS_FB_PEEK` gathers
  `MODELSIM_BUILD`/`VERILATOR_BUILD` so the framebuffer peek/poke and
  `SIM_USE_FAST_RAM` datapath are enabled for both simulators. Functional checks
  (`$fatal`, framebuffer compare, watchdog, AXI-error/underflow) are never gated.
- **`cfg_driver.sv`** — under Verilator `--timing`, a guarded `default clocking
  cb_tb` + `\`SYNC`/`\`RD` de-races the AXI-Lite handshake in the preponed region.
- **`gru_axi_writer.sv`** — non-blocking array write in a for-loop → blocking.
- **`lcd_monitor.sv`** — one blocking `frame_height` write → non-blocking.
- **`gru_ref_model.sv` / `cfg_driver.sv`** — `disable <task>` → SV `return;`.
- **`behav/ddr3_model_wrapper_stub.sv`** — port-faithful no-op stub replaces the
  tristate Micron model in the Verilator filelist only (inert under
  `SIM_USE_FAST_RAM`). The contention path (arbiter + `axi_wrap_ram_sp`) is
  untouched — this is not a zero-latency always-ready DDR.

## Known differences vs ModelSim

- 2-state (no X/Z); reset-before-init signals resolve to 0, not X.
- `--timing` event-driven sim is slower per cycle but supports `#delay`/
  `@(posedge)`/watchdog.
- VCD hierarchy names differ (`tb.u_x…`, not `sim:/tb/u_x…`).
- Verilator is NOT a golden reference for MIG/Xilinx primitives — 4-state /
  tristate / timing-check problems go to ModelSim.

## Default escalation policy

1. result JSON + transcript summary (no rerun)
2. `lite` (depth-1) VCD + bounded queries
3. `debug` (depth-3) VCD
4. `full` only when explicitly requested
5. ModelSim cross-check when Verilator semantics are suspect

## Evidence order

1. lint summary (if lint was run)
2. `result_<TB>.json`
3. transcript summary
4. VCD metadata summary
5. targeted signal/time queries
6. ModelSim cross-check
7. rerun
