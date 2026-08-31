module gru_viewport_transform (
    input  logic signed [31:0] ndc_x_q16_16,
    input  logic signed [31:0] ndc_y_q16_16,
    input  logic signed [31:0] ndc_z_q16_16,
    input  logic [15:0]        viewport_x,
    input  logic [15:0]        viewport_y,
    input  logic [15:0]        viewport_w,
    input  logic [15:0]        viewport_h,
    output logic signed [15:0] screen_x,
    output logic signed [15:0] screen_y,
    output logic [15:0]        screen_z
);
    logic signed [63:0] sx_q16_16;
    logic signed [63:0] sy_q16_16;
    logic signed [63:0] sz_q16_16;
    logic signed [31:0] one_q16_16;
    logic signed [31:0] half_q16_16;

    always_comb begin
        one_q16_16 = 32'sh0001_0000;
        half_q16_16 = 32'sh0000_8000;

        sx_q16_16 = (((ndc_x_q16_16 + one_q16_16) * viewport_w) >>> 1) + (viewport_x <<< 16);
        sy_q16_16 = (((one_q16_16 - ndc_y_q16_16) * viewport_h) >>> 1) + (viewport_y <<< 16);
        sz_q16_16 = (ndc_z_q16_16 + one_q16_16) >>> 1;

        screen_x = $signed((sx_q16_16 + half_q16_16) >>> 16);
        screen_y = $signed((sy_q16_16 + half_q16_16) >>> 16);

        if (sz_q16_16 < 0) begin
            screen_z = 16'd0;
        end else if (sz_q16_16 > 64'sh0000_0000_ffff_0000) begin
            screen_z = 16'hffff;
        end else begin
            screen_z = sz_q16_16[31:16];
        end
    end
endmodule
