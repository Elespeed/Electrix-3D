`include "../gru/gru_defs.vh"

// SketchBook front-end for the GRU Lite setup/raster pair in RGB332 mode.
module sketch_triangle_lite_adapter #(
    parameter bit ENABLE_GOURAUD = 1'b0
) (
    input  logic        clk,
    input  logic        resetn,
    input  logic        clear,
    input  logic        start,
    input  logic        gouraud_en,
    input  logic signed [15:0] x0,
    input  logic signed [15:0] y0,
    input  logic signed [15:0] x1,
    input  logic signed [15:0] y1,
    input  logic signed [15:0] x2,
    input  logic signed [15:0] y2,
    input  logic [7:0] c0_rgb332,
    input  logic [7:0] c1_rgb332,
    input  logic [7:0] c2_rgb332,
    input  logic [15:0] frame_w,
    input  logic [15:0] frame_h,
    output logic        busy,
    output logic        span_valid,
    input  logic        span_ready,
    output logic [63:0] span_data
);
    logic [`GRU_TRI_CMD_W-1:0] tri_cmd;
    logic [`GRU_SEQ_W-1:0] seq_id;
    logic [4:0] opcode_unused;
    logic [`GRU_COLOR_W-1:0] color_unused;
    logic [15:0] setup_c0, setup_c1, setup_c2;
    logic signed [10:0] sx0, sx1, sx2, bbox_min_x, bbox_max_x;
    logic signed [9:0] sy0, sy1, sy2, bbox_min_y, bbox_max_y;
    logic signed [23:0] area2;
    logic reject;
    logic gouraud_active;

    // This is a synthesis-time constant when disabled.  It permits Vivado to
    // eliminate the rasterizer's gradient, reciprocal and colour-DDA logic.
    assign gouraud_active = ENABLE_GOURAUD && gouraud_en;

    always_comb begin
        tri_cmd = '0;
        tri_cmd[`GRU_TRI_CMD_OPCODE_MSB:`GRU_TRI_CMD_OPCODE_LSB] =
            gouraud_active ? `GRU_OP_TRIANGLE_GOURAUD : `GRU_OP_TRIANGLE_FLAT;
        tri_cmd[`GRU_TRI_CMD_X0_MSB:`GRU_TRI_CMD_X0_LSB] = x0;
        tri_cmd[`GRU_TRI_CMD_Y0_MSB:`GRU_TRI_CMD_Y0_LSB] = y0;
        tri_cmd[`GRU_TRI_CMD_X1_MSB:`GRU_TRI_CMD_X1_LSB] = x1;
        tri_cmd[`GRU_TRI_CMD_Y1_MSB:`GRU_TRI_CMD_Y1_LSB] = y1;
        tri_cmd[`GRU_TRI_CMD_X2_MSB:`GRU_TRI_CMD_X2_LSB] = x2;
        tri_cmd[`GRU_TRI_CMD_Y2_MSB:`GRU_TRI_CMD_Y2_LSB] = y2;
        tri_cmd[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB] = {8'd0, c0_rgb332};
        tri_cmd[`GRU_TRI_CMD_ATTR1_LO_MSB:`GRU_TRI_CMD_ATTR1_LO_LSB] = {8'd0, c1_rgb332};
        tri_cmd[`GRU_TRI_CMD_ATTR2_LO_MSB:`GRU_TRI_CMD_ATTR2_LO_LSB] = {8'd0, c2_rgb332};
    end

    gru_lite_triangle_setup u_setup (
        tri_cmd, frame_w, frame_h, seq_id, opcode_unused, color_unused,
        setup_c0, setup_c1, setup_c2, sx0, sy0, sx1, sy1, sx2, sy2,
        bbox_min_x, bbox_max_x, bbox_min_y, bbox_max_y, area2, reject
    );

    gru_lite_triangle_raster #(.ENABLE_GOURAUD(ENABLE_GOURAUD), .RGB332_MODE(1'b1)) u_raster (
        clk, resetn, clear, start, '0, {8'd0, c0_rgb332}, gouraud_active,
        gouraud_active ? setup_c0 : {8'd0, c0_rgb332},
        gouraud_active ? setup_c1 : {8'd0, c1_rgb332},
        gouraud_active ? setup_c2 : {8'd0, c2_rgb332},
        sx0, sy0, sx1, sy1, sx2, sy2, bbox_min_x, bbox_max_x, bbox_min_y,
        bbox_max_y, area2, reject, busy, span_valid, span_ready, span_data
    );
endmodule
