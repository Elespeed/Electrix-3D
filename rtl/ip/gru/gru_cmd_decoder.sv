`include "gru_defs.vh"

module gru_cmd_decoder (
    input  logic                      cmd_valid,
    input  logic [`GRU_CMD_W-1:0]     cmd_data,
    input  logic [`GRU_SEQ_W-1:0]     alloc_seq,
    input  logic                      clear_q_full,
    input  logic                      rect_q_full,
    input  logic                      line_q_full,
    input  logic                      glyph_q_full,
    input  logic                      triangle_q_full,
    output logic                      dispatch_fire,
    output logic                      cfg_error_pulse,
    output logic                      clear_q_wr_en,
    output logic                      rect_q_wr_en,
    output logic                      line_q_wr_en,
    output logic                      glyph_q_wr_en,
    output logic                      triangle_q_wr_en,
    output logic [`GRU_ENGINE_CMD_W-1:0] clear_q_wr_data,
    output logic [`GRU_ENGINE_CMD_W-1:0] rect_q_wr_data,
    output logic [`GRU_ENGINE_CMD_W-1:0] line_q_wr_data,
    output logic [`GRU_ENGINE_CMD_W-1:0] glyph_q_wr_data,
    output logic [`GRU_TRI_CMD_W-1:0]    triangle_q_wr_data
);
    logic [`GRU_OPCODE_W-1:0] opcode;
    logic [`GRU_COLOR_W-1:0]  color_idx;
    logic [`GRU_FONT_W-1:0]   font_id;
    logic [`GRU_X_W-1:0]      x0;
    logic [`GRU_Y_W-1:0]      y0;
    logic [`GRU_X_W-1:0]      x1;
    logic [`GRU_Y_W-1:0]      y1;
    logic                     target_ready;
    logic [1:0]               target_sel;

    always_comb begin
        opcode = cmd_data[`GRU_CMD0_OPCODE_MSB:`GRU_CMD0_OPCODE_LSB];
        color_idx = cmd_data[`GRU_CMD0_COLOR_MSB:`GRU_CMD0_COLOR_LSB];
        font_id = cmd_data[`GRU_CMD0_FONT_MSB:`GRU_CMD0_FONT_LSB];
        x0 = cmd_data[`GRU_CMD0_X0_MSB:`GRU_CMD0_X0_LSB];
        y0 = {cmd_data[32 + `GRU_CMD1_Y0_HI_BIT],
              cmd_data[`GRU_CMD0_Y0_MSB:`GRU_CMD0_Y0_LSB]};
        x1 = cmd_data[32 + `GRU_CMD1_X1_MSB:32 + `GRU_CMD1_X1_LSB];
        y1 = {cmd_data[32 + `GRU_CMD1_Y1_HI_BIT],
              cmd_data[32 + `GRU_CMD1_Y1_MSB:32 + `GRU_CMD1_Y1_LSB]};

        target_sel = 2'd0;
        cfg_error_pulse = 1'b0;
        case (opcode)
            `GRU_OP_CLEAR: begin
                target_sel = 2'd0;
            end
            `GRU_OP_FILL_RECT: begin
                target_sel = 2'd1;
            end
            `GRU_OP_DRAW_LINE: begin
                target_sel = 2'd2;
            end
            `GRU_OP_DRAW_GLYPH: begin
                target_sel = 2'd3;
            end
            default: begin
                target_sel = 2'd1;
                cfg_error_pulse = cmd_valid;
            end
        endcase

        case (target_sel)
            2'd0: target_ready = ~clear_q_full;
            2'd1: target_ready = ~rect_q_full;
            2'd2: target_ready = ~line_q_full;
            default: target_ready = ~glyph_q_full;
        endcase

        dispatch_fire = cmd_valid & target_ready;

        clear_q_wr_en = dispatch_fire & (target_sel == 2'd0);
        rect_q_wr_en  = dispatch_fire & (target_sel == 2'd1);
        line_q_wr_en  = dispatch_fire & (target_sel == 2'd2);
        glyph_q_wr_en = dispatch_fire & (target_sel == 2'd3);
        triangle_q_wr_en = 1'b0;

        clear_q_wr_data = '0;
        rect_q_wr_data  = '0;
        line_q_wr_data  = '0;
        glyph_q_wr_data = '0;
        triangle_q_wr_data = '0;

        clear_q_wr_data[`GRU_ECMD_OPCODE_MSB:`GRU_ECMD_OPCODE_LSB] = opcode;
        clear_q_wr_data[`GRU_ECMD_COLOR_MSB:`GRU_ECMD_COLOR_LSB] = color_idx;
        clear_q_wr_data[`GRU_ECMD_FONT_MSB:`GRU_ECMD_FONT_LSB] = font_id;
        clear_q_wr_data[`GRU_ECMD_X0_MSB:`GRU_ECMD_X0_LSB] = x0;
        clear_q_wr_data[`GRU_ECMD_Y0_MSB:`GRU_ECMD_Y0_LSB] = y0;
        clear_q_wr_data[`GRU_ECMD_X1_MSB:`GRU_ECMD_X1_LSB] = x1;
        clear_q_wr_data[`GRU_ECMD_Y1_MSB:`GRU_ECMD_Y1_LSB] = y1;
        clear_q_wr_data[`GRU_ECMD_Y0_HI_BIT] = y0[`GRU_Y_W-1];
        clear_q_wr_data[`GRU_ECMD_Y1_HI_BIT] = y1[`GRU_Y_W-1];
        clear_q_wr_data[`GRU_ECMD_SEQ_MSB:`GRU_ECMD_SEQ_LSB] = alloc_seq;

        rect_q_wr_data = clear_q_wr_data;
        line_q_wr_data = clear_q_wr_data;
        glyph_q_wr_data = clear_q_wr_data;

        if (cfg_error_pulse) begin
            rect_q_wr_data[`GRU_ECMD_OPCODE_MSB:`GRU_ECMD_OPCODE_LSB] = `GRU_OP_FILL_RECT;
            rect_q_wr_data[`GRU_ECMD_X0_MSB:`GRU_ECMD_X0_LSB] = 9'd1;
            rect_q_wr_data[`GRU_ECMD_Y0_MSB:`GRU_ECMD_Y0_LSB] = 9'd1;
            rect_q_wr_data[`GRU_ECMD_X1_MSB:`GRU_ECMD_X1_LSB] = 9'd0;
            rect_q_wr_data[`GRU_ECMD_Y1_MSB:`GRU_ECMD_Y1_LSB] = 9'd0;
        end
    end
endmodule
