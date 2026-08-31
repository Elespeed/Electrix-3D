---
name: modelsim-batch-debug
description: >
  Use when an AI agent needs to run the project-specific ModelSim batch flow,
  inspect structured batch results, summarize transcript logs with known-noise
  filtering and checkpoint extraction, inspect bounded VCD waveform facts,
  collect state snapshots at a specific time, decide whether the current VCD
  capture is sufficient, optionally expand capture with manifest-driven
  profiles and a temporary VCD cfg, and rerun without loading raw VCD or large
  logs into context. This skill is specialized for
  D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim.
---

# ModelSim Batch Debug

This skill is for the project-specific ModelSim batch debug flow under
`D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim`.

Use this skill when the user wants AI to:

- run ModelSim in batch mode
- inspect structured batch results before reading logs
- inspect transcript logs with checkpoint extraction and known-noise filtering
- inspect VCD waveform facts without opening GUI waveforms
- collect a compact state snapshot at a specific time
- decide whether the current VCD capture is sufficient
- expand VCD capture with manifest-driven profiles and rerun

Do not read raw `.vcd` files or full transcript logs into context. Always use
the helper scripts in `scripts/` and return compact JSON summaries.

## Defaults

- Prefer `make -C fpga/modelsim run-batch`.
- Require a concrete `TB`.
- Default to `VCD=1 VCD_CFG=lite`.
- Prefer fixed-window capture with `VCD_START/VCD_END`.
- Use trigger-centered capture only when a trigger signal is known.
- Treat `debug` as escalation-only.
- Treat `full` as exceptional and only when the user explicitly asks.
- Never edit checked-in `fpga/modelsim/vcdcfg/*.lst` during diagnosis runs.
- Expand waveform capture by generating a temporary cfg with
  `scripts/vcd_cfg_expand.py`.
- Prefer phase-driven workflows such as `--phase backpressure` when the user is
  debugging a known GRU/GDU stage.

## Evidence Order

1. `logs/result_<TB>.json`
2. transcript summary
3. VCD summary and bounded queries
4. snapshot
5. temporary cfg expansion and rerun

## Workflow

1. Preflight:
   - Use `scripts/modelsim_run.py --check-only ...` to verify the project,
     `Makefile`, batch script, selected TB file, base VCD preset, and
     manifest exist.
   - Refuse broad waveform inspection if no `TB` is provided.

2. First run:
   - Run batch mode with `scripts/modelsim_run.py`.
   - Prefer:
     - `--cfg lite`
     - `--phase backpressure` or another known phase
     - `--start ... --end ...`, or
     - `--trigger ... --pre ... --post ...`

3. Result-first diagnosis:
   - Read `result_<TB>.json` first.
   - Use it for:
     - compile/load/run status
     - pass/fail
     - last checkpoint
     - phase hint
     - known-noise counts
     - selected cfg/profiles
     - VCD path

4. Log-first diagnosis:
   - If result JSON is missing or insufficient, summarize the transcript with
     `scripts/transcript_summarize.py`.
   - Use the summary to classify:
     - compile errors
     - load errors
     - runtime errors
     - pass/fail markers
     - checkpoints
     - known noise
     - VCD output hints

5. VCD diagnosis:
   - Use `scripts/vcd_query.py` only.
   - Preferred action order:
     1. `summary`
     2. `signal.find` or `scope.list`
     3. `value.at`
     4. `value.window`
     5. `edge.find` or `event.count`
   - Every query must include signal filters and/or bounded time ranges.

6. Snapshot:
   - Use `scripts/modelsim_snapshot.py` when VCD evidence is missing or when a
     phase-specific state cut at one time is more efficient than a rerun.
   - Prefer phase defaults before adding ad-hoc signals.

7. Escalation:
   - If `lite` is insufficient, first try:
     - a narrower time window
     - a trigger-centered capture
     - a manifest-driven profile combination
     - a temporary expanded cfg
   - Only upgrade to `debug` if those fail.

8. Rerun loop:
   - For every rerun, state:
     - why the previous evidence was insufficient
     - what changed in VCD capture
     - what hypothesis the rerun is testing

## Script Entry Points

Run batch simulation:

```powershell
python skill/modelsim-batch-debug/scripts/modelsim_run.py --tb gru_gdu_local_tb --phase backpressure --vcd --cfg lite --start 70us --end 85us
```

Summarize transcript:

```powershell
python skill/modelsim-batch-debug/scripts/transcript_summarize.py --log D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim\logs\transcript_gru_gdu_local_tb.log
```

Read a snapshot:

```powershell
python skill/modelsim-batch-debug/scripts/modelsim_snapshot.py --tb gru_gdu_local_tb --phase backpressure --time 80us
```

Query a VCD:

```powershell
python skill/modelsim-batch-debug/scripts/vcd_query.py --vcd D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim\vcd\gru_gdu_local_tb\lite__70us__85us.vcd --action summary
python skill/modelsim-batch-debug/scripts/vcd_query.py --vcd D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim\vcd\gru_gdu_local_tb\lite__70us__85us.vcd --action signal.find --phase backpressure --pattern "*awready*"
python skill/modelsim-batch-debug/scripts/vcd_query.py --vcd D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim\vcd\gru_gdu_local_tb\lite__70us__85us.vcd --action value.window --signal sim:/gru_gdu_local_tb/u_graph_system/u_gru_top/m_axi_awready --start 79us --end 81us --max-transitions 32
```

Create a temporary expanded cfg:

```powershell
python skill/modelsim-batch-debug/scripts/vcd_cfg_expand.py --tb gru_gdu_local_tb --base lite --phase backpressure --profile gru_writer --add sim:/gru_gdu_local_tb/u_graph_system/u_gru_top/u_gru_axi_writer/state
```

## Token Control Rules

- Never read raw `.vcd` into context.
- Never paste full transcript logs into context.
- Prefer `result_<TB>.json` and transcript counts before raw line samples.
- Prefer `summary` and counts before raw transition samples.
- Cap results with script limits such as `--max-signals`, `--max-transitions`,
  and `--limit`.
- Avoid instance-wide recursive dumps unless the user explicitly requests them.

Read [references/modelsim-project.md](references/modelsim-project.md) for the
project-specific paths, naming conventions, manifest conventions, and
escalation policy.
