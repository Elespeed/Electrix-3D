---
name: frame-output-check
description: Summarize simulation framebuffer exports into compact visual evidence. Use when Codex needs to inspect `.ppm` or `.png` images from hardware or display simulations, especially under `sim/frame_output`, to verify labels, compare scenes, measure image differences, or avoid mistaking a Home frame for an application frame.
---

# Frame Output Check

Use this skill to turn generated framebuffer images into concise, reproducible evidence instead of relying on a visual guess.

## Workflow

1. Start with the exported frames under `sim/frame_output/`.
2. Run `scripts/frame_output_check.py` on one or more `.ppm` or `.png` files.
3. Read the JSON summary first.
4. Use the generated `.png` files for direct visual confirmation when the summary suggests a mismatch.
5. When comparing two scenes, use `--compare` so the script reports pixel-difference ratio and per-probe changes.

## Commands

Summarize one or more frames:

```powershell
python skill/frame-output-check/scripts/frame_output_check.py sim/frame_output/home_left.ppm sim/frame_output/state.ppm
```

Summarize and compare two frames:

```powershell
python skill/frame-output-check/scripts/frame_output_check.py sim/frame_output/home_left.ppm sim/frame_output/terminal.ppm --compare
```

Write JSON to a file:

```powershell
python skill/frame-output-check/scripts/frame_output_check.py sim/frame_output/*.ppm --compare --json-out sim/frame_output/frame_summary.json
```

## What The Script Reports

- Image path, format, width, and height
- Auto-generated `.png` path for any `.ppm` input
- Global counts such as non-black ratio and top colors
- Project-specific region summaries for the MCU display layout:
  - title bar
  - left tile
  - right tile
  - left focus border probe
  - right focus border probe
- Stable pixel probes that are useful for Home vs app-page checks
- Optional pairwise diff metrics when `--compare` is set

## Interpretation Rules

- Treat the JSON summary as the primary evidence.
- Use direct image viewing only after reading the summary.
- Do not claim a page is `terminal` or `state` purely because the testbench named the file that way.
- If a file named `terminal.ppm` has nearly the same probes and diff profile as `home_left.ppm`, report that the captured content is still Home-like.
- Keep display-state conclusions separate from control-state conclusions such as `scene`, `requested_page`, or `swap_count`.

## Scope

This skill is optimized for the current workspace's MCU display frames. It still works on generic `.ppm` and `.png` files, but the built-in named regions are tailored to the 800x480 Home layout used by the display regressions.

