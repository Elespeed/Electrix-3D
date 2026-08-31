`include "gru_defs.vh"

module gru_triangle_setup (
    input  logic [`GRU_TRI_CMD_W-1:0] tri_cmd,
    input  logic [15:0]               frame_w,
    input  logic [15:0]               frame_h,
    output logic [`GRU_SEQ_W-1:0]     seq_id,
    output logic [4:0]                opcode,
    output logic                      gouraud_en,
    output logic                      textured_en,
    output logic                      perspective_en,
    output logic [`GRU_COLOR_W-1:0]   color_idx,
    output logic [15:0]               c0_rgb565,
    output logic [15:0]               c1_rgb565,
    output logic [15:0]               c2_rgb565,
    output logic signed [15:0]        u0_q8_8,
    output logic signed [15:0]        v0_q8_8,
    output logic signed [15:0]        u1_q8_8,
    output logic signed [15:0]        v1_q8_8,
    output logic signed [15:0]        u2_q8_8,
    output logic signed [15:0]        v2_q8_8,
    output logic signed [15:0]        inv_w0_q8_8,
    output logic signed [15:0]        inv_w1_q8_8,
    output logic signed [15:0]        inv_w2_q8_8,
    output logic signed [15:0]        x0,
    output logic signed [15:0]        y0,
    output logic signed [15:0]        x1,
    output logic signed [15:0]        y1,
    output logic signed [15:0]        x2,
    output logic signed [15:0]        y2,
    output logic signed [15:0]        bbox_min_x,
    output logic signed [15:0]        bbox_max_x,
    output logic signed [15:0]        bbox_min_y,
    output logic signed [15:0]        bbox_max_y,
    output logic signed [31:0]        area2,
    output logic                      reject
);
    logic signed [15:0] raw_min_x;
    logic signed [15:0] raw_max_x;
    logic signed [15:0] raw_min_y;
    logic signed [15:0] raw_max_y;
    logic signed [15:0] frame_max_x;
    logic signed [15:0] frame_max_y;

    gru_edge_eval u_area_eval (
        .ax    (x0),
        .ay    (y0),
        .bx    (x1),
        .by    (y1),
        .px    (x2),
        .py    (y2),
        .value (area2)
    );

    always_comb begin
        seq_id     = tri_cmd[`GRU_TRI_CMD_SEQ_MSB:`GRU_TRI_CMD_SEQ_LSB];
        opcode     = tri_cmd[`GRU_TRI_CMD_OPCODE_MSB:`GRU_TRI_CMD_OPCODE_LSB];
        gouraud_en = (opcode == `GRU_OP_TRIANGLE_GOURAUD);
        textured_en = (opcode == `GRU_OP_TRIANGLE_TEXTURED) ||
                      (opcode == `GRU_OP_TRIANGLE_TEXTURED_PC);
        perspective_en = (opcode == `GRU_OP_TRIANGLE_TEXTURED_PC);
        color_idx  = tri_cmd[`GRU_TRI_CMD_ATTR0_LO_LSB +: 8];
        c0_rgb565  = tri_cmd[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB];
        c1_rgb565  = tri_cmd[`GRU_TRI_CMD_ATTR1_LO_MSB:`GRU_TRI_CMD_ATTR1_LO_LSB];
        c2_rgb565  = tri_cmd[`GRU_TRI_CMD_ATTR2_LO_MSB:`GRU_TRI_CMD_ATTR2_LO_LSB];
        u0_q8_8    = tri_cmd[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB];
        v0_q8_8    = tri_cmd[`GRU_TRI_CMD_ATTR0_HI_MSB:`GRU_TRI_CMD_ATTR0_HI_LSB];
        u1_q8_8    = tri_cmd[`GRU_TRI_CMD_ATTR1_LO_MSB:`GRU_TRI_CMD_ATTR1_LO_LSB];
        v1_q8_8    = tri_cmd[`GRU_TRI_CMD_ATTR1_HI_MSB:`GRU_TRI_CMD_ATTR1_HI_LSB];
        u2_q8_8    = tri_cmd[`GRU_TRI_CMD_ATTR2_LO_MSB:`GRU_TRI_CMD_ATTR2_LO_LSB];
        v2_q8_8    = tri_cmd[`GRU_TRI_CMD_ATTR2_HI_MSB:`GRU_TRI_CMD_ATTR2_HI_LSB];
        inv_w0_q8_8 = tri_cmd[`GRU_TRI_CMD_EXTRA0_MSB:`GRU_TRI_CMD_EXTRA0_LSB];
        inv_w1_q8_8 = tri_cmd[`GRU_TRI_CMD_EXTRA1_MSB:`GRU_TRI_CMD_EXTRA1_LSB];
        inv_w2_q8_8 = tri_cmd[`GRU_TRI_CMD_EXTRA2_MSB:`GRU_TRI_CMD_EXTRA2_LSB];
        x0 = tri_cmd[`GRU_TRI_CMD_X0_MSB:`GRU_TRI_CMD_X0_LSB];
        y0 = tri_cmd[`GRU_TRI_CMD_Y0_MSB:`GRU_TRI_CMD_Y0_LSB];
        x1 = tri_cmd[`GRU_TRI_CMD_X1_MSB:`GRU_TRI_CMD_X1_LSB];
        y1 = tri_cmd[`GRU_TRI_CMD_Y1_MSB:`GRU_TRI_CMD_Y1_LSB];
        x2 = tri_cmd[`GRU_TRI_CMD_X2_MSB:`GRU_TRI_CMD_X2_LSB];
        y2 = tri_cmd[`GRU_TRI_CMD_Y2_MSB:`GRU_TRI_CMD_Y2_LSB];

        raw_min_x = x0;
        if (x1 < raw_min_x) raw_min_x = x1;
        if (x2 < raw_min_x) raw_min_x = x2;
        raw_max_x = x0;
        if (x1 > raw_max_x) raw_max_x = x1;
        if (x2 > raw_max_x) raw_max_x = x2;
        raw_min_y = y0;
        if (y1 < raw_min_y) raw_min_y = y1;
        if (y2 < raw_min_y) raw_min_y = y2;
        raw_max_y = y0;
        if (y1 > raw_max_y) raw_max_y = y1;
        if (y2 > raw_max_y) raw_max_y = y2;

        frame_max_x = $signed({1'b0, frame_w}) - 16'sd1;
        frame_max_y = $signed({1'b0, frame_h}) - 16'sd1;

        bbox_min_x = raw_min_x;
        bbox_max_x = raw_max_x;
        bbox_min_y = raw_min_y;
        bbox_max_y = raw_max_y;

        if (bbox_min_x < 0) bbox_min_x = 0;
        if (bbox_min_y < 0) bbox_min_y = 0;
        if (bbox_max_x > frame_max_x) bbox_max_x = frame_max_x;
        if (bbox_max_y > frame_max_y) bbox_max_y = frame_max_y;

        reject = (area2 == 32'sd0) ||
                 (frame_w == 16'd0) || (frame_h == 16'd0) ||
                 (raw_max_x < 0) || (raw_max_y < 0) ||
                 (raw_min_x > frame_max_x) || (raw_min_y > frame_max_y) ||
                 (bbox_min_x > bbox_max_x) || (bbox_min_y > bbox_max_y);
    end
endmodule
