// Paper benchmark top: CPU-driven Q8.8 matrix multiplication followed by the
// unchanged CPU-to-SketchBook command path.  This wrapper deliberately leaves
// the Scene Controller uninstantiated while retaining the board-level contract.
module soc_top_sketch_matmul #(parameter SIMULATION=1'b0) (
    input clk,
    input reset,
    output [2:0] video_red,
    output [2:0] video_green,
    output [1:0] video_blue,
    output video_hsync,
    output video_vsync,
    output video_clk,
    output video_de,
    input [3:0] touch_btn,
    input [31:0] dip_sw,
    output [15:0] leds,
    output [7:0] dpy0,
    output [7:0] dpy1,
    inout [31:0] base_ram_data,
    output [19:0] base_ram_addr,
    output [3:0] base_ram_be_n,
    output base_ram_ce_n,
    output base_ram_oe_n,
    output base_ram_we_n,
    inout [31:0] ext_ram_data,
    output [19:0] ext_ram_addr,
    output [3:0] ext_ram_be_n,
    output ext_ram_ce_n,
    output ext_ram_oe_n,
    output ext_ram_we_n,
    inout UART_RX,
    inout UART_TX
);
    soc_top_sketch_matmul_core #(
        .SIMULATION(SIMULATION)
    ) u_soc (
        .clk(clk), .reset(reset),
        .video_red(video_red), .video_green(video_green), .video_blue(video_blue),
        .video_hsync(video_hsync), .video_vsync(video_vsync),
        .video_clk(video_clk), .video_de(video_de),
        .touch_btn(touch_btn), .dip_sw(dip_sw), .leds(leds), .dpy0(dpy0), .dpy1(dpy1),
        .base_ram_data(base_ram_data), .base_ram_addr(base_ram_addr),
        .base_ram_be_n(base_ram_be_n), .base_ram_ce_n(base_ram_ce_n),
        .base_ram_oe_n(base_ram_oe_n), .base_ram_we_n(base_ram_we_n),
        .ext_ram_data(ext_ram_data), .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n), .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n), .ext_ram_we_n(ext_ram_we_n),
        .UART_RX(UART_RX), .UART_TX(UART_TX)
    );
endmodule

// Keep the dedicated parameter localized to this source: this is a pin- and
// behavior-compatible copy of the baseline top with only the Matmul instance
// selecting its registered read response.
module soc_top_sketch_matmul_core #(parameter SIMULATION=1'b0) (
    input clk, input reset,
    output [2:0] video_red, output [2:0] video_green, output [1:0] video_blue,
    output video_hsync, output video_vsync, output video_clk, output video_de,
    input [3:0] touch_btn, input [31:0] dip_sw, output [15:0] leds,
    output [7:0] dpy0, output [7:0] dpy1, inout [31:0] base_ram_data,
    output [19:0] base_ram_addr, output [3:0] base_ram_be_n, output base_ram_ce_n,
    output base_ram_oe_n, output base_ram_we_n, inout [31:0] ext_ram_data,
    output [19:0] ext_ram_addr, output [3:0] ext_ram_be_n, output ext_ram_ce_n,
    output ext_ram_oe_n, output ext_ram_we_n, inout UART_RX, inout UART_TX
);
    soc_top_sketch #(.SIMULATION(SIMULATION), .ENABLE_SCENE(1'b0),
                     .MATMUL_LATCHED_READ_RESPONSE(1'b1)) u_soc_base (
        .clk(clk), .reset(reset), .video_red(video_red), .video_green(video_green), .video_blue(video_blue),
        .video_hsync(video_hsync), .video_vsync(video_vsync), .video_clk(video_clk), .video_de(video_de),
        .touch_btn(touch_btn), .dip_sw(dip_sw), .leds(leds), .dpy0(dpy0), .dpy1(dpy1),
        .base_ram_data(base_ram_data), .base_ram_addr(base_ram_addr), .base_ram_be_n(base_ram_be_n),
        .base_ram_ce_n(base_ram_ce_n), .base_ram_oe_n(base_ram_oe_n), .base_ram_we_n(base_ram_we_n),
        .ext_ram_data(ext_ram_data), .ext_ram_addr(ext_ram_addr), .ext_ram_be_n(ext_ram_be_n),
        .ext_ram_ce_n(ext_ram_ce_n), .ext_ram_oe_n(ext_ram_oe_n), .ext_ram_we_n(ext_ram_we_n), .UART_RX(UART_RX), .UART_TX(UART_TX));
endmodule
