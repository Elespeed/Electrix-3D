package gru_cmd_pkg;

task automatic gru_push_cmd(input [31:0] w0, input [31:0] w1);
    begin
        ctrl_write(1'b1, `GRU_REG_CMD_W0, w0);
        ctrl_write(1'b1, `GRU_REG_CMD_W1, w1);
        ctrl_write(1'b1, `GRU_REG_CMD_PUSH, 32'h1);
    end
endtask

task automatic gru_issue_clear(input [7:0] color_idx);
    begin
        gru_push_cmd(pack_cmd_w0(`GRU_OP_CLEAR, color_idx, 2'd0, 9'd0, 8'd0), 32'd0);
        expected_clear(color_idx);
    end
endtask

task automatic gru_issue_fill_rect(
    input [8:0] x,
    input [7:0] y,
    input integer w,
    input integer h,
    input [7:0] color_idx
);
    begin
        gru_push_cmd(
            pack_cmd_w0(`GRU_OP_FILL_RECT, color_idx, 2'd0, x, y),
            pack_cmd_w1_xy(x + w - 1, y + h - 1)
        );
        expected_fill_rect(x, y, w, h, color_idx);
    end
endtask

task automatic gru_issue_draw_rect(
    input integer x,
    input integer y,
    input integer w,
    input integer h,
    input [7:0] color_idx
);
    begin
        if ((w <= 0) || (h <= 0)) begin
            disable gru_issue_draw_rect;
        end
        gru_issue_draw_line(x, y, x + w - 1, y, color_idx);
        gru_issue_draw_line(x, y + h - 1, x + w - 1, y + h - 1, color_idx);
        gru_issue_draw_line(x, y, x, y + h - 1, color_idx);
        gru_issue_draw_line(x + w - 1, y, x + w - 1, y + h - 1, color_idx);
    end
endtask

task automatic gru_issue_draw_line(
    input integer x0,
    input integer y0,
    input integer x1,
    input integer y1,
    input [7:0] color_idx
);
    begin
        gru_push_cmd(
            pack_cmd_w0(`GRU_OP_DRAW_LINE, color_idx, 2'd0, x0[8:0], y0[7:0]),
            pack_cmd_w1_xy(x1[8:0], y1[7:0])
        );
        expected_draw_line(x0, y0, x1, y1, color_idx);
    end
endtask

task automatic gru_issue_draw_glyph(
    input [8:0] x,
    input [7:0] y,
    input [7:0] ascii,
    input [1:0] font_id,
    input [7:0] color_idx
);
    begin
        gru_push_cmd(
            pack_cmd_w0(`GRU_OP_DRAW_GLYPH, color_idx, font_id, x, y),
            pack_cmd_w1_ascii(ascii)
        );
        expected_draw_glyph(x, y, ascii, font_id, color_idx);
    end
endtask

endpackage