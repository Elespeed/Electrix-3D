---
name: verilator-batch-debug
description: Use when an AI agent needs to run and diagnose the project-specific Verilator batch flow under fpga/verilator for any testbench with a matching filelist, including sketch_soc_os_tb, sketch_scene_soc_tb, gru_gdu_blit_contention_tb, rtthread_nano_os_tb, and rtthread_nano_os_320x240_tb. Inspect result JSON before logs, summarize transcripts without loading them in full, query bounded VCD facts, and cross-check ModelSim only when 4-state, X/Z, Vivado/Xilinx IP, or MIG DDR3 behavior matters. Cross-reference verilator调试.md for the 3D Scene SoC AXI-read and regression checklist.
---

# Verilator Batch Debug

Use this fast 2-state flow for lint and functional regressions. It shares RTL
with ModelSim but is not the reference for X/Z, tristate DDR, or Xilinx IP.

## Rules

- Require `--tb <TB>`; the TB must have `filelist/tb_<TB>.f`.
- Start with `--check-only`, then lint after a first migration or broad RTL edit.
- For `run-batch`, read `logs/result_<TB>.json` first, then use the transcript
  summarizer. `lint` and `compile` have no current result JSON: use their
  command return code and `VERILATOR_LINT_RC`/`VERILATOR_COMPILE_RC` instead.
  Never load a full transcript or raw VCD into context.
- A TB `$fatal`/assertion produces a `%Fatal: ...Assertion failed... <message>`
  line followed by a generic `%Error ... Verilog $stop` echo. The summarizer and
  result JSON surface the `%Fatal` text as `fatal_messages` / `first_error`;
  read that before the `%Error` echo, which alone says nothing.
- Treat `required_missing` and `missing_tools` from `--check-only` as blockers;
  `optional_missing` (such as README) is informational.
- `run-batch` checks the trace configuration and relevant HDL/TB/filelist/C-image
  timestamps. It automatically recompiles stale binaries; use `compile` only
  when you explicitly want a build without running.
- Default to no VCD. When needed, use `--vcd --cfg lite --start <time> --end <time>`.
  `debug` is escalation-only; `full` requires an explicit request. For a
  depth-3 `debug` capture, use a microsecond-scale window (at most 1ms). The
  runner rejects a wider debug window unless `--allow-large-vcd-window` is
  explicitly supplied, because a SoC trace can otherwise consume many GB even
  though cropping is working.
- Large PPM frame dumps are independent of VCD. Preserve the TB's requested
  frame-dump policy and expect it to dominate wall-clock time.
- When a TB defaults to unlimited PPM dumps, keep that default for normal runs.
  A one-off Verilator `-G` parameter override may cap dumps for a fast regression.

## Workflow

1. Preflight:

   ```powershell
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_tb --check-only
   ```

2. Fresh lint and binary for changed sources:

   ```powershell
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_tb --target lint
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_tb --target compile
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_tb
   ```

   For the RT-Thread TB only, this keeps the source default at unlimited dumps
   while writing one frame for a short regression:

   ```powershell
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_tb --target compile --verilator-extra=-GFRAME_DUMP_LIMIT=1
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_tb --verilator-extra=-GFRAME_DUMP_LIMIT=1 --keep-frame-output
   ```

   For the fixed small-screen OS integration test, build the matching C image
   first; its timing is explicit in the TB, so only C uses `sim320x240`.

   ```powershell
   wsl bash -lc "cd /mnt/d/FPGA/ciciec2026_loongson_preliminary/sdk/software/examples/RTThread_Nano && make CONFIG_PROFILE=sim320x240"
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_320x240_tb --target lint
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_320x240_tb --target compile --verilator-extra=-GFRAME_DUMP_LIMIT=1
   python skill/verilator-batch-debug/scripts/verilator_run.py --tb rtthread_nano_os_320x240_tb --verilator-extra=-GFRAME_DUMP_LIMIT=1
   ```

3. Inspect result, then summarize only if it is incomplete:

   ```powershell
   python skill/verilator-batch-debug/scripts/transcript_summarize.py --log fpga/verilator/logs/transcript_rtthread_nano_os_tb.log
   ```

   The summary includes PASS/FAIL, compile/run return codes, generic OS
   `GDU_DIAG` checkpoints, and DVI frame/file-dump counts.

4. If the result indicates a runtime issue and a waveform is necessary, state
   the hypothesis and rerun with a narrow capture window. First use heartbeat
   or transcript timing to identify the target interval; then use a `lite`
   window such as `85000us` to `85100us`. Escalate to `debug` only after that,
   with a window no wider than 1ms. Query it only through
   `vcd_query.py`: `summary`, `signal.find`, then bounded `value.at` or
   `value.window`.

5. Use ModelSim only for four-state-sensitive questions: X/Z, inout/tristate
   SRAM or DDR, Xilinx IP/MIG, CDC/timing, or a Verilator result that conflicts
   with the RTL protocol. Keep deterministic RTL state-machine and ordinary
   AXI handshake faults in Verilator.

   The local query wrapper uses `--action`, not subcommands:

   ```powershell
   python skill/verilator-batch-debug/scripts/vcd_query.py --vcd fpga/verilator/vcd/<TB>/<cfg>.vcd --action summary
   python skill/verilator-batch-debug/scripts/vcd_query.py --vcd fpga/verilator/vcd/<TB>/<cfg>.vcd --action signal.find --pattern "uart|axi|apb"
   python skill/verilator-batch-debug/scripts/vcd_query.py --vcd fpga/verilator/vcd/<TB>/<cfg>.vcd --action value.window --signal "<hier.signal>" --start 190ns --end 260ns
   ```

   For a button/UI stall, inspect: `btn` -> `confreg_int_state/confreg_int` ->
   `ext_irq` -> GDU `swap_pending` -> `vblank_evt_sys` -> `swap_done_evt` ->
   `fb_base_active`. The small-screen TB emits `[INPUT_DIAG]`; the C image emits
   `[DBG]` markers for IRQ, input queue, scene transition, and swap completion.

## Frame-based pixel checks lag the live display

The framebuffer is double-buffered and the page swap is vblank-synchronized:
`sketch_frame_ctrl` retires a PRESENT only at a GDU frame boundary, and the DVI
monitor's `captured_frame_id` is one boundary behind the live output. After a UI
transition (especially one that ABORTs the AUTO_PRESENT background Scene, which
must first drain its in-flight swap), the new page can take 2-3 boundaries to
show up. So do not assert pixels after a fixed `captured_frame_id > N` guess;
poll the completed-frame copy until the expected pixel matches (bounded), as
`sketch_soc_os_tb` does with `wait_expect_pixel()`. Also remember the DVI output
is 2x the framebuffer (`SRC_W/H=400x300` -> `OUT=800x600`): an expected pixel
written in framebuffer coordinates must be doubled to screen coordinates.

## Legacy AXI/APB peripherals

For an older AXI-to-APB bridge, do not infer a UART-register fault solely from
an unchanged peripheral register. First prove the transaction in this order:

1. Capture a bounded `debug` VCD around the first transaction.
2. Query the master `AWVALID/AWREADY`, `WVALID/WREADY`, `BVALID/BREADY`, then
   the bridge `axi_s_sel_wr`, `apb_s_wstrb`, `reg_psel`, and `reg_enable`.
3. If `WREADY` handshakes but `apb_s_wstrb` or `reg_psel` never asserts, report
   the bridge as the first failing boundary; do not broaden the VCD or change
   UART registers speculatively.
4. For byte accesses, check address-lane alignment before changing peripherals:
   `WDATA` must be shifted by `8 * AWADDR[1:0]`, `WSTRB` must be
   `4'b0001 << AWADDR[1:0]`, and readback must extract the matching `RDATA`
   byte lane.
5. Use ModelSim once to determine whether the fault is a simulator race or is
   reproducible. If both simulators stop at the same bridge boundary, create a
   minimal bridge-only transaction TB before changing production sequencing.

For this workspace, invoke the local shims as
`python skill/verilator-batch-debug/scripts/<tool>.py ...`; they
delegate to the canonical scripts in `fpga/verilator/scripts`.

## Scene SoC AXI reads

For a Scene model-fetch stall, prove each boundary in order rather than
capturing the whole SoC: `dma_m_ar*` -> `ram_ar*` -> SRAM chip-select/read
signals -> `ram_r*` -> `dma_m_r*`. For an ExtRAM model at `0x1c400000`, require
`soc_sram_addr[22]=1`, active ExtRAM CE/OE, and `ram_arid == ram_rid`. A request
state must stay active until the AR handshake; do not advance solely because a
reader is currently not busy.

## Required report

State simulator and TB, compile/load/run status, PASS/FAIL, last checkpoint,
first meaningful error, known-noise status, VCD/capture state, PPM-dump activity,
and the next minimal action. Switch to ModelSim only when Verilator semantics
are insufficient.

Read [references/verilator-project.md](references/verilator-project.md) for
WSL bridging, VCD settings, and the compatibility layer.
