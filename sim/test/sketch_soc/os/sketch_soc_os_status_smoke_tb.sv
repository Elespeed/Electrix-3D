`timescale 1ns/1ps

// Deliberately omits the DVI framebuffer monitor: this test checks only the
// software-visible state machine and UART shell response, so it stays fast.
module sketch_soc_os_status_smoke_tb;
    import uart_agent_pkg::*;

    localparam int UART_WAIT_TIMEOUT = 20_000_000;
    localparam int TEST_TIMEOUT_CYCLES = 20_000_000;
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
    integer button_irq_edges = 0;
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
            touch_btn[index] = 1'b1;
            repeat (500) @(posedge clk);
            touch_btn[index] = 1'b0;
            repeat (100_000) @(posedge clk);
            if (button_irq_edges == edges_before)
                $fatal(1, "[sketch_soc_os_status_smoke_tb] BTN%0d did not reach confreg interrupt", index + 1);
        end
    endtask

    task automatic set_sw0(input logic value);
        begin
            dip_sw[0] = value;
            repeat (900_000) @(posedge clk);
        end
    endtask

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

    always @(posedge dut.confreg_int) begin
        if (!reset) button_irq_edges = button_irq_edges + 1;
    end

    always @(posedge dut.sys_clk) begin
        if (!reset && dut.u_sketch_book.err_active_write)
            $fatal(1, "[sketch_soc_os_status_smoke_tb] SketchBook active-page write error");
        if (!reset && dut.u_sketch_book.u_gru.error)
            $fatal(1, "[sketch_soc_os_status_smoke_tb] SketchBook renderer error");
    end

    initial begin
        #200;
        reset = 1'b0;
        wait(dut.sys_resetn);
        u_uart_agent.uart_wait_tx_string("SK_OS READY", UART_WAIT_TIMEOUT, 1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=0", UART_WAIT_TIMEOUT, 1'b1);

        press_button(1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=1", UART_WAIT_TIMEOUT, 1'b1);
        press_button(1);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=2", UART_WAIT_TIMEOUT, 1'b1);
        set_sw0(1'b1);
        u_uart_agent.uart_wait_tx_string("SK_OS CARD SYSTEM", UART_WAIT_TIMEOUT, 1'b1);
        u_uart_agent.uart_send_line("skstatus");
        u_uart_agent.uart_wait_tx_string("SK_OS STATUS scene=3 selected=2", UART_WAIT_TIMEOUT, 1'b1);

        set_sw0(1'b0);
        u_uart_agent.uart_wait_tx_string("SK_OS HOME selected=2", UART_WAIT_TIMEOUT, 1'b1);
        u_uart_agent.uart_send_line("skstatus");
        u_uart_agent.uart_wait_tx_string("SK_OS STATUS scene=0 selected=2", UART_WAIT_TIMEOUT, 1'b1);
        if (dut.g_scene_ctrl.u_scene_ctrl.busy)
            $fatal(1, "[sketch_soc_os_status_smoke_tb] home Scene remained busy");
        if ((dut.g_scene_ctrl.u_scene_ctrl.u_regs.render_cfg & 6'h13) != 0)
            $fatal(1, "[sketch_soc_os_status_smoke_tb] home Scene autonomous flags are enabled");

        done = 1'b1;
        $display("[sketch_soc_os_status_smoke_tb] PASS");
        $finish;
    end

    initial begin
        repeat (TEST_TIMEOUT_CYCLES) @(posedge clk);
        if (!done)
            $fatal(1, "[sketch_soc_os_status_smoke_tb] global timeout");
    end
endmodule
