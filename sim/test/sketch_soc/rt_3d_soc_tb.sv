`timescale 1ns/1ps
module rt_3d_soc_tb;
    import uart_agent_pkg::*;
    localparam int UART_WAIT_TIMEOUT = 2_000_000;
    logic clk = 1'b0, reset = 1'b1;
    logic [3:0] touch_btn = '0;
    logic [31:0] dip_sw = '0;
    tri UART_RX, UART_TX;
    tri [31:0] base_ram_data, ext_ram_data;
    wire [2:0] video_red, video_green; wire [1:0] video_blue;
    wire video_hsync, video_vsync, video_clk, video_de;
    wire [15:0] leds; wire [7:0] dpy0, dpy1;
    wire [19:0] base_ram_addr, ext_ram_addr;
    wire [3:0] base_ram_be_n, ext_ram_be_n;
    wire base_ram_ce_n, base_ram_oe_n, base_ram_we_n;
    wire ext_ram_ce_n, ext_ram_oe_n, ext_ram_we_n;
    integer irq_edges = 0, cpu_irq_edges = 0, scene_reads = 0, scene_cmds = 0;
    integer captured_frame_before = 0;
    logic [2:0] irq_status_seen = 3'b000;
    logic saw_wait = 1'b0, saw_wake = 1'b0, done = 1'b0;

    always #10 clk = ~clk;
    soc_top_sketch #(.SIMULATION(1'b1)) dut (
        .clk, .reset, .touch_btn, .dip_sw,
        .video_red, .video_green, .video_blue, .video_hsync, .video_vsync,
        .video_clk, .video_de, .leds, .dpy0, .dpy1,
        .base_ram_data, .base_ram_addr, .base_ram_be_n, .base_ram_ce_n,
        .base_ram_oe_n, .base_ram_we_n, .ext_ram_data, .ext_ram_addr,
        .ext_ram_be_n, .ext_ram_ce_n, .ext_ram_oe_n, .ext_ram_we_n,
        .UART_RX, .UART_TX);
    dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0), .TESTCASE("rt_3d_soc_tb"),
                           .OUTPUT_ROOT("../../sim/frame_output")) mon (
        .video_clk, .resetn(~reset),
        .video_red({video_red, video_red[2:1]}),
        .video_green({video_green, video_green}),
        .video_blue({video_blue, video_blue, video_blue[1]}),
        .video_hsync, .video_vsync, .video_de);
    sram_sp #(.AW(18), .Init_File("../../sdk/axi_ram.mif")) base_sram_sp (
        .ram_addr(base_ram_addr), .ram_be_n(base_ram_be_n), .ram_ce_n(base_ram_ce_n),
        .ram_oe_n(base_ram_oe_n), .ram_we_n(base_ram_we_n), .ram_data(base_ram_data));
`ifdef MODELSIM_BUILD
    localparam string SCENE_EXT_INIT_FILE = "../../../assets/3d/generated/blade/v4/blade_shade.s3d.mif";
`else
    localparam string SCENE_EXT_INIT_FILE = "../../assets/3d/generated/blade/v4/blade_shade.s3d.mif";
`endif
    sram_sp #(.AW(18), .Init_File(SCENE_EXT_INIT_FILE)) ext_sram_sp (
        .ram_addr(ext_ram_addr), .ram_be_n(ext_ram_be_n), .ram_ce_n(ext_ram_ce_n),
        .ram_oe_n(ext_ram_oe_n), .ram_we_n(ext_ram_we_n), .ram_data(ext_ram_data));
    uart_agent uart (.clk, .rst_n(~reset), .uart_rx(UART_RX), .uart_tx(UART_TX),
        .apb_psel(dut.u_axi_uart_controller.uart0.PSEL),
        .apb_penable(dut.u_axi_uart_controller.uart0.PENABLE),
        .apb_pwrite(dut.u_axi_uart_controller.uart0.PWRITE),
        .apb_paddr(dut.u_axi_uart_controller.uart0.PADDR[7:0]),
        .apb_pwdata(dut.u_axi_uart_controller.uart0.PWDATA[7:0]));
    always @(posedge dut.confreg_int) if (!reset) begin
        irq_edges = irq_edges + 1;
        irq_status_seen = dut.g_scene_ctrl.u_scene_ctrl.irq_status;
    end
    always @(posedge dut.ext_irq) if (!reset) cpu_irq_edges = cpu_irq_edges + 1;
    always @(posedge dut.sys_clk) begin
        if (!reset && dut.dma_m_arvalid && dut.dma_m_arready) scene_reads = scene_reads + 1;
        if (!reset && dut.scene_mmio_valid && dut.scene_mmio_ready && dut.scene_mmio_we)
            scene_cmds = scene_cmds + 1;
        if (!reset && dut.u_sketch_book.err_active_write)
            $fatal(1, "active-page SketchBook write");
    end

    initial begin
        #200; reset = 1'b0; wait(dut.sys_resetn);
        uart.uart_wait_tx_string("RT3D START backend=SCENE_CONTROLLER", UART_WAIT_TIMEOUT, 1'b1);
        uart.uart_wait_tx_string("RT3D IRQ WAIT seq=1", UART_WAIT_TIMEOUT, 1'b1);
        saw_wait = 1'b1;
        if (irq_edges == 0) $fatal(1, "Scene completion did not assert confreg bit6 IRQ");
        if (cpu_irq_edges == 0)
            $fatal(1, "confreg IRQ did not reach CPU ext_irq");
        uart.uart_wait_tx_string("RT3D IRQ WAKE seq=1", UART_WAIT_TIMEOUT, 1'b1);
        saw_wake = 1'b1;
        if (irq_status_seen[2])
            $fatal(1, "Scene ERROR IRQ asserted");
        if (!irq_status_seen[1])
            $fatal(1, "IRQ wake did not report FRAME_DONE status");
        if (dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count == 0)
            $fatal(1, "Scene frame counter did not advance");
        if (!saw_wait || !saw_wake || irq_edges == 0 || cpu_irq_edges == 0 || scene_reads == 0 || scene_cmds == 0)
            $fatal(1, "missing end-to-end evidence wait=%0b wake=%0b irq=%0d cpu_irq=%0d reads=%0d cmds=%0d",
                   saw_wait, saw_wake, irq_edges, cpu_irq_edges, scene_reads, scene_cmds);
        if (dut.g_scene_ctrl.u_scene_ctrl.perf_load_bytes == 0 ||
            dut.g_scene_ctrl.u_scene_ctrl.perf_transform_cycles == 0 ||
            dut.g_scene_ctrl.u_scene_ctrl.perf_input_triangles == 0)
            $fatal(1, "T11 counters not populated load=%0d transform=%0d tris=%0d",
                   dut.g_scene_ctrl.u_scene_ctrl.perf_load_bytes,
                   dut.g_scene_ctrl.u_scene_ctrl.perf_transform_cycles,
                   dut.g_scene_ctrl.u_scene_ctrl.perf_input_triangles);
        // FRAME_DONE proves rendering completed, but the double-buffered DVI
        // output becomes observable only after the PRESENT reaches vblank and
        // the monitor completes the following scanout frame.
        captured_frame_before = mon.captured_frame_id;
        wait (mon.captured_frame_id >= captured_frame_before + 2);
        mon.assert_captured_region_nonblack(0, 0, 799, 599, 100,
                                            "rt_3d_scene_visible");
        mon.dump_captured_frame("rt_3d_soc_render");
        mon.flush_and_close();
        done = 1'b1;
        $display("[rt_3d_soc_tb] PASS irq_edges=%0d cpu_irq_edges=%0d reads=%0d cmds=%0d frames=%0d load=%0d transform=%0d tris=%0d",
                 irq_edges, cpu_irq_edges, scene_reads, scene_cmds,
                 dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count,
                 dut.g_scene_ctrl.u_scene_ctrl.perf_load_bytes,
                 dut.g_scene_ctrl.u_scene_ctrl.perf_transform_cycles,
                 dut.g_scene_ctrl.u_scene_ctrl.perf_input_triangles);
        $finish;
    end
    initial begin
        repeat (8_000_000) @(posedge clk);
        if (!done) $fatal(1, "rt_3d SoC timeout wait=%0b wake=%0b irq=%0d pc=%08x",
                          saw_wait, saw_wake, irq_edges, dut.debug_wb_pc);
    end
endmodule
