`include "gru_defs.vh"

// gru_lite_triangle_engine
// ----------------------------------------------------------------------------
// 3D Lite triangle engine (Phase 1x0 flat + Phase 2x0 Gouraud).  Drop-in
// replacement for the Phase 0x0 shell on the SAME port list, so gru_top_lt is
// unchanged.  It rasterizes FLAT and GOURAUD triangles; textured opcodes stay
// unsupported and are drained exactly as the Phase 0x0 shell did.
//
// Retire source differs per opcode (the key invariant; see plan / commit msg):
//   * FLAT / GOURAUD -> render spans carrying seq_id + a final last=1 span and
//              retire through gru_axi_writer (writer_cmd_done_pulse), exactly
//              like the Full-3D gru_triangle_engine (which has no done-pulse of
//              its own).  The engine's own cmd_done_pulse / cfg_error_pulse
//              stay 0 for these.
//   * TEXTURED -> seq-gated drain (pop only when cmd_seq == retire_seq), emit
//              cmd_done_pulse + cfg_error_pulse.  The seq-gate is mandatory:
//              draining out of order would advance retire_seq past an in-flight
//              rendered triangle whose spans the writer has not yet flushed
//              (deadlock).
//
// cmd_ready:
//   idle                -> 1  (fence_complete ANDs triangle_cmd_ready)
//   FLAT/GOURAUD at head-> ~raster_busy & ~setup_pending_q   (accept when free)
//   TEXTURED at head    -> (cmd_seq == retire_seq)           (seq-gated drain)
//
// The raster is itself the rate limiter (one len=1 span per accepted span_ready,
// all span fields registered), so no Lite fragment FIFO is needed.
// ----------------------------------------------------------------------------
module gru_lite_triangle_engine (
    input  logic                       clk,
    input  logic                       rstn,
    input  logic                       clr,
    input  logic [15:0]                frame_w,
    input  logic [15:0]                frame_h,
    input  logic                       cmd_valid,    // = ~triangle_cmd_empty
    output logic                       cmd_ready,
    input  logic [`GRU_TRI_CMD_W-1:0]  cmd_data,
    input  logic [`GRU_SEQ_W-1:0]      retire_seq,
    output logic                       span_valid,
    input  logic                       span_ready,
    output logic [63:0]                span_data,
    output logic                       cmd_done_pulse,
    output logic                       cfg_error_pulse
);
    // ------------------------------------------------------------------
    // Command decode
    // ------------------------------------------------------------------
    logic [4:0]               cmd_opcode;
    logic [`GRU_SEQ_W-1:0]    cmd_seq;
    logic                     is_flat;
    logic                     is_gouraud;
    logic                     is_render;     // FLAT | GOURAUD -> render + writer retire
    assign cmd_opcode = cmd_data[`GRU_TRI_CMD_OPCODE_MSB:`GRU_TRI_CMD_OPCODE_LSB];
    assign cmd_seq    = cmd_data[`GRU_TRI_CMD_SEQ_MSB:`GRU_TRI_CMD_SEQ_LSB];
    assign is_flat    = (cmd_opcode == `GRU_OP_TRIANGLE_FLAT);
    assign is_gouraud = (cmd_opcode == `GRU_OP_TRIANGLE_GOURAUD);
    assign is_render  = is_flat | is_gouraud;

    // ------------------------------------------------------------------
    // Setup (combinational geometry decode)
    // ------------------------------------------------------------------
    logic [`GRU_SEQ_W-1:0] setup_seq;
    logic [`GRU_COLOR_W-1:0] setup_color_idx;
    logic [15:0]          sc0_rgb565, sc1_rgb565, sc2_rgb565;
    logic signed [10:0] sx0, sx1, sx2, sbbox_min_x, sbbox_max_x;
    logic signed [9:0]  sy0, sy1, sy2, sbbox_min_y, sbbox_max_y;
    logic signed [23:0] s_area2;
    logic               s_reject;
    gru_lite_triangle_setup u_setup (
        .tri_cmd   (cmd_data),
        .frame_w   (frame_w),
        .frame_h   (frame_h),
        .seq_id    (setup_seq),
        .opcode    (),
        .color_idx (setup_color_idx),
        .c0_rgb565 (sc0_rgb565),
        .c1_rgb565 (sc1_rgb565),
        .c2_rgb565 (sc2_rgb565),
        .x0        (sx0), .y0 (sy0),
        .x1        (sx1), .y1 (sy1),
        .x2        (sx2), .y2 (sy2),
        .bbox_min_x(sbbox_min_x), .bbox_max_x(sbbox_max_x),
        .bbox_min_y(sbbox_min_y), .bbox_max_y(sbbox_max_y),
        .area2     (s_area2),
        .reject    (s_reject)
    );

    // Flat colour = 8-bit colour_idx expanded to RGB565 (same LUT the 2D and
    // Full-3D engines use).  The raster emits this constant for every flat pixel.
    logic [15:0] flat_rgb565;
    gru_colour_lut u_colour_lut (
        .color_idx (setup_color_idx),
        .rgb565    (flat_rgb565)
    );

    // ------------------------------------------------------------------
    // Latched geometry for the raster (registered on a render accept, mirroring
    // Full-3D gru_triangle_engine.sv's setup_pending_q -> start_raster handshake)
    // ------------------------------------------------------------------
    logic [`GRU_SEQ_W-1:0] seq_q;
    logic [15:0]           flat_rgb565_q;
    logic                  gouraud_q;
    logic [15:0]           c0_q, c1_q, c2_q;
    logic signed [10:0]    x0_q, x1_q, x2_q;
    logic signed [9:0]     y0_q, y1_q, y2_q;
    logic signed [10:0]    bbox_min_x_q, bbox_max_x_q;
    logic signed [9:0]     bbox_min_y_q, bbox_max_y_q;
    logic signed [23:0]    area2_q;
    logic                  reject_q;
    logic                  setup_pending_q;

    logic raster_busy;
    logic start_raster;
    assign start_raster = setup_pending_q & ~raster_busy;

    gru_lite_triangle_raster u_raster (
        .clk        (clk),
        .rstn       (rstn),
        .clr        (clr),
        .start      (start_raster),
        .seq_id     (seq_q),
        .flat_rgb565(flat_rgb565_q),
        .gouraud_en (gouraud_q),
        .c0_rgb565  (c0_q),
        .c1_rgb565  (c1_q),
        .c2_rgb565  (c2_q),
        .x0         (x0_q), .y0 (y0_q),
        .x1         (x1_q), .y1 (y1_q),
        .x2         (x2_q), .y2 (y2_q),
        .bbox_min_x (bbox_min_x_q), .bbox_max_x (bbox_max_x_q),
        .bbox_min_y (bbox_min_y_q), .bbox_max_y (bbox_max_y_q),
        .area2      (area2_q),
        .reject     (reject_q),
        .busy       (raster_busy),
        .span_valid (span_valid),
        .span_ready (span_ready),
        .span_data  (span_data)
    );

    // ------------------------------------------------------------------
    // Pop / dispatch
    // ------------------------------------------------------------------
    logic render_pop;   // FLAT or GOURAUD: latch + start raster
    logic drain_pop;    // TEXTURED: seq-gated drain (unsupported -> cfg_error)
    assign render_pop = cmd_valid & is_render & ~raster_busy & ~setup_pending_q;
    assign drain_pop  = cmd_valid & ~is_render & (cmd_seq == retire_seq);

    assign cmd_ready = ~cmd_valid |
                       (is_render ? (~raster_busy & ~setup_pending_q)
                                  : (cmd_seq == retire_seq));

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            setup_pending_q <= 1'b0;
            cmd_done_pulse  <= 1'b0;
            cfg_error_pulse <= 1'b0;
            seq_q           <= '0;
            flat_rgb565_q   <= '0;
            gouraud_q       <= 1'b0;
            c0_q <= '0; c1_q <= '0; c2_q <= '0;
            x0_q <= '0; y0_q <= '0; x1_q <= '0; y1_q <= '0; x2_q <= '0; y2_q <= '0;
            bbox_min_x_q <= '0; bbox_max_x_q <= '0; bbox_min_y_q <= '0; bbox_max_y_q <= '0;
            area2_q <= '0;
            reject_q <= 1'b0;
        end else if (clr) begin
            setup_pending_q <= 1'b0;
            cmd_done_pulse  <= 1'b0;
            cfg_error_pulse <= 1'b0;
        end else begin
            // Retire / error pulses fire only on the TEXTURED drain pop.  A
            // rendered (FLAT/GOURAUD) command retires through its spans
            // (writer_cmd_done_pulse in gru_top_lt), so these stay 0 for it.
            cmd_done_pulse  <= drain_pop;
            cfg_error_pulse <= drain_pop;

            if (render_pop) begin
                // Latch geometry + colour for the raster (FIFO rd_data is
                // combinational, so these setup outputs still reflect the popped
                // command).
                setup_pending_q <= 1'b1;
                seq_q           <= setup_seq;
                flat_rgb565_q   <= flat_rgb565;
                gouraud_q       <= is_gouraud;
                c0_q <= sc0_rgb565; c1_q <= sc1_rgb565; c2_q <= sc2_rgb565;
                x0_q <= sx0; y0_q <= sy0; x1_q <= sx1; y1_q <= sy1; x2_q <= sx2; y2_q <= sy2;
                bbox_min_x_q <= sbbox_min_x; bbox_max_x_q <= sbbox_max_x;
                bbox_min_y_q <= sbbox_min_y; bbox_max_y_q <= sbbox_max_y;
                area2_q <= s_area2;
                reject_q <= s_reject;
            end else if (start_raster) begin
                setup_pending_q <= 1'b0;
            end
        end
    end
endmodule
