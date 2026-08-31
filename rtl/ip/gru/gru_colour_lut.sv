module gru_colour_lut (
    input  logic [7:0]  color_idx,
    output logic [15:0] rgb565
);
    always_comb begin
        // colour_idx is the driver's 3:3:2 quantised RGB565 value.  It is
        // not a palette index: treating 0x03 as a special "green" entry
        // turned RGB565 blue (0x0018 -> idx 0x03) into a green background.
        // Replicate the high bits to recover a valid 5:6:5 colour.  The old
        // expression was 17 bits wide and silently truncated its red MSB.
        rgb565 = {
            color_idx[7:5], color_idx[7:6],
            color_idx[4:2], color_idx[4:2],
            color_idx[1:0], color_idx[1:0], color_idx[1]
        };
    end
endmodule
