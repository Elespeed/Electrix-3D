`include "gru_defs.vh"

// gru_lite_triangle_setup
// ----------------------------------------------------------------------------
// 3D Lite triangle setup (Phase 1x0 flat + Phase 2x0 Gouraud).  Combinational
// decode of a 256-bit triangle command into the geometry the Lite rasterizer
// consumes.  This is the Lite counterpart of engine_3d/gru_triangle_setup.sv,
// stripped to flat/Gouraud colour only: no texture, no perspective, no Z.
//
// Phase 2x0 adds the three per-vertex RGB565 outputs (c0/c1/c2_rgb565) the
// Gouraud rasterizer interpolates.  Setup stays COMBINATIONAL and divider-free:
// the reciprocal-of-area that Gouraud needs is computed separately, in the
// rasterizer's multi-cycle setup, by gru_lite_recip_area (leading-one + LUT).
//
// Lite contract (docs/3dlite/phase1x0_Flat三角形开发.md): vertices arrive in
// screen space and the framebuffer is at most 800x480.  Any vertex outside the
// engine's addressable range is a REJECT -- Lite ships no full clipper
// ("任何越界顶点均为拒绝路径").  That reject is what bounds the edge-function
// range, so the rasterizer's 24-bit edge accumulators can never overflow (see
// the width proof in gru_lite_triangle_raster.sv).
//
// The addressable range is the AND of three limits:
//   * the configured framebuffer  [0, frame_w-1] x [0, frame_h-1];
//   * the Lite internal datapath  (x 10-bit / y 9-bit magnitude);
//   * the downstream span format  (GRU_SPAN_X / GRU_SPAN_Y are 9-bit -> 0..511).
// The span format is the tightest, so the engine can only address
// [0, min(frame_w,512)-1] x [0, min(frame_h,512)-1].  eff_max_* below encodes
// that, and reject fires for any vertex outside it (preventing silent span
// truncation should a future wider command packing ever deliver larger coords).
// ----------------------------------------------------------------------------
module gru_lite_triangle_setup (
    input  logic [`GRU_TRI_CMD_W-1:0] tri_cmd,
    input  logic [15:0]               frame_w,
    input  logic [15:0]               frame_h,
    output logic [`GRU_SEQ_W-1:0]     seq_id,
    output logic [4:0]                opcode,
    output logic [`GRU_COLOR_W-1:0]   color_idx,
    // Phase 2x0 Gouraud: per-vertex RGB565 (flat colour path ignores these).
    output logic [15:0]               c0_rgb565,
    output logic [15:0]               c1_rgb565,
    output logic [15:0]               c2_rgb565,
    output logic signed [10:0]        x0,
    output logic signed [9:0]         y0,
    output logic signed [10:0]        x1,
    output logic signed [9:0]         y1,
    output logic signed [10:0]        x2,
    output logic signed [9:0]         y2,
    output logic signed [10:0]        bbox_min_x,
    output logic signed [10:0]        bbox_max_x,
    output logic signed [9:0]         bbox_min_y,
    output logic signed [9:0]         bbox_max_y,
    output logic signed [23:0]        area2,
    output logic                      reject
);
    // Raw signed coords as packed by gru_top_lt (sign-extended 9-bit x / 8-bit y
    // into the 16-bit GRU_TRI_CMD_* fields).  The OOB check uses these
    // full-width values; only after the check passes are they narrowed to the
    // Lite datapath (x [10:0], y [9:0]).
    logic signed [15:0] rx0, ry0, rx1, ry1, rx2, ry2;
    logic signed [15:0] frame_max_x, frame_max_y;
    logic signed [15:0] eff_max_x, eff_max_y;
    logic               vert_oob;

    // 2x signed area = edge function evaluated at v2 over edge (v0->v1):
    //   E(p,a,b) = (px-ax)(by-ay) - (py-ay)(bx-ax).
    // Identical to gru_lite_triangle_raster.lite_edge() so setup and raster
    // agree on winding sign.  Operands are extended one place wider than their
    // stored width so a full-range difference never overflows before the
    // multiply (defensive; reject already bounds coords, so |diff| <= 511).
    function automatic logic signed [23:0] lite_edge(
        input logic signed [10:0] px,
        input logic signed [9:0]  py,
        input logic signed [10:0] ax,
        input logic signed [9:0]  ay,
        input logic signed [10:0] bx,
        input logic signed [9:0]  by
    );
        logic signed [12:0] px_e, ax_e, bx_e;
        logic signed [11:0] py_e, ay_e, by_e;
        logic signed [12:0] dx_a, dx_b;
        logic signed [11:0] dy_a, dy_b;
        logic signed [25:0] t1, t2;
        begin
            px_e = px;  ax_e = ax;  bx_e = bx;
            py_e = py;  ay_e = ay;  by_e = by;
            dx_a = px_e - ax_e;
            dy_a = py_e - ay_e;
            dx_b = bx_e - ax_e;
            dy_b = by_e - ay_e;
            t1 = dx_a * dy_b;
            t2 = dy_a * dx_b;
            lite_edge = t1 - t2;   // |.| <= 765442 < 2^20 -> fits [23:0] (see raster proof)
        end
    endfunction

    always_comb begin
        seq_id    = tri_cmd[`GRU_TRI_CMD_SEQ_MSB:`GRU_TRI_CMD_SEQ_LSB];
        opcode    = tri_cmd[`GRU_TRI_CMD_OPCODE_MSB:`GRU_TRI_CMD_OPCODE_LSB];
        color_idx = tri_cmd[`GRU_TRI_CMD_ATTR0_LO_LSB +: 8];
        // Gouraud per-vertex colours.  gru_top_lt packs the Gouraud ext-words as
        // c0->ATTR0_LO, c1->ATTR1_LO, c2->ATTR2_LO (mirrors cfg_driver /
        // gru_ref_model), identical to engine_3d/gru_triangle_setup.
        c0_rgb565 = tri_cmd[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB];
        c1_rgb565 = tri_cmd[`GRU_TRI_CMD_ATTR1_LO_MSB:`GRU_TRI_CMD_ATTR1_LO_LSB];
        c2_rgb565 = tri_cmd[`GRU_TRI_CMD_ATTR2_LO_MSB:`GRU_TRI_CMD_ATTR2_LO_LSB];

        rx0 = $signed(tri_cmd[`GRU_TRI_CMD_X0_MSB:`GRU_TRI_CMD_X0_LSB]);
        ry0 = $signed(tri_cmd[`GRU_TRI_CMD_Y0_MSB:`GRU_TRI_CMD_Y0_LSB]);
        rx1 = $signed(tri_cmd[`GRU_TRI_CMD_X1_MSB:`GRU_TRI_CMD_X1_LSB]);
        ry1 = $signed(tri_cmd[`GRU_TRI_CMD_Y1_MSB:`GRU_TRI_CMD_Y1_LSB]);
        rx2 = $signed(tri_cmd[`GRU_TRI_CMD_X2_MSB:`GRU_TRI_CMD_X2_LSB]);
        ry2 = $signed(tri_cmd[`GRU_TRI_CMD_Y2_MSB:`GRU_TRI_CMD_Y2_LSB]);

        frame_max_x = $signed({1'b0, frame_w}) - 16'sd1;
        frame_max_y = $signed({1'b0, frame_h}) - 16'sd1;
        // Span format caps each axis at 9 bits (0..511); the engine cannot
        // address beyond that regardless of framebuffer width.
        eff_max_x = (frame_w >= 16'd512) ? 16'sd511 : frame_max_x;
        eff_max_y = (frame_h >= 16'd512) ? 16'sd511 : frame_max_y;

        // Lite reject: any vertex outside the addressable range.  Checked on the
        // raw 16-bit values because narrowing an out-of-range coord could wrap
        // it back into range.  When !vert_oob every coord lies in [0, eff_max],
        // so the [10:0]/[9:0] narrowing below is exact.
        vert_oob = (rx0 < 0) | (rx0 > eff_max_x) | (ry0 < 0) | (ry0 > eff_max_y) |
                   (rx1 < 0) | (rx1 > eff_max_x) | (ry1 < 0) | (ry1 > eff_max_y) |
                   (rx2 < 0) | (rx2 > eff_max_x) | (ry2 < 0) | (ry2 > eff_max_y);

        x0 = rx0[10:0];  y0 = ry0[9:0];
        x1 = rx1[10:0];  y1 = ry1[9:0];
        x2 = rx2[10:0];  y2 = ry2[9:0];

        area2 = lite_edge(x2, y2, x0, y0, x1, y1);

        // bbox = vertex min/max.  No clipping needed: vert_oob already forces
        // every vertex into [0, eff_max], so the bbox is inside the frame and
        // min <= max whenever !reject.
        bbox_min_x = x0;
        if (x1 < bbox_min_x) bbox_min_x = x1;
        if (x2 < bbox_min_x) bbox_min_x = x2;
        bbox_max_x = x0;
        if (x1 > bbox_max_x) bbox_max_x = x1;
        if (x2 > bbox_max_x) bbox_max_x = x2;
        bbox_min_y = y0;
        if (y1 < bbox_min_y) bbox_min_y = y1;
        if (y2 < bbox_min_y) bbox_min_y = y2;
        bbox_max_y = y0;
        if (y1 > bbox_max_y) bbox_max_y = y1;
        if (y2 > bbox_max_y) bbox_max_y = y2;

        reject = vert_oob |
                 (area2 == 24'sd0) |
                 (frame_w == 16'd0) | (frame_h == 16'd0);
    end
endmodule
