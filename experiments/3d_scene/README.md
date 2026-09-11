# Scene Controller experiment system

Runs support `CPU_ONLY`, `CPU_MATMUL`, and `SCENE_CONTROLLER`. Select the
backend with `MODE=...`; generate deterministic S0--S4
SK3D-v4 assets with `make -C experiments/3d_scene assets`. Formal evidence is
written to ignored `runs/<run_id>/`; its manifest retains asset and config
hashes.

Each benchmark output is UTF-8 JSON Lines. Blank lines are ignored. Records
must occur in this order:

1. `run_begin`: `schema`, `run_id`, `mode`, and positive model dimensions `V`,
   `T`, `M`.
2. Zero or more `frame` records. `frame` starts at zero and is contiguous.
   Every frame carries `cycles.active/polling/wall`, the four phase cycle
   counters (`transform`, `triangle_cull`, `painter_sort`, `command_submit`),
   `frame_latency_cycles`, a uint32 `crc` (number or hex string), and `status`.
3. `run_end`: `schema`, `run_id`, `frames` and `status`. `frames` must equal the
   number of frame records.

`mode`, `V`, `T`, and `M` are invariant for a run. `active` and `polling` may
not exceed `wall`. Status values are `pass`, `fail`, or `error`.

Validate with:

```text
python tools/validate_3d_jsonl.py experiments/3d_scene/fixtures/valid.jsonl
```

`validate_run.py` checks record structure, asset/config identity, and status.
`summarize.py` aggregates every structurally valid passing frame. Command and
frame CRCs are retained in the JSONL and transcript as diagnostic evidence;
they are not a prerequisite for performance statistics.

Examples:

```text
make -C experiments/3d_scene MODE=CPU_ONLY MODEL=S0 smoke
make -C experiments/3d_scene MODE=CPU_MATMUL MODEL=S1 run
make -C experiments/3d_scene MODE=SCENE_CONTROLLER run-matrix
```
