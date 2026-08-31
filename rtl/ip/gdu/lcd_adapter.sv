module lcd_adapter (
    input  logic        clk,
    input  logic        resetn,
    input  logic [15:0] pixel_rgb565,
    input  logic        de,
    input  logic        hsync,
    input  logic        vsync,
    output logic [15:0] lcd_rgb,
    output logic        lcd_hsync,
    output logic        lcd_vsync,
    output logic        lcd_de,
    output logic        lcd_pclk,
    output logic        lcd_rst,
    output logic        lcd_bl_ctr
);

    assign lcd_pclk   = clk;
    assign lcd_rst    = resetn;
    assign lcd_bl_ctr = 1'b1;
    assign lcd_hsync  = hsync;
    assign lcd_vsync  = vsync;
    assign lcd_de     = de;
    assign lcd_rgb    = de ? pixel_rgb565 : 16'h0000;

endmodule

