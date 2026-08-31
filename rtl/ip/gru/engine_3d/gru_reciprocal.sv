// 1/x for the perspective texture recovery path.
//
// Output format is SIGNED Q4.28 (range [-8, +8)): it represents w = 1/inv_w,
// and w in the perspective test cases reaches 4.0..5.0.  An earlier Q2.30
// output (range [-2, +2)) wrapped to negative for any w >= 2.0, which made
// recover_coord produce negative u/v and collapsed the whole w>=2 region of
// every perspective triangle to texel (0,0).  Q4.28 covers the delivered w
// range with margin; widen further (lose fractional bits) if near-zero inv_w
// (very large w) sweeps are added later.
module gru_reciprocal (
    input  logic signed [31:0] in_q16_16,
    output logic               valid,
    output logic               divide_by_zero,
    output logic signed [31:0] reciprocal_q4_28
);
    logic signed [63:0] recip_abs_q4_28;
    logic signed [31:0] in_abs_q16_16;

    always_comb begin
        divide_by_zero = (in_q16_16 == 32'sd0);
        valid = ~divide_by_zero;
        in_abs_q16_16 = in_q16_16[31] ? -in_q16_16 : in_q16_16;
        recip_abs_q4_28 = 64'sd0;
        reciprocal_q4_28 = 32'sd0;

        if (!divide_by_zero) begin
            // Q4.28 of (1/inv_w):  (1 << 44) / in_abs_q16_16, since in is Q16.16
            // and 2^(44-16) = 2^28 supplies the Q4.28 fractional scaling.
            recip_abs_q4_28 = (64'sd1 <<< 44) / in_abs_q16_16;
            reciprocal_q4_28 = in_q16_16[31] ? -recip_abs_q4_28[31:0] : recip_abs_q4_28[31:0];
        end
    end
endmodule
