# Robotss articulation preview

This standalone preview rotates `robotss` arm and leg groups around the OBJ-space pivots in `robotss_pivot.json`. It reads generated assets but does not modify SK3D/MIF outputs or the shared `assets/3d/previews/frame` directory.

Run from the repository root:

```powershell
python tools/3d_gen/robotss_articulation/robotss_walk.py --verify-neutral
```

The command writes the existing OBJ/V3 preview under `assets/3d/previews/robotss/articulation/out/` and a matching decoded V4 preview under `assets/3d/previews/robotss/articulation/out_v4/`. Generate the assets first:

```powershell
make -f tools/3d_gen/Makefile ASSET=robotss
```

Each output directory contains:

- `no_zbuffer/frames/` and `zbuffer/frames/`: 16 PNG walk frames.
- `no_zbuffer/robotss_walk.gif` and `zbuffer/robotss_walk.gif`: looping previews.
- `comparison_contact_sheet.png`: no-Z and Z-buffer frames side by side.
- `summary.json`: OBJ pivots, vertex-to-part mapping, joint angles, and per-frame visibility/occlusion statistics.

The four limbs use a ±25° sine-wave roll: left arm/right leg are in phase, and right arm/left leg are opposite. The body is static. Roll rotates around OBJ +Z, so the gait is visible in the front-view silhouette; pitch rotates around +X and is mainly useful for a side-view depth swing.

To render the same walk from a fixed 30° side view without replacing the
front-view output, use a separate output directory:

```powershell
python tools/3d_gen/robotss_articulation/robotss_walk.py --yaw-degrees 30 --output assets/3d/previews/robotss/articulation/out_side30
```

Use `--v4-output <folder>` to select the V4 folder, or `--skip-v3` to render only V4.
