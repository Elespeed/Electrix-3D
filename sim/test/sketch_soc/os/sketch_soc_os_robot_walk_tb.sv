`timescale 1ns/1ps

// Dedicated application-level regression: second Sketch OS card uses BR01's
// robotss package entry and drives its five articulated meshes through one
// complete command-mode walk sequence.
module sketch_soc_os_robot_walk_tb;
    import uart_agent_pkg::*;
    localparam int UART_WAIT_TIMEOUT = 20_000_000;
    localparam int TEST_TIMEOUT_CYCLES = 45_000_000;
    localparam int BUTTON_SETTLE_CYCLES = 3_000_000;
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
    integer irq_edges = 0, command_frames_before;
    logic done = 1'b0;
`ifdef MODELSIM_BUILD
    localparam string SCENE_EXT_INIT_FILE = "../../../assets/3d/packages/br01/br01.s3dpkg.mif";
`else
    localparam string SCENE_EXT_INIT_FILE = "../../assets/3d/packages/br01/br01.s3dpkg.mif";
`endif

    always #10 clk = ~clk;
    always @(posedge dut.confreg_int) if (!reset) irq_edges = irq_edges + 1;
    always @(posedge dut.sys_clk) begin
        if (!reset && dut.u_sketch_book.err_active_write)
            $fatal(1, "[robot_walk] SketchBook active-page write");
        if (!reset && dut.u_sketch_book.u_gru.error)
            $fatal(1, "[robot_walk] SketchBook renderer error");
    end

    task automatic press_down;
        integer edges_before;
        begin
            edges_before = irq_edges;
            touch_btn[1] = 1'b1; repeat (500) @(posedge clk); touch_btn[1] = 1'b0;
            repeat (BUTTON_SETTLE_CYCLES) @(posedge clk);
            if (irq_edges == edges_before) $fatal(1, "[robot_walk] BTN2 did not interrupt");
        end
    endtask
    task automatic press_up;
        integer edges_before;
        begin
            edges_before = irq_edges;
            touch_btn[0] = 1'b1; repeat (500) @(posedge clk); touch_btn[0] = 1'b0;
            repeat (BUTTON_SETTLE_CYCLES) @(posedge clk);
            if (irq_edges == edges_before) $fatal(1, "[robot_walk] BTN1 did not interrupt");
        end
    endtask
    task automatic set_sw0(input logic value);
        begin dip_sw[0] = value; repeat (900_000) @(posedge clk); end
    endtask

    dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0), .TESTCASE("sketch_soc_os_robot_walk_tb"),
                           .OUTPUT_ROOT("../../../sim/frame_output")) mon (
        .video_clk(video_clk), .resetn(~reset), .video_red({video_red, video_red[2:1]}),
        .video_green({video_green, video_green}), .video_blue({video_blue, video_blue, video_blue[1]}),
        .video_hsync(video_hsync), .video_vsync(video_vsync), .video_de(video_de));

    soc_top_sketch #(.SIMULATION(1'b1)) dut (
        .clk, .reset, .touch_btn, .dip_sw, .video_red, .video_green, .video_blue, .video_hsync, .video_vsync, .video_clk, .video_de,
        .leds, .dpy0, .dpy1, .base_ram_data, .base_ram_addr, .base_ram_be_n, .base_ram_ce_n, .base_ram_oe_n, .base_ram_we_n,
        .ext_ram_data, .ext_ram_addr, .ext_ram_be_n, .ext_ram_ce_n, .ext_ram_oe_n, .ext_ram_we_n, .UART_RX, .UART_TX);
    sram_sp #(.AW(18), .Init_File("../../sdk/axi_ram.mif")) base_sram_sp (
        .ram_addr(base_ram_addr), .ram_be_n(base_ram_be_n), .ram_ce_n(base_ram_ce_n), .ram_oe_n(base_ram_oe_n), .ram_we_n(base_ram_we_n), .ram_data(base_ram_data));
    sram_sp #(.AW(18), .Init_File(SCENE_EXT_INIT_FILE)) ext_sram_sp (
        .ram_addr(ext_ram_addr), .ram_be_n(ext_ram_be_n), .ram_ce_n(ext_ram_ce_n), .ram_oe_n(ext_ram_oe_n), .ram_we_n(ext_ram_we_n), .ram_data(ext_ram_data));
    uart_agent u_uart_agent (.clk(clk), .rst_n(~reset), .uart_rx(UART_RX), .uart_tx(UART_TX),
        .apb_psel(dut.u_axi_uart_controller.uart0.PSEL), .apb_penable(dut.u_axi_uart_controller.uart0.PENABLE),
        .apb_pwrite(dut.u_axi_uart_controller.uart0.PWRITE), .apb_paddr(dut.u_axi_uart_controller.uart0.PADDR[7:0]), .apb_pwdata(dut.u_axi_uart_controller.uart0.PWDATA[7:0]));

    initial begin
        #200; reset = 1'b0; wait(dut.sys_resetn);
        u_uart_agent.uart_wait_tx_string("SK_OS READY", UART_WAIT_TIMEOUT, 1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);
        press_down();
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=1", UART_WAIT_TIMEOUT, 1'b1);
        set_sw0(1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS CARD ROBOT WALK", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.g_scene_ctrl.u_scene_ctrl.error ||
             ((dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_base == 32'h1c400a60) &&
              (dut.g_scene_ctrl.u_scene_ctrl.u_regs.model_size == 32'd1856)));
        if (dut.g_scene_ctrl.u_scene_ctrl.error) $fatal(1, "[robot_walk] load error=%0d", dut.g_scene_ctrl.u_scene_ctrl.error_code);
        wait(dut.g_scene_ctrl.u_scene_ctrl.error || dut.g_scene_ctrl.u_scene_ctrl.cmd_mesh_count == 5);
        if (dut.g_scene_ctrl.u_scene_ctrl.error) $fatal(1, "[robot_walk] mesh-load error=%0d", dut.g_scene_ctrl.u_scene_ctrl.error_code);
        command_frames_before = dut.g_scene_ctrl.u_scene_ctrl.cmd_frame_count;
        wait(dut.g_scene_ctrl.u_scene_ctrl.cmd_frame_count >= command_frames_before + 4);
        press_up();
        u_uart_agent.uart_wait_tx_string("SK_OS ROBOT motion=JUMP_OPEN", UART_WAIT_TIMEOUT, 1'b1);
        command_frames_before = dut.g_scene_ctrl.u_scene_ctrl.cmd_frame_count;
        wait(dut.g_scene_ctrl.u_scene_ctrl.cmd_frame_count >= command_frames_before + 4);
        mon.assert_captured_region_nonblack(216, 128, 584, 476, 64, "robot walk viewport");
        mon.dump_captured_frame("sketch_soc_os_robot_walk"); mon.flush_and_close();
        done = 1'b1; $display("[sketch_soc_os_robot_walk_tb] PASS frames=%0d", dut.g_scene_ctrl.u_scene_ctrl.cmd_frame_count); $finish;
    end
    initial begin repeat (TEST_TIMEOUT_CYCLES) @(posedge clk); if (!done) $fatal(1, "[robot_walk] global timeout"); end
endmodule
