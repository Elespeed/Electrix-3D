#ifndef SOC_CONFIG_COMMON_H
#define SOC_CONFIG_COMMON_H

/* Framebuffer addresses are consumed only by the GRU/GDU AXI masters.  On the
 * LV5 board they target the 1 MiB local framebuffer BRAM, not ExtRAM. */
#define SOC_FB_BASE_A        0xa0400000u
#define SOC_FB_REGION_SIZE   0x00100000u
#define SOC_FB_PIXEL_BYTES   2u
#define SOC_FB_PIXEL_FORMAT  1u

// Phase-0: reserved ExtRAM address plan for the upcoming 3D rendering path
// (SOC_3D_PLAN_*).  PLACEHOLDER reservations only -- no driver consumes them
// yet, and the only RTL hook frozen so far is GRU_REG_DEPTH_BASE (MMIO 0x48).
// They live here so later phases (16-bit depth/Z buffer, triangle setup,
// binning) reuse ONE shared address map instead of inventing a new layout.
//
// Bases are 1 MB-aligned and spaced 1 MB apart, clearing any supported
// framebuffer resolution (sim 80x60 .. remote 400x300, single/double-buffered).
// Resolution-dependent sizes/strides stay in soc_config_sim.h / remote.h /
// complex.h.
//   SOC_FB_BASE_A          RGB565 framebuffer(s)
//   SOC_3D_PLAN_DEPTH_BASE 16-bit depth/Z buffer (programmed into GRU_REG_DEPTH_BASE)
//   SOC_3D_PLAN_TILE_BASE  per-tile / binning scratch for triangle setup
#define SOC_3D_PLAN_DEPTH_BASE   0xa0100000u
#define SOC_3D_PLAN_TILE_BASE    0xa0200000u
#define SOC_3D_PLAN_REGION_SIZE  0x00100000u   /* 1 MB per reserved block */

#endif
