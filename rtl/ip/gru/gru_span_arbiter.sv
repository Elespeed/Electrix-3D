`include "gru_defs.vh"

module gru_span_arbiter (
    input  logic [`GRU_SEQ_W-1:0]  retire_seq,
    input  logic                   writer_ready,
    input  logic                   clear_valid,
    input  logic [`GRU_SPAN_W-1:0] clear_data,
    output logic                   clear_rd_en,
    input  logic                   rect_valid,
    input  logic [`GRU_SPAN_W-1:0] rect_data,
    output logic                   rect_rd_en,
    input  logic                   line_valid,
    input  logic [`GRU_SPAN_W-1:0] line_data,
    output logic                   line_rd_en,
    input  logic                   glyph_valid,
    input  logic [`GRU_SPAN_W-1:0] glyph_data,
    output logic                   glyph_rd_en,
    input  logic                   triangle_valid,
    input  logic [`GRU_SPAN_W-1:0] triangle_data,
    output logic                   triangle_rd_en,
    output logic                   writer_valid,
    output logic [`GRU_SPAN_W-1:0] writer_data
);
    logic clear_match;
    logic rect_match;
    logic line_match;
    logic glyph_match;
    logic triangle_match;

    always_comb begin
        clear_match = clear_valid &&
                      (clear_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] == retire_seq);
        rect_match = rect_valid &&
                     (rect_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] == retire_seq);
        line_match = line_valid &&
                     (line_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] == retire_seq);
        glyph_match = glyph_valid &&
                      (glyph_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] == retire_seq);
        triangle_match = triangle_valid &&
                         (triangle_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] == retire_seq);

        writer_valid = 1'b0;
        writer_data = '0;
        clear_rd_en = 1'b0;
        rect_rd_en = 1'b0;
        line_rd_en = 1'b0;
        glyph_rd_en = 1'b0;
        triangle_rd_en = 1'b0;

        if (clear_match) begin
            writer_valid = 1'b1;
            writer_data = clear_data;
            clear_rd_en = writer_ready;
        end else if (rect_match) begin
            writer_valid = 1'b1;
            writer_data = rect_data;
            rect_rd_en = writer_ready;
        end else if (line_match) begin
            writer_valid = 1'b1;
            writer_data = line_data;
            line_rd_en = writer_ready;
        end else if (glyph_match) begin
            writer_valid = 1'b1;
            writer_data = glyph_data;
            glyph_rd_en = writer_ready;
        end else if (triangle_match) begin
            writer_valid = 1'b1;
            writer_data = triangle_data;
            triangle_rd_en = writer_ready;
        end
    end
endmodule
