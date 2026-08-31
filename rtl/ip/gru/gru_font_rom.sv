module gru_font_rom (
    input  logic [1:0] font_id,
    input  logic [7:0] ascii,
    input  logic [3:0] x,
    input  logic [3:0] y,
    output logic       pixel_on,
    output logic [3:0] glyph_w,
    output logic [3:0] glyph_h,
    // Bit 0 is the left-most visible glyph pixel.  Consumers that scan one
    // row at a time can register this bus before finding horizontal runs.
    output logic [7:0] row_bits,
    output logic       glyph_empty
);
    logic [39:0] glyph_bits_5x7;
    logic [7:0]  glyph_col_5x7;
    logic [3:0]  x5;
    logic [3:0]  y5;
    logic [7:0]  x_scaled;
    logic [7:0]  y_scaled;

    function automatic [39:0] glyph_5x7(input [7:0] ch);
        begin
            case (ch)
`include "gru_font_5x7_table.svh"
                default: glyph_5x7 = 40'h0000000000;
            endcase
        end
    endfunction

    always_comb begin
        case (font_id)
            2'd1: begin
                glyph_w = 4'd5;
                glyph_h = 4'd7;
            end
            2'd2: begin
                glyph_w = 4'd6;
                glyph_h = 4'd8;
            end
            default: begin
                glyph_w = 4'd4;
                glyph_h = 4'd6;
            end
        endcase
    end

    always_comb begin
        glyph_bits_5x7 = glyph_5x7(ascii);
        x5 = 4'd0;
        y5 = 4'd0;
        x_scaled = 8'd0;
        y_scaled = 8'd0;
        pixel_on = 1'b0;
        glyph_col_5x7 = 8'd0;
        row_bits = 8'd0;
        glyph_empty = (glyph_bits_5x7 == 40'd0);

        case (font_id)
            2'd1: begin
                if ((x < 4'd5) && (y < 4'd7)) begin
                    x5 = x;
                    y5 = y;
                    glyph_col_5x7 = (glyph_bits_5x7 >> (x5 * 8)) & 8'hff;
                    pixel_on = glyph_col_5x7[y5];
                end
                if (y < 4'd7) begin
                    for (int col = 0; col < 5; col = col + 1)
                        row_bits[col] = glyph_bits_5x7[(col * 8) + y];
                end
            end
            2'd2: begin
                if ((x < 4'd5) && (y < 4'd7)) begin
                    x5 = x;
                    y5 = y;
                    glyph_col_5x7 = (glyph_bits_5x7 >> (x5 * 8)) & 8'hff;
                    pixel_on = glyph_col_5x7[y5];
                end
                if (y < 4'd7) begin
                    for (int col = 0; col < 5; col = col + 1)
                        row_bits[col] = glyph_bits_5x7[(col * 8) + y];
                end
            end
            default: begin
                if ((x < 4'd4) && (y < 4'd6)) begin
                    x_scaled = x * 8'd5;
                    y_scaled = y * 8'd7;
                    x5 = x_scaled / 8'd4;
                    y5 = y_scaled / 8'd6;
                    glyph_col_5x7 = (glyph_bits_5x7 >> (x5 * 8)) & 8'hff;
                    pixel_on = glyph_col_5x7[y5];
                end
                if (y < 4'd6) begin
                    for (int col = 0; col < 4; col = col + 1)
                        row_bits[col] = glyph_bits_5x7[(col * 8) + y];
                end
            end
        endcase
    end
endmodule
