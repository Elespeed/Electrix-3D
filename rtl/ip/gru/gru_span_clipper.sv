`include "gru_defs.vh"

module gru_span_clipper (
    input  logic                   in_valid,
    output logic                   in_ready,
    input  logic [`GRU_SPAN_W-1:0] in_span,

    output logic                   out_valid,
    input  logic                   out_ready,
    output logic [`GRU_SPAN_W-1:0] out_span,

    input  logic [15:0]            frame_w,
    input  logic [15:0]            frame_h
);
    logic [15:0] span_x;
    logic [15:0] span_y;
    logic [15:0] span_len;
    logic        span_last;
    logic [16:0] span_end_exclusive;
    logic [15:0] clipped_len;
    logic        drop_span;
    logic        emit_placeholder;
    logic        emit_span;
    logic        clip_len_needed;

    always_comb begin
        span_x = {7'd0, in_span[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB]};
        span_y = {7'd0, in_span[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB]};
        span_len = in_span[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB];
        span_last = in_span[`GRU_SPAN_LAST_BIT];
        span_end_exclusive = {1'b0, span_x} + {1'b0, span_len};

        drop_span = (span_y >= frame_h) || (span_x >= frame_w) || (span_len == 16'd0);
        emit_placeholder = drop_span && span_last;
        emit_span = ~drop_span || emit_placeholder;
        clip_len_needed = ~drop_span && (span_end_exclusive > {1'b0, frame_w});
        clipped_len = clip_len_needed ? (frame_w - span_x) : span_len;

        out_valid = in_valid && emit_span;
        in_ready = emit_span ? out_ready : 1'b1;

        out_span = in_span;
        if (emit_placeholder) begin
            out_span[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = '0;
            out_span[`GRU_SPAN_LAST_BIT] = 1'b1;
        end else if (clip_len_needed) begin
            out_span[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = clipped_len[`GRU_LEN_W-1:0];
        end
    end
endmodule
