module gru_barycentric (
    input  logic signed [15:0] px,
    input  logic signed [15:0] py,
    input  logic signed [15:0] x0,
    input  logic signed [15:0] y0,
    input  logic signed [15:0] x1,
    input  logic signed [15:0] y1,
    input  logic signed [15:0] x2,
    input  logic signed [15:0] y2,
    output logic signed [31:0] w0,
    output logic signed [31:0] w1,
    output logic signed [31:0] w2
);
    logic signed [16:0] dx01;
    logic signed [16:0] dy01;
    logic signed [16:0] dx02;
    logic signed [16:0] dy02;
    logic signed [16:0] dx10;
    logic signed [16:0] dy10;
    logic signed [16:0] dx12;
    logic signed [16:0] dy12;
    logic signed [16:0] dx20;
    logic signed [16:0] dy20;
    logic signed [16:0] dx21;
    logic signed [16:0] dy21;
    logic signed [33:0] w0_ax;
    logic signed [33:0] w0_ay;
    logic signed [33:0] w1_ax;
    logic signed [33:0] w1_ay;
    logic signed [33:0] w2_ax;
    logic signed [33:0] w2_ay;

    always_comb begin
        dx01 = px - x1;
        dy21 = y2 - y1;
        dy01 = py - y1;
        dx21 = x2 - x1;
        dx02 = px - x2;
        dy02 = py - y2;
        dy20 = y0 - y2;
        dx20 = x0 - x2;
        dx10 = px - x0;
        dy10 = py - y0;
        dy12 = y1 - y0;
        dx12 = x1 - x0;

        w0_ax = $signed({{17{dx01[16]}}, dx01}) * $signed({{17{dy21[16]}}, dy21});
        w0_ay = $signed({{17{dy01[16]}}, dy01}) * $signed({{17{dx21[16]}}, dx21});
        w1_ax = $signed({{17{dx02[16]}}, dx02}) * $signed({{17{dy20[16]}}, dy20});
        w1_ay = $signed({{17{dy02[16]}}, dy02}) * $signed({{17{dx20[16]}}, dx20});
        w2_ax = $signed({{17{dx10[16]}}, dx10}) * $signed({{17{dy12[16]}}, dy12});
        w2_ay = $signed({{17{dy10[16]}}, dy10}) * $signed({{17{dx12[16]}}, dx12});

        w0 = w0_ax - w0_ay;
        w1 = w1_ax - w1_ay;
        w2 = w2_ax - w2_ay;
    end
endmodule
