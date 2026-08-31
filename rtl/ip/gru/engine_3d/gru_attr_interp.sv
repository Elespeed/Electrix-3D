module gru_attr_interp (
    input  logic signed [31:0] area2,
    input  logic signed [31:0] w0,
    input  logic signed [31:0] w1,
    input  logic signed [31:0] w2,
    input  logic [15:0]        c0_rgb565,
    input  logic [15:0]        c1_rgb565,
    input  logic [15:0]        c2_rgb565,
    output logic [15:0]        rgb565
);
    function automatic logic [5:0] interp_channel(
        input logic signed [31:0] bary0,
        input logic signed [31:0] bary1,
        input logic signed [31:0] bary2,
        input logic signed [31:0] area_twice,
        input logic [5:0]         v0,
        input logic [5:0]         v1,
        input logic [5:0]         v2
    );
        logic signed [41:0] term0;
        logic signed [41:0] term1;
        logic signed [41:0] term2;
        logic signed [41:0] numer;
        logic signed [31:0] denom;
        logic signed [41:0] value;
        begin
            term0 = $signed({{10{bary0[31]}}, bary0}) * $signed({36'd0, v0});
            term1 = $signed({{10{bary1[31]}}, bary1}) * $signed({36'd0, v1});
            term2 = $signed({{10{bary2[31]}}, bary2}) * $signed({36'd0, v2});
            numer = term0 + term1 + term2;
            denom = area_twice;
            if (denom < 0) begin
                numer = -numer;
                denom = -denom;
            end
            if (denom == 0) begin
                value = 42'sd0;
            end else begin
                value = numer / $signed({{10{denom[31]}}, denom});
            end

            if (value < 0) begin
                interp_channel = 6'd0;
            end else if (value > 63) begin
                interp_channel = 6'd63;
            end else begin
                interp_channel = value[5:0];
            end
        end
    endfunction

    logic [4:0] r0, r1, r2;
    logic [5:0] g0, g1, g2;
    logic [4:0] b0, b1, b2;
    logic [5:0] r_interp;
    logic [5:0] g_interp;
    logic [5:0] b_interp;

    always_comb begin
        r0 = c0_rgb565[15:11];
        g0 = c0_rgb565[10:5];
        b0 = c0_rgb565[4:0];
        r1 = c1_rgb565[15:11];
        g1 = c1_rgb565[10:5];
        b1 = c1_rgb565[4:0];
        r2 = c2_rgb565[15:11];
        g2 = c2_rgb565[10:5];
        b2 = c2_rgb565[4:0];

        r_interp = interp_channel(w0, w1, w2, area2, {1'b0, r0}, {1'b0, r1}, {1'b0, r2});
        g_interp = interp_channel(w0, w1, w2, area2, g0, g1, g2);
        b_interp = interp_channel(w0, w1, w2, area2, {1'b0, b0}, {1'b0, b1}, {1'b0, b2});

        rgb565 = {r_interp[4:0], g_interp, b_interp[4:0]};
    end
endmodule
