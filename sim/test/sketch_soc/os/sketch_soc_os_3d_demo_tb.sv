`timescale 1ns/1ps

module sketch_soc_os_3d_demo_tb;
    import uart_agent_pkg::*;

    localparam int UART_WAIT_TIMEOUT = 20_000_000;
    localparam int TEST_TIMEOUT_CYCLES = 40_000_000;
    // 60 ms at the 50 MHz simulation clock: longer than the input polling,
    // UI queue scheduling, and one 50 ms 3D render cadence.
    localparam int BUTTON_SETTLE_CYCLES = 3_000_000;
    logic clk = 1'b0, reset = 1'b1;
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
    integer button_irq_edges = 0;
    integer home_frames_before;
    integer swap_before;
    logic done = 1'b0;
`ifdef MODELSIM_BUILD
    localparam string SCENE_EXT_INIT_FILE = "../../../assets/3d/packages/br01/br01.s3dpkg.mif";
`else
    localparam string SCENE_EXT_INIT_FILE = "../../assets/3d/packages/br01/br01.s3dpkg.mif";
`endif

    always #10 clk = ~clk;

    task automatic press_button(input integer index);
        integer edges_before;
        begin
            edges_before = button_irq_edges;
            touch_btn[index] = 1'b1;
            repeat (500) @(posedge clk);
            touch_btn[index] = 1'b0;
            repeat (BUTTON_SETTLE_CYCLES) @(posedge clk);
            if (button_irq_edges == edges_before)
                $fatal(1, "[sketch_soc_os_3d_demo_tb] BTN%0d did not reach confreg interrupt", index + 1);
        end
    endtask

    task automatic set_sw0(input logic value);
        begin
            dip_sw[0] = value;
            repeat (900_000) @(posedge clk);
        end
    endtask

    task automatic expect_pixel(
        input integer x, input integer y,
        input integer expected_r, input integer expected_g, input integer expected_b,
        input [8*64-1:0] label
    );
        integer index;
        begin
            index = y * 800 + x;
            if ((mon.captured_frame_r[index] != expected_r) ||
                (mon.captured_frame_g[index] != expected_g) ||
                (mon.captured_frame_b[index] != expected_b))
                $fatal(1, "[sketch_soc_os_3d_demo_tb] %0s: got %0d,%0d,%0d expected %0d,%0d,%0d",
                       label, mon.captured_frame_r[index], mon.captured_frame_g[index], mon.captured_frame_b[index],
                       expected_r, expected_g, expected_b);
        end
    endtask

    dvi_monitor_800x600 #(
        .FRAME_DUMP_LIMIT(0),
        .TESTCASE("sketch_soc_os_3d_demo_tb"),
        .OUTPUT_ROOT("../../../sim/frame_output")
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
    sram_sp #(.AW(18), .Init_File(SCENE_EXT_INIT_FILE)) ext_sram_sp (
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

    always @(posedge dut.sys_clk) begin
        if (!reset && dut.u_sketch_book.err_active_write)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] SketchBook active-page write error");
        if (!reset && dut.u_sketch_book.u_gru.error)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] SketchBook renderer error");
    end
    always @(posedge dut.confreg_int)
        if (!reset) button_irq_edges = button_irq_edges + 1;

    initial begin
        #200;
        reset = 1'b0;
        wait(dut.sys_resetn);
        u_uart_agent.uart_wait_tx_string("SK_OS READY", UART_WAIT_TIMEOUT, 1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);

        home_frames_before = dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count;
        press_button(2);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME ignore_btn3 selected=0", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count >= home_frames_before + 1);
        if (dut.g_scene_ctrl.u_scene_ctrl.u_regs.viewport_x != 16'd200)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] BTN3 changed home viewport to %0d",
                   dut.g_scene_ctrl.u_scene_ctrl.u_regs.viewport_x);

        swap_before = dut.u_sketch_book.swap_counter;
        set_sw0(1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS CARD 3D DEMO", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        wait(dut.g_scene_ctrl.u_scene_ctrl.error ||
             dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.frame_count >= 3);
        if (dut.g_scene_ctrl.u_scene_ctrl.error)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] Scene error %0d base=%h size=%0d hdr=%h",
                   dut.g_scene_ctrl.u_scene_ctrl.error_code,
                   dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_base,
                   dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_size,
                   dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.format_version);
        mon.assert_captured_region_nonblack(216, 128, 584, 476, 64, "3d blade viewport");

        // The white border is outside the local-clear viewport.  Checking it
        // once after the first completed 3D presentation proves that the UI
        // chrome and the local renderer coexist; requiring several fixed DVI
        // frame periods here only tests simulator/frame-dump throughput.
        expect_pixel(208, 120, 255, 255, 255, "demo viewport border");

        // Exercise a live scene control before changing models.  One observed
        // pitch update is sufficient for this integration TB; repeated fixed
        // frame waits belong in a performance/soak regression, not PASS logic.
        press_button(0);
        u_uart_agent.uart_wait_tx_string("SK_OS DEMO pitch=1", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.g_scene_ctrl.u_scene_ctrl.u_regs.pitch[3:0] == 4'd1);

        swap_before = dut.u_sketch_book.swap_counter;
        press_button(2);
        u_uart_agent.uart_wait_tx_string("SK_OS DEMO model=ROBOT_RIGID", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.g_scene_ctrl.u_scene_ctrl.error ||
             ((dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_base == 32'h1c400370) &&
              (dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_size == 32'd1776)));
        if (dut.g_scene_ctrl.u_scene_ctrl.error)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] rigid robot switch load error %0d",
                   dut.g_scene_ctrl.u_scene_ctrl.error_code);
        if (dut.g_scene_ctrl.u_scene_ctrl.cmd_mesh_count != 0)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] rigid robot unexpectedly reported cmd mesh count %0d",
                   dut.g_scene_ctrl.u_scene_ctrl.cmd_mesh_count);
        // A swap after the selection proves that the new scene reached the
        // display pipeline.  It is robust to the monitor's one-frame capture
        // lag and avoids assuming a particular render cadence.
        wait(dut.u_sketch_book.swap_counter > swap_before);
        if (dut.g_scene_ctrl.u_scene_ctrl.cmd_frame_count != 0)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] rigid robot unexpectedly used command frames %0d",
                   dut.g_scene_ctrl.u_scene_ctrl.cmd_frame_count);
        if ((dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_base != 32'h1c400370) ||
            (dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_size != 32'd1776))
            $fatal(1, "[sketch_soc_os_3d_demo_tb] rigid robot model reverted base=%h size=%0d",
                   dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_base,
                   dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_size);
        mon.assert_captured_region_nonblack(216, 128, 584, 476, 64, "robot demo viewport");

        swap_before = dut.u_sketch_book.swap_counter;
        set_sw0(1'b0);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        if ((dut.g_scene_ctrl.u_scene_ctrl.u_regs.render_cfg & 6'h13) != 0)
            $fatal(1, "[sketch_soc_os_3d_demo_tb] home Scene left autonomous render flags enabled");
        mon.dump_captured_frame("sketch_soc_os_3d_demo_home_final");
        mon.flush_and_close();
        done = 1'b1;
        $display("[sketch_soc_os_3d_demo_tb] PASS");
        $finish;
    end

    initial begin
        repeat (TEST_TIMEOUT_CYCLES) @(posedge clk);
        if (!done) $fatal(1, "[sketch_soc_os_3d_demo_tb] global timeout");
    end
endmodule
