module output_adapter (
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

    dvi_adapter u_dvi_adapter (
        .clk         (clk),
        .pixel_rgb565(pixel_rgb565),
        .de          (de),
        .hsync       (hsync),
        .vsync       (vsync),
        .video_red   (video_red),
        .video_green (video_green),
        .video_blue  (video_blue),
        .video_hsync (video_hsync),
        .video_vsync (video_vsync),
        .video_de    (video_de),
        .video_clk   (video_clk)
    );

endmodule
