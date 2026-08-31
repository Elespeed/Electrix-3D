module gru_edge_eval (
    input  logic signed [15:0] ax,
    input  logic signed [15:0] ay,
    input  logic signed [15:0] bx,
    input  logic signed [15:0] by,
    input  logic signed [15:0] px,
    input  logic signed [15:0] py,
    output logic signed [31:0] value
);
    logic signed [16:0] apx;
    logic signed [16:0] apy;
    logic signed [16:0] abx;
    logic signed [16:0] aby;

    always_comb begin
        apx = px - ax;
        apy = py - ay;
        abx = bx - ax;
        aby = by - ay;
        value = (apx * aby) - (apy * abx);
    end
endmodule

