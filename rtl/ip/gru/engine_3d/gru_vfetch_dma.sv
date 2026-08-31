module gru_vfetch_dma #(
    parameter int VERTEX_W = 128
) (
    input  logic [127:0] beat_lo,
    input  logic [127:0] beat_hi,
    input  logic [4:0]   byte_offset,
    input  logic [2:0]   vertex_format,
    output logic [VERTEX_W-1:0] vertex_data,
    output logic                 format_supported
);
    logic [255:0] window_data;
    logic [255:0] shifted_data;

    always_comb begin
        window_data = {beat_hi, beat_lo};
        shifted_data = window_data >> (byte_offset * 8);
        vertex_data = shifted_data[VERTEX_W-1:0];
        format_supported = (vertex_format == 3'd0);
    end
endmodule
