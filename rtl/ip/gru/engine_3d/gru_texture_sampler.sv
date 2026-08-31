`include "gru_defs.vh"

module gru_texture_sampler (
    input  logic [127:0] beat_data,
    input  logic [3:0]   texel_byte_lane,
    input  logic [2:0]   tex_format,
    output logic [15:0]  rgb565,
    output logic         format_supported
);
    always_comb begin
        rgb565 = 16'h0000;
        format_supported = 1'b0;
        if (tex_format == `GRU_PIXFMT_RGB565) begin
            rgb565 = beat_data[(texel_byte_lane * 8) +: 16];
            format_supported = 1'b1;
        end
    end
endmodule
