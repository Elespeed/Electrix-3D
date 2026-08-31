`include "config_common.h"

`ifdef FB_WIDTH
`undef FB_WIDTH
`undef FB_HEIGHT
`undef FB_STRIDE_BYTES
`undef GDU_DEFAULT_WIDTH
`undef GDU_DEFAULT_HEIGHT
`undef GDU_DEFAULT_STRIDE
`undef GDU_STARTUP_THRESHOLD
`undef GDU_STARTUP_PREFILL_LINES
`undef GRU_WCB_LINE_BEATS
`undef GDU_TIMING_H_ACTIVE
`undef GDU_TIMING_H_FRONT
`undef GDU_TIMING_H_SYNC
`undef GDU_TIMING_H_BACK
`undef GDU_TIMING_H_TOTAL
`undef GDU_TIMING_V_ACTIVE
`undef GDU_TIMING_V_FRONT
`undef GDU_TIMING_V_SYNC
`undef GDU_TIMING_V_BACK
`undef GDU_TIMING_V_TOTAL
`undef SOC_LCD_OUTPUT_MODE
`endif

`define FB_WIDTH         400
`define FB_HEIGHT        300
`define FB_STRIDE_BYTES  800

`define GDU_DEFAULT_WIDTH   16'd400
`define GDU_DEFAULT_HEIGHT  16'd300
`define GDU_DEFAULT_STRIDE  32'd800
`define GDU_STARTUP_THRESHOLD (((`FB_WIDTH * 3) < 1024) ? (`FB_WIDTH * 3) : 1024)
`define GDU_STARTUP_PREFILL_LINES 3
`define GRU_WCB_LINE_BEATS 64

// Set to 1 only when SketchBook needs per-vertex RGB332 interpolation.
// Keeping it 0 makes the Lite rasterizer synthesize as flat-only, removing
// its Gouraud colour-gradient and reciprocal datapath.
`define SKETCH_ENABLE_GOURAUD 0

// Remote system: store packed RGB332 at 400x300, then let the GDU scale 2x to a
// standard 800x600 active area for DVI capture/output.
`define GDU_TIMING_H_ACTIVE 800
`define GDU_TIMING_H_FRONT  40
`define GDU_TIMING_H_SYNC   128
`define GDU_TIMING_H_BACK   88
`define GDU_TIMING_H_TOTAL  1056
`define GDU_TIMING_V_ACTIVE 600
`define GDU_TIMING_V_FRONT  1
`define GDU_TIMING_V_SYNC   4
`define GDU_TIMING_V_BACK   23
`define GDU_TIMING_V_TOTAL  628

`define SOC_LCD_OUTPUT_MODE `LCD_OUTPUT_MODE_PARALLEL
