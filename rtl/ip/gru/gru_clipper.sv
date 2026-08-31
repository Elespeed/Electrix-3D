`include "gru_defs.vh"

module gru_clipper (
    input  logic [`GRU_X_W-1:0] x0_in,
    input  logic [`GRU_Y_W-1:0] y0_in,
    input  logic [`GRU_X_W-1:0] x1_in,
    input  logic [`GRU_Y_W-1:0] y1_in,
    input  logic [15:0]         frame_w,
    input  logic [15:0]         frame_h,
    output logic [`GRU_X_W-1:0] x0_out,
    output logic [`GRU_Y_W-1:0] y0_out,
    output logic [`GRU_X_W-1:0] x1_out,
    output logic [`GRU_Y_W-1:0] y1_out,
    output logic                empty
);
    logic signed [15:0] xa;
    logic signed [15:0] xb;
    logic signed [15:0] ya;
    logic signed [15:0] yb;
    logic signed [15:0] xmax;
    logic signed [15:0] ymax;

    always_comb begin
        xa = {7'd0, x0_in};
        xb = {7'd0, x1_in};
        ya = {8'd0, y0_in};
        yb = {8'd0, y1_in};

        if (xa > xb) begin
            xa = {7'd0, x1_in};
            xb = {7'd0, x0_in};
        end
        if (ya > yb) begin
            ya = {8'd0, y1_in};
            yb = {8'd0, y0_in};
        end

        xmax = (frame_w == 16'd0) ? 16'sd0 : $signed({1'b0, frame_w}) - 16'sd1;
        ymax = (frame_h == 16'd0) ? 16'sd0 : $signed({1'b0, frame_h}) - 16'sd1;

        if (xa < 0) begin
            xa = 0;
        end
        if (ya < 0) begin
            ya = 0;
        end
        if (xb > xmax) begin
            xb = xmax;
        end
        if (yb > ymax) begin
            yb = ymax;
        end

        empty = (frame_w == 16'd0) || (frame_h == 16'd0) || (xa > xb) || (ya > yb);
        x0_out = xa[`GRU_X_W-1:0];
        y0_out = ya[`GRU_Y_W-1:0];
        x1_out = xb[`GRU_X_W-1:0];
        y1_out = yb[`GRU_Y_W-1:0];
    end
endmodule
