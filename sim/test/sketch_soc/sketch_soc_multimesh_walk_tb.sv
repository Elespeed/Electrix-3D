`timescale 1ns/1ps

module sketch_soc_multimesh_walk_tb;
    import uart_agent_pkg::*;
    localparam int UART_WAIT_TIMEOUT = 60_000_000;
    localparam int TEST_TIMEOUT_CYCLES = 90_000_000;
`ifdef MODELSIM_BUILD
    localparam string SCENE_EXT_INIT_FILE = "../../../assets/3d/generated/robotss/v4/robotss_shade.s3d.mif";
`else
    localparam string SCENE_EXT_INIT_FILE = "../../assets/3d/generated/robotss/v4/robotss_shade.s3d.mif";
`endif
    logic clk = 0, reset = 1;
    logic [3:0] touch_btn = 0;
    logic [31:0] dip_sw = 0;
    tri UART_RX, UART_TX;
    tri [31:0] base_ram_data, ext_ram_data;
    wire [2:0] video_red, video_green;
    wire [1:0] video_blue;
    wire video_hsync, video_vsync, video_clk, video_de;
    wire [15:0] leds;
    wire [7:0] dpy0, dpy1;
    wire [19:0] base_ram_addr, ext_ram_addr;
    wire [3:0] base_ram_be_n, ext_ram_be_n;
    wire base_ram_ce_n, base_ram_oe_n, base_ram_we_n, ext_ram_ce_n, ext_ram_oe_n, ext_ram_we_n;
    integer scene_reads = 0, reads_after_load, fid;
    logic done = 0, cm_error;
    logic [31:0] clears, fills, tris, presents;

    always #10 clk = ~clk;
    always @(posedge dut.sys_clk) if (dut.dma_m_arvalid && dut.dma_m_arready) scene_reads++;

    soc_top_sketch #(.SIMULATION(1'b1)) dut (.*);
    sram_sp #(.AW(18), .Init_File("../../sdk/axi_ram.mif")) base_sram_sp (
        .ram_addr(base_ram_addr), .ram_be_n(base_ram_be_n), .ram_ce_n(base_ram_ce_n), .ram_oe_n(base_ram_oe_n), .ram_we_n(base_ram_we_n), .ram_data(base_ram_data));
    sram_sp #(.AW(18), .Init_File(SCENE_EXT_INIT_FILE)) ext_sram_sp (
        .ram_addr(ext_ram_addr), .ram_be_n(ext_ram_be_n), .ram_ce_n(ext_ram_ce_n), .ram_oe_n(ext_ram_oe_n), .ram_we_n(ext_ram_we_n), .ram_data(ext_ram_data));
    uart_agent uart (.clk, .rst_n(~reset), .uart_rx(UART_RX), .uart_tx(UART_TX),
        .apb_psel(dut.u_axi_uart_controller.uart0.PSEL), .apb_penable(dut.u_axi_uart_controller.uart0.PENABLE),
        .apb_pwrite(dut.u_axi_uart_controller.uart0.PWRITE), .apb_paddr(dut.u_axi_uart_controller.uart0.PADDR[7:0]), .apb_pwdata(dut.u_axi_uart_controller.uart0.PWDATA[7:0]));
    sketch_cmd_monitor cm (.clk(dut.sys_clk), .resetn(dut.sys_resetn), .valid(dut.sketch_mmio_valid), .we(dut.sketch_mmio_we),
        .ready(dut.sketch_mmio_ready), .addr(dut.sketch_mmio_addr), .wdata(dut.sketch_mmio_wdata), .error(cm_error),
        .clear_count(clears), .fill_count(fills), .tri_count(tris), .present_count(presents));
    dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0), .TESTCASE("sketch_soc_multimesh_walk_tb"), .OUTPUT_ROOT("../../sim/frame_output")) mon (
        .video_clk, .resetn(~reset), .video_red({video_red,video_red[2:1]}), .video_green({video_green,video_green}),
        .video_blue({video_blue,video_blue,video_blue[1]}), .video_hsync, .video_vsync, .video_de);

    initial begin
        #200 reset = 0;
        wait(dut.sys_resetn);
        uart.uart_wait_tx_string("SCENE ROBOT WALK START", UART_WAIT_TIMEOUT, 1'b1);
        uart.uart_wait_tx_string("SCENE ROBOT WALK LOADED meshes=5", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.cache_valid);
        if (dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.cmd_mesh_count != 5)
            $fatal(1, "robot mesh count=%0d", dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.cmd_mesh_count);
        reads_after_load = scene_reads;
        uart.uart_wait_tx_string("SCENE ROBOT WALK PASS cycle=1", UART_WAIT_TIMEOUT, 1'b1);
        if (dut.g_scene_ctrl.u_scene_ctrl.error) $fatal(1, "Scene error=%0d", dut.g_scene_ctrl.u_scene_ctrl.error_code);
        if (scene_reads != reads_after_load) $fatal(1, "robot reread ExtRAM after cache valid: load=%0d total=%0d", reads_after_load, scene_reads);
        if (clears < 16 || presents < 16 || tris == 0)
            $fatal(1, "command count clear=%0d tri=%0d present=%0d", clears, tris, presents);
        if (cm_error || dut.u_sketch_book.err_active_write) $fatal(1, "SketchBook command/page error");
        fid = mon.captured_frame_id;
        wait(mon.captured_frame_id >= fid + 2);
        mon.assert_captured_region_nonblack(0, 0, 799, 599, 100, "robot walk visible");
        mon.dump_captured_frame("sketch_soc_multimesh_walk_final");
        done = 1;
        $display("[sketch_soc_multimesh_walk_tb] PASS frames=%0d reads=%0d clear=%0d tri=%0d present=%0d", dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.cmd_frame_count, scene_reads, clears, tris, presents);
        $finish;
    end
    initial begin
        repeat(TEST_TIMEOUT_CYCLES) @(posedge clk);
        if (!done) $fatal(1, "[sketch_soc_multimesh_walk_tb] timeout");
    end
endmodule
