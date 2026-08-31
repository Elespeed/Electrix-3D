`timescale 1ns/1ps
module sketch_scene_soc_tb;
    import uart_agent_pkg::*;
    logic clk=0, reset=1; logic [3:0] touch_btn=0; logic [31:0] dip_sw=0;
    tri UART_RX, UART_TX; tri [31:0] base_ram_data, ext_ram_data;
    wire [2:0] video_red,video_green; wire [1:0] video_blue; wire video_hsync,video_vsync,video_clk,video_de;
    wire [15:0] leds; wire [7:0] dpy0,dpy1; wire [19:0] base_ram_addr,ext_ram_addr; wire [3:0] base_ram_be_n,ext_ram_be_n;
    wire base_ram_ce_n,base_ram_oe_n,base_ram_we_n,ext_ram_ce_n,ext_ram_oe_n,ext_ram_we_n;
    integer scene_reads=0, scene_cmds=0, reads_after_load=0; logic done=0, arb_checked=0;
    always #10 clk=~clk;
    always @(posedge dut.sys_clk) begin
        if (dut.dma_m_arvalid && dut.dma_m_arready) scene_reads++;
        if (dut.scene_mmio_valid && dut.scene_mmio_ready && dut.scene_mmio_we) scene_cmds++;
    end
    // The direct SoC top enables Scene by default; keep this TB on the same
    // configuration used by both the 2D and 3D software images.
    soc_top_sketch #(.SIMULATION(1'b1)) dut (.*);
    // Capture the board-facing output, not merely the Scene-to-SketchBook
    // command stream.  This makes the joint test prove the rendered model
    // reaches a complete DVI frame.
    dvi_monitor_800x600 #(
        .FRAME_DUMP_LIMIT(0),
        .TESTCASE("sketch_scene_soc_tb"),
        .OUTPUT_ROOT("../../sim/frame_output")
    ) mon (
        .video_clk(video_clk), .resetn(~reset),
        .video_red({video_red, video_red[2:1]}),
        .video_green({video_green, video_green}),
        .video_blue({video_blue, video_blue, video_blue[1]}),
        .video_hsync(video_hsync), .video_vsync(video_vsync), .video_de(video_de)
    );
    sram_sp #(.AW(20),.Init_File("../../sdk/axi_ram.mif")) base_sram_sp (.ram_addr(base_ram_addr),.ram_be_n(base_ram_be_n),.ram_ce_n(base_ram_ce_n),.ram_oe_n(base_ram_oe_n),.ram_we_n(base_ram_we_n),.ram_data(base_ram_data));
`ifdef MODELSIM_BUILD
    localparam string SCENE_EXT_INIT_FILE = "../../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`else
    localparam string SCENE_EXT_INIT_FILE = "../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`endif
    sram_sp #(.AW(20),.Init_File(SCENE_EXT_INIT_FILE)) ext_sram_sp (.ram_addr(ext_ram_addr),.ram_be_n(ext_ram_be_n),.ram_ce_n(ext_ram_ce_n),.ram_oe_n(ext_ram_oe_n),.ram_we_n(ext_ram_we_n),.ram_data(ext_ram_data));
    uart_agent uart (.clk,.rst_n(~reset),.uart_rx(UART_RX),.uart_tx(UART_TX),.apb_psel(dut.u_axi_uart_controller.uart0.PSEL),.apb_penable(dut.u_axi_uart_controller.uart0.PENABLE),.apb_pwrite(dut.u_axi_uart_controller.uart0.PWRITE),.apb_paddr(dut.u_axi_uart_controller.uart0.PADDR[7:0]),.apb_pwdata(dut.u_axi_uart_controller.uart0.PWDATA[7:0]));
    // Inject a CPU-side SketchBook packet while Scene owns the port.  The
    // arbiter must backpressure it and must not let its fields contaminate a
    // Scene command packet.
    initial begin
        wait(dut.sys_resetn);
        wait(dut.scene_busy);
        force dut.cpu_sketch_mmio_valid = 1'b1;
        force dut.cpu_sketch_mmio_we    = 1'b1;
        force dut.cpu_sketch_mmio_addr  = 32'h0000_0008;
        force dut.cpu_sketch_mmio_wdata = 32'hdeadc0de;
        repeat (8) begin
            @(posedge dut.sys_clk);
            if (dut.cpu_sketch_mmio_ready)
                $fatal(1, "CPU SketchBook request was accepted while Scene busy");
            if (dut.sketch_mmio_valid !== dut.scene_mmio_valid ||
                dut.sketch_mmio_addr  !== dut.scene_mmio_addr)
                $fatal(1, "CPU request contaminated Scene SketchBook packet");
        end
        release dut.cpu_sketch_mmio_valid;
        release dut.cpu_sketch_mmio_we;
        release dut.cpu_sketch_mmio_addr;
        release dut.cpu_sketch_mmio_wdata;
        arb_checked = 1'b1;
    end
    initial begin
        #200 reset=0; wait(dut.sys_resetn);
        uart.uart_wait_tx_string("SCENE SK3D START",2_000_000,1'b1);
        wait (dut.g_scene_ctrl.u_scene_ctrl.model_valid);
        if (dut.g_scene_ctrl.u_scene_ctrl.error)
            $fatal(1,"Scene load failed: code=%0d reads=%0d", dut.g_scene_ctrl.u_scene_ctrl.error_code, scene_reads);
        if (dut.g_scene_ctrl.u_scene_ctrl.u_regs.pitch != 0)
            $fatal(1,"Blade demo must use yaw-only animation: pitch=%0d", dut.g_scene_ctrl.u_scene_ctrl.u_regs.pitch);
        reads_after_load = scene_reads;
        uart.uart_wait_tx_string("SCENE SK3D PASS",1_000_000,1'b1);
        wait (dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count >= 3);
        if (dut.g_scene_ctrl.u_scene_ctrl.error)
            $fatal(1,"Scene animation failed: code=%0d state=%0d", dut.g_scene_ctrl.u_scene_ctrl.error_code, dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.state);
        if(scene_reads==0 || scene_cmds==0) $fatal(1,"Scene did not fetch model or submit commands");
        if (scene_reads != reads_after_load)
            $fatal(1,"Scene reread ExtRAM after model cache was valid: load_reads=%0d total_reads=%0d", reads_after_load, scene_reads);
        if (scene_cmds < 15)
            $fatal(1,"Scene did not submit enough commands for multiple animation frames: cmds=%0d", scene_cmds);
        if(dut.u_sketch_book.err_active_write) $fatal(1,"SketchBook write while active");
        if(!arb_checked) $fatal(1,"CPU/Scene SketchBook arbitration was not checked");
        if (mon.captured_frame_id == 0)
            $fatal(1, "Scene commands did not reach a captured DVI frame");
        mon.assert_captured_region_nonblack(0, 0, 800, 600, 64, "scene_model_visible");
        done=1; $display("[sketch_scene_soc_tb] PASS frames=%0d reads=%0d cmds=%0d",dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count,scene_reads,scene_cmds); $finish;
    end
    initial begin repeat(8_000_000) @(posedge clk); if(!done) begin
        $display("scene timeout busy=%b error=%b code=%0d ar=%b/%b addr=%h state=%0d", dut.g_scene_ctrl.u_scene_ctrl.busy, dut.g_scene_ctrl.u_scene_ctrl.error, dut.g_scene_ctrl.u_scene_ctrl.error_code, dut.dma_m_arvalid, dut.dma_m_arready, dut.dma_m_araddr, dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.state);
        $fatal(1,"scene SoC timeout");
    end end
endmodule
