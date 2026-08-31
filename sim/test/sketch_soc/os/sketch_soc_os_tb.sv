`timescale 1ns/1ps

module sketch_soc_os_tb;
    import uart_agent_pkg::*;

    localparam int UART_WAIT_TIMEOUT = 20_000_000;
    localparam int TEST_TIMEOUT_CYCLES = 40_000_000;
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
    integer clear_cmd_count = 0;
    integer button_irq_edges = 0;
    integer swap_before;
    integer frame_before;
    integer diag_sys_cycles = 0;
    logic done = 1'b0;
`ifdef MODELSIM_BUILD
    localparam string SCENE_EXT_INIT_FILE = "../../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`else
    localparam string SCENE_EXT_INIT_FILE = "../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`endif

    always #10 clk = ~clk;

    task automatic press_button(input integer index);
        integer edges_before;
        begin
            edges_before = button_irq_edges;
            $display("[INPUT_DIAG] BTN%0d assert pc=%08x int_state=%08x swap=%0d", index + 1,
                     dut.debug_wb_pc, dut.u_confreg.confreg_int_state, dut.u_sketch_book.swap_counter);
            touch_btn[index] = 1'b1;
            repeat (500) @(posedge clk);
            touch_btn[index] = 1'b0;
            $display("[INPUT_DIAG] BTN%0d release pc=%08x int_state=%08x irq_edges=%0d", index + 1,
                     dut.debug_wb_pc, dut.u_confreg.confreg_int_state, button_irq_edges);
            repeat (100_000) @(posedge clk);
            $display("[INPUT_DIAG] BTN%0d settled pc=%08x int_state=%08x irq_edges=%0d swap=%0d", index + 1,
                     dut.debug_wb_pc, dut.u_confreg.confreg_int_state, button_irq_edges,
                     dut.u_sketch_book.swap_counter);
            if (button_irq_edges == edges_before)
                $fatal(1, "[sketch_soc_os_tb] BTN%0d did not reach confreg interrupt", index + 1);
        end
    endtask

    task automatic set_sw0(input logic value);
        begin
            dip_sw[0] = value;
            // Three stable input-poll samples are required by the software
            // debounce path, plus one UI-thread scheduling interval.
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
                (mon.captured_frame_b[index] != expected_b)) begin
                $fatal(1, "[sketch_soc_os_tb] %0s at (%0d,%0d): got %0d,%0d,%0d expected %0d,%0d,%0d",
                       label, x, y, mon.captured_frame_r[index], mon.captured_frame_g[index],
                       mon.captured_frame_b[index], expected_r, expected_g, expected_b);
            end
        end
    endtask

    // The framebuffer swap is vblank-synchronized, and the monitor's
    // captured-frame copy lags the live display by one boundary.  Poll it
    // instead of assuming that a software PRESENT is visible immediately.
    task automatic wait_expect_pixel(
        input integer x, input integer y,
        input integer expected_r, input integer expected_g, input integer expected_b,
        input [8*64-1:0] label,
        input integer max_frames
    );
        integer index;
        integer fid;
        integer waited;
        begin
            index = y * 800 + x;
            fid = mon.captured_frame_id;
            for (waited = 0; waited < max_frames; waited = waited + 1) begin
                wait(mon.captured_frame_id > fid);
                fid = mon.captured_frame_id;
                if ((mon.captured_frame_r[index] == expected_r) &&
                    (mon.captured_frame_g[index] == expected_g) &&
                    (mon.captured_frame_b[index] == expected_b)) begin
                    return;
                end
            end
            $fatal(1, "[sketch_soc_os_tb] %0s at (%0d,%0d): never matched %0d,%0d,%0d in %0d frames",
                   label, x, y, expected_r, expected_g, expected_b, max_frames);
        end
    endtask

    dvi_monitor_800x600 #(
        .FRAME_DUMP_LIMIT(0),
        .TESTCASE("sketch_soc_os_tb"),
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

    // The Scene-owned model cache reads ExtRAM only.  Keep the CPU image in
    // BaseRAM and seed the independent ExtRAM device with the blade asset.
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

    // CMD0=CLEAR is observable on the CPU AXI write channel.  Navigation is
    // required to update only cursor outlines, so this counter must not move.
    always @(posedge dut.sys_clk) begin
        if (!reset) begin
            diag_sys_cycles = diag_sys_cycles + 1;
            if ((diag_sys_cycles % 100_000) == 0)
                $display("[HEARTBEAT] sys_cycles=%0d pc=%08x int_state=%08x swap=%0d pending=%0b frame=%0d scene{busy=%0b valid=%0b state=%0d count=%0d yaw=%0d mmio_v=%0b mmio_r=%0b} cpu{v=%0b we=%0b a=%03x r=%0b data=%08x axi{aw=%0b/%0b w=%0b/%0b b=%0b/%0b}} sk{v=%0b r=%0b q=%0d full=%0b closed=%0b gru_busy=%0b render=%0b swap_p=%0b}",
                         diag_sys_cycles, dut.debug_wb_pc, dut.u_confreg.confreg_int_state,
                         dut.u_sketch_book.swap_counter, dut.u_sketch_book.swap_pending,
                         dut.u_sketch_book.frame_counter,
                         dut.g_scene_ctrl.u_scene_ctrl.busy,
                         dut.g_scene_ctrl.u_scene_ctrl.model_valid,
                         dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.state,
                         dut.g_scene_ctrl.u_scene_ctrl.frame_count,
                         dut.g_scene_ctrl.u_scene_ctrl.u_pipeline.u_engine.yaw,
                         dut.g_scene_ctrl.u_scene_ctrl.mmio_valid,
                         dut.g_scene_ctrl.u_scene_ctrl.mmio_ready,
                         dut.cpu_sketch_mmio_valid,
                         dut.cpu_sketch_mmio_we,
                         dut.cpu_sketch_mmio_addr[11:0],
                         dut.cpu_sketch_mmio_ready,
                         dut.cpu_sketch_mmio_rdata,
                         dut.dvi_awvalid,
                         dut.dvi_awready,
                         dut.dvi_wvalid,
                         dut.dvi_wready,
                         dut.dvi_bvalid,
                         dut.dvi_bready,
                         dut.sketch_mmio_valid,
                         dut.sketch_mmio_ready,
                         dut.u_sketch_book.cmd_level,
                         dut.u_sketch_book.cmd_full,
                         dut.u_sketch_book.frame_closed,
                         dut.u_sketch_book.gru_busy,
                         dut.u_sketch_book.render_allowed,
                         dut.u_sketch_book.swap_pending);
        end
        if (dut.dvi_awvalid && dut.dvi_awready && dut.dvi_wvalid && dut.dvi_wready &&
            ((dut.dvi_awaddr & 32'hfff0_0fff) == 32'h1f10_0008) &&
            (dut.dvi_wdata[4:0] == 5'd0)) begin
            clear_cmd_count = clear_cmd_count + 1;
        end
        if (!reset && dut.u_sketch_book.err_active_write)
            $fatal(1, "[sketch_soc_os_tb] SketchBook active-page write error");
        if (!reset && dut.u_sketch_book.u_gru.error)
            $fatal(1, "[sketch_soc_os_tb] SketchBook renderer error");
    end

    always @(posedge dut.confreg_int) begin
        if (!reset) begin
            button_irq_edges = button_irq_edges + 1;
            if ((dut.u_confreg.confreg_int_state & 32'h1f) != 0)
                $display("[INPUT_DIAG] confreg button irq pc=%08x state=%08x edges=%0d", dut.debug_wb_pc,
                         dut.u_confreg.confreg_int_state, button_irq_edges);
        end
    end

    initial begin
        #200;
        reset = 1'b0;
        wait(dut.sys_resetn);
        u_uart_agent.uart_wait_tx_string("SK_OS READY", UART_WAIT_TIMEOUT, 1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);
        wait(mon.captured_frame_id > 0);
        wait_expect_pixel(52, 136, 255, 255, 0, "home card 0 yellow cursor", 16);

        // The UI owns PRESENT in home mode: Scene must have completed a
        // single frame and returned idle with its autonomous modes disabled.
        wait(dut.g_scene_ctrl.u_scene_ctrl.frame_count >= 2);
        if (dut.g_scene_ctrl.u_scene_ctrl.busy)
            $fatal(1, "[sketch_soc_os_tb] home Scene did not return idle after one frame");
        if ((dut.g_scene_ctrl.u_scene_ctrl.u_regs.render_cfg & 6'h13) != 0)
            $fatal(1, "[sketch_soc_os_tb] home Scene left autonomous render flags enabled");

        // BTN3/BTN4 are reserved directions in this release.
        press_button(2);
        press_button(3);
        expect_pixel(52, 136, 255, 255, 0, "unused left/right buttons changed home cursor");

        clear_cmd_count = 0;
        swap_before = dut.u_sketch_book.swap_counter;
        press_button(1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=1", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        // The move needs the Scene's in-flight swap to drain, then its own
        // PRESENT to retire at the next vblank.  Poll for the new cursor, then
        // for the old one being restored to the background color.
        wait_expect_pixel(52, 252, 255, 255, 0, "home card 1 yellow cursor", 16);
        wait_expect_pixel(52, 136, 0, 0, 173, "old cursor restored to background", 2);
        if (clear_cmd_count != 0)
            $fatal(1, "[sketch_soc_os_tb] home cursor move issued %0d CLEAR commands", clear_cmd_count);

        swap_before = dut.u_sketch_book.swap_counter;
        press_button(0);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        wait_expect_pixel(52, 136, 255, 255, 0, "home cursor returned to card 0", 16);

        swap_before = dut.u_sketch_book.swap_counter;
        frame_before = mon.captured_frame_id;
        set_sw0(1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS CARD ANIMATION", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        frame_before = mon.captured_frame_id;
        wait(mon.captured_frame_id >= (frame_before + 2));
        mon.assert_captured_region_nonblack(80, 250, 700, 380, 100, "animation card content");

        u_uart_agent.uart_send_line("skstatus");
        u_uart_agent.uart_wait_tx_string("SK_OS STATUS scene=1 selected=0", UART_WAIT_TIMEOUT, 1'b1);

        swap_before = dut.u_sketch_book.swap_counter;
        set_sw0(1'b0);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        wait_expect_pixel(52, 136, 255, 255, 0, "returned home cursor", 16);

        // Exercise the remaining two cards as real UI transitions, rather
        // than accepting their presence in the static home-page drawing.
        press_button(1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=1", UART_WAIT_TIMEOUT, 1'b1);
        swap_before = dut.u_sketch_book.swap_counter;
        set_sw0(1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS CARD SHAPES", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        u_uart_agent.uart_send_line("skstatus");
        u_uart_agent.uart_wait_tx_string("SK_OS STATUS scene=2 selected=1", UART_WAIT_TIMEOUT, 1'b1);
        // The red triangle is drawn in framebuffer space as
        // (64,190),(128,80),(192,190) and scaled 2x to the DVI output, so
        // screen (256,340) is the framebuffer interior point (128,170).
        wait_expect_pixel(256, 340, 255, 0, 0, "shapes card red triangle", 16);

        swap_before = dut.u_sketch_book.swap_counter;
        set_sw0(1'b0);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=1", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);

        press_button(1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=2", UART_WAIT_TIMEOUT, 1'b1);
        swap_before = dut.u_sketch_book.swap_counter;
        set_sw0(1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS CARD SYSTEM", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);
        u_uart_agent.uart_send_line("skstatus");
        u_uart_agent.uart_wait_tx_string("SK_OS STATUS scene=3 selected=2", UART_WAIT_TIMEOUT, 1'b1);

        swap_before = dut.u_sketch_book.swap_counter;
        set_sw0(1'b0);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=2", UART_WAIT_TIMEOUT, 1'b1);
        wait(dut.u_sketch_book.swap_counter > swap_before);

        // Returning from System is the relevant end-to-end home transition.
        // Do not require two unrelated navigation events just to force the
        // selected card back to zero; prove the actual UI state through the
        // same shell interface used by the fast UART smoke test.
        u_uart_agent.uart_send_line("skstatus");
        u_uart_agent.uart_wait_tx_string("SK_OS STATUS scene=0 selected=2", UART_WAIT_TIMEOUT, 1'b1);
        mon.dump_captured_frame("sketch_soc_os_home_final");
        mon.flush_and_close();
        done = 1'b1;
        $display("[sketch_soc_os_tb] PASS");
        $finish;
    end

    initial begin
        repeat (TEST_TIMEOUT_CYCLES) @(posedge clk);
        if (!done)
            $fatal(1, "[sketch_soc_os_tb] global timeout");
    end
endmodule
