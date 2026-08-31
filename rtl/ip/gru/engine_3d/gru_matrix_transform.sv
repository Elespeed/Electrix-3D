module gru_matrix_transform (
    input  logic signed [31:0] in_x_q16_16,
    input  logic signed [31:0] in_y_q16_16,
    input  logic signed [31:0] in_z_q16_16,
    input  logic signed [31:0] in_w_q16_16,
    input  logic signed [15:0] m00_q2_14,
    input  logic signed [15:0] m01_q2_14,
    input  logic signed [15:0] m02_q2_14,
    input  logic signed [15:0] m03_q2_14,
    input  logic signed [15:0] m10_q2_14,
    input  logic signed [15:0] m11_q2_14,
    input  logic signed [15:0] m12_q2_14,
    input  logic signed [15:0] m13_q2_14,
    input  logic signed [15:0] m20_q2_14,
    input  logic signed [15:0] m21_q2_14,
    input  logic signed [15:0] m22_q2_14,
    input  logic signed [15:0] m23_q2_14,
    input  logic signed [15:0] m30_q2_14,
    input  logic signed [15:0] m31_q2_14,
    input  logic signed [15:0] m32_q2_14,
    input  logic signed [15:0] m33_q2_14,
    output logic signed [31:0] out_x_q16_16,
    output logic signed [31:0] out_y_q16_16,
    output logic signed [31:0] out_z_q16_16,
    output logic signed [31:0] out_w_q16_16
);
    logic signed [47:0] dot_x_q18_30;
    logic signed [47:0] dot_y_q18_30;
    logic signed [47:0] dot_z_q18_30;
    logic signed [47:0] dot_w_q18_30;

    always_comb begin
        dot_x_q18_30 =
            (in_x_q16_16 * m00_q2_14) +
            (in_y_q16_16 * m01_q2_14) +
            (in_z_q16_16 * m02_q2_14) +
            (in_w_q16_16 * m03_q2_14);
        dot_y_q18_30 =
            (in_x_q16_16 * m10_q2_14) +
            (in_y_q16_16 * m11_q2_14) +
            (in_z_q16_16 * m12_q2_14) +
            (in_w_q16_16 * m13_q2_14);
        dot_z_q18_30 =
            (in_x_q16_16 * m20_q2_14) +
            (in_y_q16_16 * m21_q2_14) +
            (in_z_q16_16 * m22_q2_14) +
            (in_w_q16_16 * m23_q2_14);
        dot_w_q18_30 =
            (in_x_q16_16 * m30_q2_14) +
            (in_y_q16_16 * m31_q2_14) +
            (in_z_q16_16 * m32_q2_14) +
            (in_w_q16_16 * m33_q2_14);

        out_x_q16_16 = dot_x_q18_30[45:14];
        out_y_q16_16 = dot_y_q18_30[45:14];
        out_z_q16_16 = dot_z_q18_30[45:14];
        out_w_q16_16 = dot_w_q18_30[45:14];
    end
endmodule
