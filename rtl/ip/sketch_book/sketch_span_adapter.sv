`include "../gru/gru_defs.vh"

// Adapts the common GRU 64-bit span contract to SketchBook's BRAM writer.
// SketchBook has one ordered writer, therefore sequence bits are deliberately
// consumed here rather than introducing the DDR GRU's sequence arbiter.
module sketch_span_adapter #(
    parameter int ADDR_W = 17
) (
    input  logic [63:0]       in_span,
    output logic [15:0]       span_x,
    output logic [15:0]       span_y,
    output logic [15:0]       span_len,
    output logic [ADDR_W-1:0] span_step,
    output logic [7:0]        span_color,
    output logic              span_last
);
    always_comb begin
        span_x     = {7'd0, in_span[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB]};
        span_y     = {7'd0, in_span[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB]};
        span_len   = {6'd0, in_span[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB]};
        span_step  = ADDR_W'(1);
        span_color = in_span[`GRU_SPAN_COLOR_LSB +: 8];
        span_last  = in_span[`GRU_SPAN_LAST_BIT];
    end
endmodule
