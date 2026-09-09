`timescale 1ns/1ps
module rt_3d_soc_tb #(
`ifdef RT3D_MODEL_S0
    parameter string SCENE_EXT_INIT_FILE = "../../experiments/3d_scene/assets/S0/model.s3d.mif"
`elsif RT3D_MODEL_S1
    parameter string SCENE_EXT_INIT_FILE = "../../experiments/3d_scene/assets/S1/model.s3d.mif"
`elsif RT3D_MODEL_S2
    parameter string SCENE_EXT_INIT_FILE = "../../experiments/3d_scene/assets/S2/model.s3d.mif"
`elsif RT3D_MODEL_S3
    parameter string SCENE_EXT_INIT_FILE = "../../experiments/3d_scene/assets/S3/model.s3d.mif"
`elsif RT3D_MODEL_S4
    parameter string SCENE_EXT_INIT_FILE = "../../experiments/3d_scene/assets/S4/model.s3d.mif"
`elsif MODELSIM_BUILD
    parameter string SCENE_EXT_INIT_FILE = "../../../assets/3d/generated/blade/v4/blade_shade.s3d.mif"
`else
    parameter string SCENE_EXT_INIT_FILE = "../../assets/3d/generated/blade/v4/blade_shade.s3d.mif"
`endif
);
    import uart_agent_pkg::*;
    // S4's CPU-only software transform is substantially longer than the
    // original S0 smoke.  Keep the timeout above the largest benchmark while
    // preserving an explicit bounded failure for a real boot/render stall.
    localparam int UART_WAIT_TIMEOUT = 20_000_000;
`ifdef RT3D_MODE_CPU_ONLY
    localparam string EXPECT_BACKEND = "CPU_ONLY";
`elsif RT3D_MODE_CPU_MATMUL
    localparam string EXPECT_BACKEND = "CPU_MATMUL";
`else
    localparam string EXPECT_BACKEND = "SCENE_CONTROLLER";
`endif
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
    integer cpu_mmio_writes = 0, matmul_writes = 0, matmul_reads = 0;
    integer cpu_clear_cmds = 0, cpu_triangle_cmds = 0, cpu_present_cmds = 0;
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
    sram_sp #(.AW(18), .Init_File(SCENE_EXT_INIT_FILE)) ext_sram_sp (
        .ram_addr(ext_ram_addr), .ram_be_n(ext_ram_be_n), .ram_ce_n(ext_ram_ce_n),
        .ram_oe_n(ext_ram_oe_n), .ram_we_n(ext_ram_we_n), .ram_data(ext_ram_data));
    uart_agent uart (.clk, .rst_n(~reset), .uart_rx(UART_RX), .uart_tx(UART_TX),
        .apb_psel(dut.u_axi_uart_controller.uart0.PSEL),
        .apb_penable(dut.u_axi_uart_controller.uart0.PENABLE),
        .apb_pwrite(dut.u_axi_uart_controller.uart0.PWRITE),
        .apb_paddr(dut.u_axi_uart_controller.uart0.PADDR[7:0]),
        .apb_pwdata(dut.u_axi_uart_controller.uart0.PWDATA[7:0]));
    always @(posedge dut.confreg_int) if (!reset) irq_edges = irq_edges + 1;
    always @(posedge dut.ext_irq) if (!reset) cpu_irq_edges = cpu_irq_edges + 1;
    always @(posedge dut.sys_clk) begin
        // IRQ is level-sensitive.  Sample sticky status every system clock so
        // an earlier RENDER_DONE edge cannot hide the subsequent FRAME_DONE.
        if (!reset) irq_status_seen = irq_status_seen | dut.g_scene_ctrl.u_scene_ctrl.irq_status;
        if (!reset && dut.dma_m_arvalid && dut.dma_m_arready) scene_reads = scene_reads + 1;
        if (!reset && dut.scene_mmio_valid && dut.scene_mmio_ready && dut.scene_mmio_we)
            scene_cmds = scene_cmds + 1;
        if (!reset && dut.sketch_mmio_valid && dut.sketch_mmio_ready && dut.sketch_mmio_we) begin
            cpu_mmio_writes = cpu_mmio_writes + 1;
            if (dut.sketch_mmio_addr[11:0] == 12'h018) begin
                case (dut.u_sketch_book.cmd0[4:0])
                    5'd0: cpu_clear_cmds = cpu_clear_cmds + 1;
                    5'd5: cpu_triangle_cmds = cpu_triangle_cmds + 1;
                    5'd6: cpu_present_cmds = cpu_present_cmds + 1;
                    default: ;
                endcase
            end
        end
        if (!reset && dut.axiOut_7_awvalid && dut.axiOut_7_awready)
            matmul_writes = matmul_writes + 1;
        if (!reset && dut.axiOut_7_arvalid && dut.axiOut_7_arready)
            matmul_reads = matmul_reads + 1;
        if (!reset && dut.u_sketch_book.err_active_write)
            $fatal(1, "active-page SketchBook write");
    end

    initial begin
        #200; reset = 1'b0; wait(dut.sys_resetn);
        uart.uart_wait_tx_string({"RT3D START backend=", EXPECT_BACKEND}, UART_WAIT_TIMEOUT, 1'b1);
`ifdef RT3D_MODE_CPU_ONLY
        // CPU modes report completion through SketchBook's frame-done status,
        // rather than the Scene Controller IRQ path.
        uart.uart_wait_tx_string("RT3D FRAME mode=CPU_ONLY", UART_WAIT_TIMEOUT, 1'b1);
        // Do not finish immediately after the JSON prefix: UART transmits the
        // long record serially, and the parser needs its newline-complete
        // record before DVI evidence is emitted.
        uart.uart_wait_tx_string("RT3D COMPLETE", UART_WAIT_TIMEOUT, 1'b1);
        if (scene_cmds != 0 || scene_reads != 0)
            $fatal(1, "CPU_ONLY unexpectedly used Scene MMIO/master reads cmds=%0d reads=%0d", scene_cmds, scene_reads);
        if (cpu_clear_cmds == 0 || cpu_triangle_cmds == 0 || cpu_present_cmds == 0)
            $fatal(1, "CPU_ONLY missing SketchBook commands clear=%0d tri=%0d present=%0d", cpu_clear_cmds, cpu_triangle_cmds, cpu_present_cmds);
`elsif RT3D_MODE_CPU_MATMUL
        uart.uart_wait_tx_string("RT3D FRAME mode=CPU_MATMUL", UART_WAIT_TIMEOUT, 1'b1);
        uart.uart_wait_tx_string("RT3D COMPLETE", UART_WAIT_TIMEOUT, 1'b1);
        if (scene_cmds != 0 || scene_reads != 0)
            $fatal(1, "CPU_MATMUL unexpectedly used Scene MMIO/master reads cmds=%0d reads=%0d", scene_cmds, scene_reads);
        if (cpu_clear_cmds == 0 || cpu_triangle_cmds == 0 || cpu_present_cmds == 0)
            $fatal(1, "CPU_MATMUL missing SketchBook commands clear=%0d tri=%0d present=%0d", cpu_clear_cmds, cpu_triangle_cmds, cpu_present_cmds);
        if (matmul_writes == 0 || matmul_reads == 0)
            $fatal(1, "CPU_MATMUL missing matrix MMIO traffic writes=%0d reads=%0d", matmul_writes, matmul_reads);
`else
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
`endif
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
        $display("[rt_3d_soc_tb] PASS backend=%s irq_edges=%0d cpu_irq_edges=%0d reads=%0d cmds=%0d cpu_mmio=%0d clear=%0d tri=%0d present=%0d matmul_wr=%0d matmul_rd=%0d frames=%0d load=%0d transform=%0d tris=%0d",
                 EXPECT_BACKEND,
                 irq_edges, cpu_irq_edges, scene_reads, scene_cmds,
                 cpu_mmio_writes, cpu_clear_cmds, cpu_triangle_cmds, cpu_present_cmds,
                 matmul_writes, matmul_reads,
                 dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count,
                 dut.g_scene_ctrl.u_scene_ctrl.perf_load_bytes,
                 dut.g_scene_ctrl.u_scene_ctrl.perf_transform_cycles,
                 dut.g_scene_ctrl.u_scene_ctrl.perf_input_triangles);
        $finish;
    end
    initial begin
        repeat (25_000_000) @(posedge clk);
        if (!done) $fatal(1, "rt_3d SoC timeout wait=%0b wake=%0b irq=%0d pc=%08x",
                          saw_wait, saw_wake, irq_edges, dut.debug_wb_pc);
    end
endmodule
