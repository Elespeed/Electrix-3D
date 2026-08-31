module gru_vertex_fetch #(
    parameter int VERTEX_W = 128
) (
    input  logic [VERTEX_W-1:0] vertex_data,
    output logic signed [31:0]  x_q16_16,
    output logic signed [31:0]  y_q16_16,
    output logic signed [31:0]  z_q16_16,
    output logic signed [31:0]  w_q16_16
);
    always_comb begin
        x_q16_16 = vertex_data[31:0];
        y_q16_16 = vertex_data[63:32];
        z_q16_16 = vertex_data[95:64];
        w_q16_16 = vertex_data[127:96];
    end
endmodule
