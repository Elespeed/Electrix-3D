module dvi_adapter (
    input  logic        clk,
    input  logic [15:0] pixel_rgb565,
    input  logic        de,
    input  logic        hsync,
    input  logic        vsync,
    output logic [4:0]  video_red,
    output logic [5:0]  video_green,
    output logic [4:0]  video_blue,
    output logic        video_hsync,
    output logic        video_vsync,
    output logic        video_de,
    output logic        video_clk
);

    assign video_clk   = clk;
    assign video_hsync = hsync;
    assign video_vsync = vsync;
    assign video_de    = de;

    assign video_red   = de ? pixel_rgb565[15:11] : 5'b00000;
    assign video_green = de ? pixel_rgb565[10:5]  : 6'b000000;
    assign video_blue  = de ? pixel_rgb565[4:0]   : 5'b00000;

endmodule
