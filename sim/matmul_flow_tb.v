`timescale 1ns / 1ps
`include "config.h"

`define UART_PSEL   u_soc_top.u_axi_uart_controller.uart0.PSEL
`define UART_PENABLE u_soc_top.u_axi_uart_controller.uart0.PENABLE
`define UART_PWRITE u_soc_top.u_axi_uart_controller.uart0.PWRITE
`define UART_WADDR  u_soc_top.u_axi_uart_controller.uart0.PADDR[7:0]
`define UART_WDATA  u_soc_top.u_axi_uart_controller.uart0.PWDATA[7:0]

module matmul_flow_tb;

localparam EXTRAM_WORDS = 1048576;
localparam DONE_LEN = 11;
localparam PC_CALL_MAIN        = 32'h1c0001bc;
localparam PC_MAIN_ENTRY       = 32'h1c000240;
localparam PC_MATMUL_INIT      = 32'h1c000274;
localparam PC_MATMUL_LOAD_LOOP = 32'h1c0002f0;
localparam PC_MATMUL_WAIT      = 32'h1c00045c;
localparam PC_MATMUL_STORE     = 32'h1c000480;
localparam PC_DONE_PRINTF      = 32'h1c0004a8;

reg reset;
reg clk;
reg [3:0] touch_btn;
reg [31:0] dip_sw;

wire UART_RX;
wire UART_TX;
wire [4:0] video_red;
wire [5:0] video_green;
wire [4:0] video_blue;
wire video_hsync;
wire video_vsync;
wire video_clk;
wire video_de;
wire [15:0] leds;
wire [7:0] dpy0;
wire [7:0] dpy1;
wire [19:0] base_ram_addr;
wire [3:0] base_ram_be_n;
wire base_ram_ce_n;
wire base_ram_oe_n;
wire base_ram_we_n;
wire [19:0] ext_ram_addr;
wire [3:0] ext_ram_be_n;
wire ext_ram_ce_n;
wire ext_ram_oe_n;
wire ext_ram_we_n;
wire [31:0] base_ram_data;
wire [31:0] ext_ram_data;

reg [31:0] expected_mem [0:EXTRAM_WORDS-1];
reg [8*256-1:0] input_hex;
reg [8*256-1:0] expected_hex;
reg [31:0] group_num;
reg [31:0] timeout_cycles;
reg [31:0] progress_cycles;
reg [31:0] uart_shift [0:DONE_LEN-1];
reg done_seen;
integer i;
integer err_count;
integer check_words;
integer timeout_count;
integer uart_count;
integer matmul_write_rsp_count;
integer matmul_read_rsp_count;
integer ram_read_rsp_count;
integer cpu_read_req_count;
integer cpu_write_rsp_count;
reg [31:0] last_debug_pc;
reg [31:0] same_pc_cycles;
reg main_seen;
reg matmul_access_seen;
reg done_printf_seen;
reg [8*32-1:0] phase_text;

initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;
end

initial begin
    input_hex = "../../../../../../tools/matmul_testdata/extram_input_4mb.hex";
    expected_hex = "../../../../../../tools/matmul_testdata/extram_expected_4mb.hex";
    group_num = 32'd10;
    timeout_cycles = 32'd5000000;
    progress_cycles = 32'd500000;

    if (!$value$plusargs("INPUT_HEX=%s", input_hex)) begin
    end
    if (!$value$plusargs("EXPECTED_HEX=%s", expected_hex)) begin
    end
    if (!$value$plusargs("GROUPS=%d", group_num)) begin
    end
    if (!$value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles)) begin
    end
    if (!$value$plusargs("PROGRESS_CYCLES=%d", progress_cycles)) begin
    end

    reset = 1'b1;
    touch_btn = 4'h0;
    dip_sw = 32'h0000_abcd;
    done_seen = 1'b0;
    timeout_count = 0;
    uart_count = 0;
    matmul_write_rsp_count = 0;
    matmul_read_rsp_count = 0;
    ram_read_rsp_count = 0;
    cpu_read_req_count = 0;
    cpu_write_rsp_count = 0;
    last_debug_pc = 32'b0;
    same_pc_cycles = 32'b0;
    main_seen = 1'b0;
    matmul_access_seen = 1'b0;
    done_printf_seen = 1'b0;

    for (i = 0; i < DONE_LEN; i = i + 1) begin
        uart_shift[i] = 32'b0;
    end

    $display("[MATMUL_TB] load ExtRAM input:    %0s", input_hex);
    $display("[MATMUL_TB] load expected image:  %0s", expected_hex);
    $display("[MATMUL_TB] groups: %0d", group_num);
    $readmemh(input_hex, ext_sram_sp.BRAM);
    $readmemh(expected_hex, expected_mem);

    #2000;
    $display("[MATMUL_TB] release reset and start timing");
    reset = 1'b0;
end

always @(posedge clk) begin
    if (!reset && !done_seen) begin
        timeout_count <= timeout_count + 1;

        if (u_soc_top.debug_wb_pc == last_debug_pc) begin
            same_pc_cycles <= same_pc_cycles + 1;
        end else begin
            last_debug_pc <= u_soc_top.debug_wb_pc;
            same_pc_cycles <= 32'b0;
        end

        if (u_soc_top.cpu_arvalid && u_soc_top.cpu_arready) begin
            cpu_read_req_count <= cpu_read_req_count + 1;
        end
        if (u_soc_top.cpu_bvalid && u_soc_top.cpu_bready) begin
            cpu_write_rsp_count <= cpu_write_rsp_count + 1;
        end
        if (u_soc_top.ram_rvalid && u_soc_top.ram_rready) begin
            ram_read_rsp_count <= ram_read_rsp_count + 1;
        end
        if (u_soc_top.axiOut_7_bvalid && u_soc_top.axiOut_7_bready) begin
            matmul_write_rsp_count <= matmul_write_rsp_count + 1;
            matmul_access_seen <= 1'b1;
        end
        if (u_soc_top.axiOut_7_rvalid && u_soc_top.axiOut_7_rready) begin
            matmul_read_rsp_count <= matmul_read_rsp_count + 1;
            matmul_access_seen <= 1'b1;
        end

        if (!main_seen && (u_soc_top.debug_wb_pc >= PC_MAIN_ENTRY)) begin
            main_seen <= 1'b1;
            $display("[MATMUL_TB] stage: entered main at cycles=%0d pc=%08x inst=%08x",
                     timeout_count, u_soc_top.debug_wb_pc, u_soc_top.debug_wb_inst);
        end
        if (!done_printf_seen && (u_soc_top.debug_wb_pc >= PC_DONE_PRINTF) &&
            (u_soc_top.debug_wb_pc < 32'h1c000780)) begin
            done_printf_seen <= 1'b1;
            $display("[MATMUL_TB] stage: software reached MATMUL_DONE printf path at cycles=%0d pc=%08x",
                     timeout_count, u_soc_top.debug_wb_pc);
        end

        if ((progress_cycles != 0) && (timeout_count != 0) &&
            ((timeout_count % progress_cycles) == 0)) begin
            print_progress;
        end
        if (timeout_count >= timeout_cycles) begin
            $display("");
            $display("[MATMUL_TB] TIMEOUT: MATMUL_DONE was not printed");
            $display("[MATMUL_TB] debug_wb_pc = %08x", u_soc_top.debug_wb_pc);
            print_progress;
            $display("[MATMUL_TB] matmul busy=%0d done=%0d error=%0d",
                     u_soc_top.u_matmul_axi_slave.busy,
                     u_soc_top.u_matmul_axi_slave.done,
                     u_soc_top.u_matmul_axi_slave.error);
            $finish;
        end
    end
end

soc_top #(.SIMULATION(1'b1)) u_soc_top (
    .clk           (clk),
    .reset         (reset),
    .touch_btn     (touch_btn),
    .dip_sw        (dip_sw),
    .video_red     (video_red),
    .video_green   (video_green),
    .video_blue    (video_blue),
    .video_hsync   (video_hsync),
    .video_vsync   (video_vsync),
    .video_clk     (video_clk),
    .video_de      (video_de),
    .leds          (leds),
    .dpy0          (dpy0),
    .dpy1          (dpy1),
    .base_ram_addr (base_ram_addr),
    .base_ram_be_n (base_ram_be_n),
    .base_ram_ce_n (base_ram_ce_n),
    .base_ram_oe_n (base_ram_oe_n),
    .base_ram_we_n (base_ram_we_n),
    .ext_ram_addr  (ext_ram_addr),
    .ext_ram_be_n  (ext_ram_be_n),
    .ext_ram_ce_n  (ext_ram_ce_n),
    .ext_ram_oe_n  (ext_ram_oe_n),
    .ext_ram_we_n  (ext_ram_we_n),
    .base_ram_data (base_ram_data),
    .ext_ram_data  (ext_ram_data),
    .UART_RX       (UART_RX),
    .UART_TX       (UART_TX)
);

sram_sp #(
    .AW(20),
    .Init_File(`SRAM_Init_File)
) base_sram_sp (
    .ram_addr (base_ram_addr),
    .ram_be_n (base_ram_be_n),
    .ram_ce_n (base_ram_ce_n),
    .ram_oe_n (base_ram_oe_n),
    .ram_we_n (base_ram_we_n),
    .ram_data (base_ram_data)
);

sram_sp #(
    .AW(20),
    .Init_File("none")
) ext_sram_sp (
    .ram_addr (ext_ram_addr),
    .ram_be_n (ext_ram_be_n),
    .ram_ce_n (ext_ram_ce_n),
    .ram_oe_n (ext_ram_oe_n),
    .ram_we_n (ext_ram_we_n),
    .ram_data (ext_ram_data)
);

wire uart_wen;
wire uart_display;
wire [7:0] uart_data;
assign uart_wen = (`UART_PSEL == 1'b1) && (`UART_PENABLE == 1'b1) && (`UART_PWRITE == 1'b1);
assign uart_display = uart_wen && (`UART_WADDR == 8'h0);
assign uart_data = `UART_WDATA;

always @(posedge clk) begin
    if (uart_display) begin
        uart_count <= uart_count + 1;
        $write("%c", uart_data);
        for (i = 0; i < DONE_LEN-1; i = i + 1) begin
            uart_shift[i] <= uart_shift[i+1];
        end
        uart_shift[DONE_LEN-1] <= {24'b0, uart_data};

        if ((uart_shift[1][7:0] == "M") &&
            (uart_shift[2][7:0] == "A") &&
            (uart_shift[3][7:0] == "T") &&
            (uart_shift[4][7:0] == "M") &&
            (uart_shift[5][7:0] == "U") &&
            (uart_shift[6][7:0] == "L") &&
            (uart_shift[7][7:0] == "_") &&
            (uart_shift[8][7:0] == "D") &&
            (uart_shift[9][7:0] == "O") &&
            (uart_shift[10][7:0] == "N") &&
            (uart_data == "E")) begin
            done_seen <= 1'b1;
            check_result;
        end
    end
end

task update_phase_text;
    begin
        if (u_soc_top.debug_wb_pc == PC_CALL_MAIN) begin
            if (same_pc_cycles >= progress_cycles) begin
                phase_text = "STUCK_AT_CALL_MAIN";
            end else begin
                phase_text = "BOOT_CALL_MAIN";
            end
        end else if (u_soc_top.debug_wb_pc < PC_MAIN_ENTRY) begin
            phase_text = "BOOT";
        end else if (u_soc_top.debug_wb_pc < PC_MATMUL_INIT) begin
            phase_text = "MAIN_PROLOGUE";
        end else if (u_soc_top.debug_wb_pc < PC_MATMUL_LOAD_LOOP) begin
            phase_text = "MATMUL_REG_INIT";
        end else if (u_soc_top.debug_wb_pc < PC_MATMUL_WAIT) begin
            phase_text = "LOAD_A_B_START_HW";
        end else if (u_soc_top.debug_wb_pc < PC_MATMUL_STORE) begin
            phase_text = "POLL_MATMUL_DONE";
        end else if (u_soc_top.debug_wb_pc < PC_DONE_PRINTF) begin
            phase_text = "STORE_RESULTS";
        end else if (u_soc_top.debug_wb_pc < 32'h1c000780) begin
            phase_text = "PRINT_DONE";
        end else begin
            phase_text = "LIB_OR_TRAP";
        end
    end
endtask

task print_progress;
    begin
        update_phase_text;
        $display("[MATMUL_TB] progress cycles=%0d phase=%0s pc=%08x inst=%08x same_pc_cycles=%0d uart_bytes=%0d",
                 timeout_count, phase_text, u_soc_top.debug_wb_pc,
                 u_soc_top.debug_wb_inst, same_pc_cycles, uart_count);
        $display("[MATMUL_TB] bus cpu_ar=%0d/%0d addr=%08x cpu_aw=%0d/%0d addr=%08x cpu_w=%0d/%0d cpu_b=%0d/%0d cpu_reads=%0d cpu_write_rsps=%0d ram_r_rsps=%0d",
                 u_soc_top.cpu_arvalid, u_soc_top.cpu_arready, u_soc_top.cpu_araddr,
                 u_soc_top.cpu_awvalid, u_soc_top.cpu_awready, u_soc_top.cpu_awaddr,
                 u_soc_top.cpu_wvalid, u_soc_top.cpu_wready,
                 u_soc_top.cpu_bvalid, u_soc_top.cpu_bready,
                 cpu_read_req_count, cpu_write_rsp_count, ram_read_rsp_count);
        $display("[MATMUL_TB] cpu_bridge ws_valid=%0d inst_req=%0d/%0d inst_addr=%08x inst_ret=%0d data_wr=%0d/%0d data_wr_addr=%08x write_state=%0d write_wait=%0d read_state=%0d b=%0d/%0d",
                 u_soc_top.u_cpu.ws_valid,
                 u_soc_top.u_cpu.inst_rd_req,
                 u_soc_top.u_cpu.inst_rd_rdy,
                 u_soc_top.u_cpu.inst_rd_addr,
                 u_soc_top.u_cpu.inst_ret_valid,
                 u_soc_top.u_cpu.data_wr_req,
                 u_soc_top.u_cpu.data_wr_rdy,
                 u_soc_top.u_cpu.data_wr_addr,
                 u_soc_top.u_cpu.axi_bridge.write_requst_state,
                 u_soc_top.u_cpu.axi_bridge.write_wait_enable,
                 u_soc_top.u_cpu.axi_bridge.read_requst_state,
                 u_soc_top.u_cpu.bvalid,
                 u_soc_top.u_cpu.bready);
        $display("[MATMUL_TB] uart_axi aw=%0d/%0d addr=%08x w=%0d/%0d strb=%x data=%08x b=%0d/%0d sel_wr=%0d apb_psel=%0d penable=%0d pwrite=%0d paddr=%02x",
                 u_soc_top.u_axi_uart_controller.axi_s_awvalid,
                 u_soc_top.u_axi_uart_controller.axi_s_awready,
                 u_soc_top.u_axi_uart_controller.axi_s_awaddr,
                 u_soc_top.u_axi_uart_controller.axi_s_wvalid,
                 u_soc_top.u_axi_uart_controller.axi_s_wready,
                 u_soc_top.u_axi_uart_controller.axi_s_wstrb,
                 u_soc_top.u_axi_uart_controller.axi_s_wdata,
                 u_soc_top.u_axi_uart_controller.axi_s_bvalid,
                 u_soc_top.u_axi_uart_controller.axi_s_bready,
                 u_soc_top.u_axi_uart_controller.AA_axi2apb_bridge_cpu.axi_s_sel_wr,
                 u_soc_top.u_axi_uart_controller.uart0.PSEL,
                 u_soc_top.u_axi_uart_controller.uart0.PENABLE,
                 u_soc_top.u_axi_uart_controller.uart0.PWRITE,
                 u_soc_top.u_axi_uart_controller.uart0.PADDR);
        $display("[MATMUL_TB] matmul busy=%0d done=%0d error=%0d access_seen=%0d write_rsps=%0d read_rsps=%0d axi7_aw=%0d/%0d addr=%08x axi7_w=%0d/%0d axi7_b=%0d/%0d axi7_ar=%0d/%0d addr=%08x axi7_r=%0d/%0d",
                 u_soc_top.u_matmul_axi_slave.busy,
                 u_soc_top.u_matmul_axi_slave.done,
                 u_soc_top.u_matmul_axi_slave.error,
                 matmul_access_seen,
                 matmul_write_rsp_count,
                 matmul_read_rsp_count,
                 u_soc_top.axiOut_7_awvalid,
                 u_soc_top.axiOut_7_awready,
                 u_soc_top.axiOut_7_awaddr,
                 u_soc_top.axiOut_7_wvalid,
                 u_soc_top.axiOut_7_wready,
                 u_soc_top.axiOut_7_bvalid,
                 u_soc_top.axiOut_7_bready,
                 u_soc_top.axiOut_7_arvalid,
                 u_soc_top.axiOut_7_arready,
                 u_soc_top.axiOut_7_araddr,
                 u_soc_top.axiOut_7_rvalid,
                 u_soc_top.axiOut_7_rready);
    end
endtask

task check_result;
    begin
        $display("");
        $display("[MATMUL_TB] MATMUL_DONE captured after %0d clk cycles", timeout_count);

        err_count = 0;
        check_words = group_num * 80;
        for (i = 0; i < check_words; i = i + 1) begin
            if (ext_sram_sp.BRAM[i] !== expected_mem[i]) begin
                if (err_count < 16) begin
                    $display("[MATMUL_TB] mismatch word[%0d]: got=%08x expected=%08x",
                             i, ext_sram_sp.BRAM[i], expected_mem[i]);
                end
                err_count = err_count + 1;
            end
        end

        if (err_count == 0) begin
            $display("[MATMUL_TB] PASS: source and result regions match expected image");
        end else begin
            $display("[MATMUL_TB] FAIL: %0d mismatched words", err_count);
        end
        $finish;
    end
endtask

endmodule
