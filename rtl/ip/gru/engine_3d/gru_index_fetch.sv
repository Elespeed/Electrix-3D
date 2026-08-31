module gru_index_fetch (
    input  logic [127:0] beat_data,
    input  logic [3:0]   byte_offset,
    input  logic [1:0]   index_format,
    output logic [15:0]  index_value,
    output logic         format_supported
);
    always_comb begin
        index_value = 16'd0;
        format_supported = 1'b0;

        case (index_format)
            2'd0: begin
                index_value = {8'd0, beat_data[(byte_offset * 8) +: 8]};
                format_supported = 1'b1;
            end
            2'd1: begin
                if (byte_offset != 4'hf) begin
                    index_value = beat_data[(byte_offset * 8) +: 16];
                    format_supported = 1'b1;
                end
            end
            default: begin
            end
        endcase
    end
endmodule
