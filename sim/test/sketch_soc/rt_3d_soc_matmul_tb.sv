`timescale 1ns/1ps
// End-to-end paper-path smoke test.  The CPU owns every operation after the
// matrix result is returned; the Scene Controller is absent from this top.
module rt_3d_soc_matmul_tb #(
`ifdef RT3D_MODEL_S0
    parameter string EXT_INIT_FILE = "../../experiments/3d_scene/assets/S0/model.s3d.mif"
`else
    parameter string EXT_INIT_FILE = "../../assets/3d/generated/blade/v4/blade_shade.s3d.mif"
`endif
);
    import uart_agent_pkg::*;
    localparam int UART_WAIT_TIMEOUT = 2_000_000;
    logic clk = 1'b0, reset = 1'b1, done = 1'b0;
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
    integer matmul_writes = 0, matmul_reads = 0, matmul_nonzero_r = 0, matmul_nonzero_c_r = 0;
    integer clear_cmds = 0, triangle_cmds = 0, present_cmds = 0;
    integer captured_frame_before = 0;
    logic [31:0] matmul_araddr = '0;

    always #10 clk = ~clk;
    soc_top_sketch_matmul #(.SIMULATION(1'b1)) dut (
        .clk, .reset, .touch_btn, .dip_sw,
        .video_red, .video_green, .video_blue, .video_hsync, .video_vsync,
        .video_clk, .video_de, .leds, .dpy0, .dpy1,
        .base_ram_data, .base_ram_addr, .base_ram_be_n, .base_ram_ce_n,
        .base_ram_oe_n, .base_ram_we_n, .ext_ram_data, .ext_ram_addr,
        .ext_ram_be_n, .ext_ram_ce_n, .ext_ram_oe_n, .ext_ram_we_n, .UART_RX, .UART_TX);
    dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0), .TESTCASE("rt_3d_soc_matmul_tb"),
                           .OUTPUT_ROOT("../../sim/frame_output")) mon (
        .video_clk, .resetn(~reset), .video_red({video_red, video_red[2:1]}),
        .video_green({video_green, video_green}), .video_blue({video_blue, video_blue, video_blue[1]}),
        .video_hsync, .video_vsync, .video_de);
    sram_sp #(.AW(18), .Init_File("../../sdk/axi_ram.mif")) base_sram_sp (
        .ram_addr(base_ram_addr), .ram_be_n(base_ram_be_n), .ram_ce_n(base_ram_ce_n),
        .ram_oe_n(base_ram_oe_n), .ram_we_n(base_ram_we_n), .ram_data(base_ram_data));
    sram_sp #(.AW(18), .Init_File(EXT_INIT_FILE)) ext_sram_sp (
        .ram_addr(ext_ram_addr), .ram_be_n(ext_ram_be_n), .ram_ce_n(ext_ram_ce_n),
        .ram_oe_n(ext_ram_oe_n), .ram_we_n(ext_ram_we_n), .ram_data(ext_ram_data));
    uart_agent uart (.clk, .rst_n(~reset), .uart_rx(UART_RX), .uart_tx(UART_TX),
        .apb_psel(dut.u_soc.u_soc_base.u_axi_uart_controller.uart0.PSEL),
        .apb_penable(dut.u_soc.u_soc_base.u_axi_uart_controller.uart0.PENABLE),
        .apb_pwrite(dut.u_soc.u_soc_base.u_axi_uart_controller.uart0.PWRITE),
        .apb_paddr(dut.u_soc.u_soc_base.u_axi_uart_controller.uart0.PADDR[7:0]),
        .apb_pwdata(dut.u_soc.u_soc_base.u_axi_uart_controller.uart0.PWDATA[7:0]));

    always @(posedge dut.u_soc.u_soc_base.sys_clk) begin
        if (!reset && dut.u_soc.u_soc_base.axiOut_7_awvalid && dut.u_soc.u_soc_base.axiOut_7_awready) matmul_writes++;
        if (!reset && dut.u_soc.u_soc_base.axiOut_7_arvalid && dut.u_soc.u_soc_base.axiOut_7_arready) begin
            matmul_reads++;
            matmul_araddr <= dut.u_soc.u_soc_base.axiOut_7_araddr;
        end
        if (!reset && dut.u_soc.u_soc_base.axiOut_7_rvalid && dut.u_soc.u_soc_base.axiOut_7_rready && dut.u_soc.u_soc_base.axiOut_7_rdata != 0)
            matmul_nonzero_r++;
        if (!reset && dut.u_soc.u_soc_base.axiOut_7_rvalid && dut.u_soc.u_soc_base.axiOut_7_rready &&
            matmul_araddr[7:0] >= 8'h90 && matmul_araddr[7:0] < 8'hc0 && dut.u_soc.u_soc_base.axiOut_7_rdata != 0)
            matmul_nonzero_c_r++;
        if (!reset && dut.u_soc.u_soc_base.sketch_mmio_valid && dut.u_soc.u_soc_base.sketch_mmio_ready && dut.u_soc.u_soc_base.sketch_mmio_we && dut.u_soc.u_soc_base.sketch_mmio_addr[11:0] == 12'h018) begin
            case (dut.u_soc.u_soc_base.u_sketch_book.cmd0[4:0])
                5'd0: clear_cmds++;
                5'd5: triangle_cmds++;
                5'd6: present_cmds++;
                default: ;
            endcase
        end
        if (!reset && dut.u_soc.u_soc_base.u_sketch_book.err_active_write) $fatal(1, "active-page SketchBook write");
    end

    initial begin
        #200 reset = 1'b0;
        wait(dut.u_soc.u_soc_base.sys_resetn);
        uart.uart_wait_tx_string("RT3D START backend=CPU_MATMUL", UART_WAIT_TIMEOUT, 1'b1);
        // Firmware emits compact records so that rt_kprintf cannot truncate a
        // long JSON document; the host parser expands this line to JSONL.
        uart.uart_wait_tx_string("RT3D FRAME mode=CPU_MATMUL", UART_WAIT_TIMEOUT, 1'b1);
        if (matmul_writes == 0 || matmul_reads == 0) $fatal(1, "missing Matmul MMIO writes=%0d reads=%0d", matmul_writes, matmul_reads);
        if (dut.u_soc.u_soc_base.u_matmul_axi_slave.error || !dut.u_soc.u_soc_base.u_matmul_axi_slave.done)
            $fatal(1, "Matmul terminal state done=%0b error=%0b", dut.u_soc.u_soc_base.u_matmul_axi_slave.done, dut.u_soc.u_soc_base.u_matmul_axi_slave.error);
        if ((dut.u_soc.u_soc_base.u_matmul_axi_slave.c_regs[0] == 0) || matmul_nonzero_c_r == 0)
            $fatal(1, "Matmul C read path did not return computed data C0=%08x c_reads=%0d", dut.u_soc.u_soc_base.u_matmul_axi_slave.c_regs[0], matmul_nonzero_c_r);
        if (clear_cmds == 0 || triangle_cmds == 0 || present_cmds == 0)
            $fatal(1, "missing SketchBook commands clear=%0d tri=%0d present=%0d", clear_cmds, triangle_cmds, present_cmds);
        captured_frame_before = mon.captured_frame_id;
        wait(mon.captured_frame_id >= captured_frame_before + 2);
        mon.assert_captured_region_nonblack(0, 0, 799, 599, 100, "cpu_matmul_visible");
        mon.flush_and_close();
        done = 1'b1;
        $display("[rt_3d_soc_matmul_tb] PASS matmul_wr=%0d matmul_rd=%0d nonzero_r=%0d nonzero_c_r=%0d clear=%0d tri=%0d present=%0d", matmul_writes, matmul_reads, matmul_nonzero_r, matmul_nonzero_c_r, clear_cmds, triangle_cmds, present_cmds);
        $finish;
    end
    initial begin
        repeat (8_000_000) @(posedge clk);
        if (!done) $fatal(1, "CPU_MATMUL SoC timeout pc=%08x", dut.u_soc.u_soc_base.debug_wb_pc);
    end
endmodule
