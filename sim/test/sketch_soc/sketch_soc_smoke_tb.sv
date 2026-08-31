`timescale 1ns/1ps

// CPU-driven SoC smoke: the program image writes only SketchBook's AXI/MMIO
// command registers.  The display framebuffer remains private to SketchBook
// BRAM; the external SRAMs only hold normal CPU program/data memory.
module sketch_soc_smoke_tb;
    import uart_agent_pkg::*;

    localparam int UART_WAIT_TIMEOUT = 2_000_000;
    localparam int TEST_TIMEOUT_CYCLES = 5_000_000;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [3:0] touch_btn = '0;
    logic [31:0] dip_sw = '0;
    tri UART_RX, UART_TX;
    tri [31:0] base_ram_data, ext_ram_data;
    wire [2:0] video_red, video_green;
    wire [1:0] video_blue;
    wire video_hsync, video_vsync, video_clk, video_de;
    wire [15:0] leds;
    wire [7:0] dpy0, dpy1;
    wire [19:0] base_ram_addr, ext_ram_addr;
    wire [3:0] base_ram_be_n, ext_ram_be_n;
    wire base_ram_ce_n, base_ram_oe_n, base_ram_we_n;
    wire ext_ram_ce_n, ext_ram_oe_n, ext_ram_we_n;
    integer de_edges = 0;
    integer sketch_axi_writes = 0;
    logic done = 1'b0;

    task automatic expect_captured_pixel(
        input integer x, input integer y,
        input integer expected_r, input integer expected_g, input integer expected_b,
        input [8*64-1:0] label
    );
        integer index;
        begin
            index = y * 800 + x;
            if ((mon.captured_frame_r[index] != expected_r) ||
                (mon.captured_frame_g[index] != expected_g) ||
                (mon.captured_frame_b[index] != expected_b)) begin
                $fatal(1, "[sketch_soc_smoke_tb] %0s at (%0d,%0d): got %0d,%0d,%0d expected %0d,%0d,%0d",
                       label, x, y, mon.captured_frame_r[index], mon.captured_frame_g[index],
                       mon.captured_frame_b[index], expected_r, expected_g, expected_b);
            end
        end
    endtask

    always #10 clk = ~clk;
    always @(posedge video_clk) if (video_de) de_edges = de_edges + 1;
    always @(posedge dut.sys_clk) begin
        if (dut.dvi_awvalid && dut.dvi_awready &&
            ((dut.dvi_awaddr & 32'hfff0_0000) == 32'h1f10_0000))
            sketch_axi_writes = sketch_axi_writes + 1;
        if (!reset && dut.u_sketch_book.err_active_write)
            $fatal(1, "[sketch_soc_smoke_tb] SketchBook active-page write error");
        if (!reset && dut.u_sketch_book.u_gru.error)
            $fatal(1, "[sketch_soc_smoke_tb] SketchBook renderer error");
    end

    // Keep the same RGB332 -> RGB565-expanded monitor adaptation used by the
    // standalone SketchBook regression so board-pin output is captured.
    dvi_monitor_800x600 #(
        .FRAME_DUMP_LIMIT(0),
        .TESTCASE("sketch_soc_smoke_tb"),
        .OUTPUT_ROOT("../../sim/frame_output")
    ) mon (
        .video_clk(video_clk), .resetn(~reset),
        .video_red({video_red, video_red[2:1]}),
        .video_green({video_green, video_green}),
        .video_blue({video_blue, video_blue, video_blue[1]}),
        .video_hsync(video_hsync), .video_vsync(video_vsync), .video_de(video_de)
    );

    soc_top_sketch #(.SIMULATION(1'b1)) dut (
        .clk, .reset, .touch_btn, .dip_sw,
        .video_red, .video_green, .video_blue, .video_hsync, .video_vsync, .video_clk, .video_de,
        .leds, .dpy0, .dpy1,
        .base_ram_data, .base_ram_addr, .base_ram_be_n, .base_ram_ce_n, .base_ram_oe_n, .base_ram_we_n,
        .ext_ram_data, .ext_ram_addr, .ext_ram_be_n, .ext_ram_ce_n, .ext_ram_oe_n, .ext_ram_we_n,
        .UART_RX, .UART_TX
    );

    sram_sp #(.AW(18), .Init_File("../../sdk/axi_ram.mif")) base_sram_sp (
        .ram_addr(base_ram_addr), .ram_be_n(base_ram_be_n), .ram_ce_n(base_ram_ce_n),
        .ram_oe_n(base_ram_oe_n), .ram_we_n(base_ram_we_n), .ram_data(base_ram_data)
    );

    sram_sp #(.AW(18), .Init_File("../../sdk/axi_ram.mif")) ext_sram_sp (
        .ram_addr(ext_ram_addr), .ram_be_n(ext_ram_be_n), .ram_ce_n(ext_ram_ce_n),
        .ram_oe_n(ext_ram_oe_n), .ram_we_n(ext_ram_we_n), .ram_data(ext_ram_data)
    );

    uart_agent u_uart_agent (
        .clk(clk), .rst_n(~reset), .uart_rx(UART_RX), .uart_tx(UART_TX),
        .apb_psel(dut.u_axi_uart_controller.uart0.PSEL),
        .apb_penable(dut.u_axi_uart_controller.uart0.PENABLE),
        .apb_pwrite(dut.u_axi_uart_controller.uart0.PWRITE),
        .apb_paddr(dut.u_axi_uart_controller.uart0.PADDR[7:0]),
        .apb_pwdata(dut.u_axi_uart_controller.uart0.PWDATA[7:0])
    );

    initial begin
        #200;
        reset = 1'b0;
        wait(dut.sys_resetn);
        // axi_ram.mif now boots Sketch OS instead of the legacy fixed 2D demo.
        u_uart_agent.uart_wait_tx_string("SK_OS READY", UART_WAIT_TIMEOUT, 1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);
        repeat (1_500_000) @(posedge clk);
        if (sketch_axi_writes == 0)
            $fatal(1, "[sketch_soc_smoke_tb] CPU never wrote SketchBook AXI window");
        if (de_edges < (800 * 600))
            $fatal(1, "[sketch_soc_smoke_tb] no complete DVI active frame");
        if (mon.captured_frame_id == 0)
            $fatal(1, "[sketch_soc_smoke_tb] no captured 800x600 DVI frame");
        mon.assert_captured_region_nonblack(0, 0, 799, 599, 1000, "sk_os_home_frame");
        mon.dump_captured_frame("sketch_soc_render");
        done = 1'b1;
        $display("[sketch_soc_smoke_tb] PASS Sketch OS AXI writes=%0d DVI active pixels=%0d", sketch_axi_writes, de_edges);
        $finish;
    end

    initial begin
        repeat (TEST_TIMEOUT_CYCLES) @(posedge clk);
        if (!done)
            $fatal(1, "[sketch_soc_smoke_tb] global timeout");
    end
endmodule
