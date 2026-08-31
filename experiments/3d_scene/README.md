# 3D benchmark JSONL v1

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
