`timescale 1ns / 1ps
`include "../../rtl/config.h"
`include "../../rtl/ip/gru/gru_defs.vh"

module cfg_driver #(
    parameter bit VERBOSE = 1'b1,
    parameter int unsigned ACCESS_TIMEOUT_CYCLES = 1000000000,
    parameter logic [4:0] DEFAULT_AXI_ID = 5'd0
) (
    input  logic        clk,
    input  logic        rst_n,

    output logic        gru_s_awvalid,
    input  logic        gru_s_awready,
    output logic [31:0] gru_s_awaddr,
    output logic [4:0]  gru_s_awid,
    output logic [7:0]  gru_s_awlen,
    output logic [2:0]  gru_s_awsize,
    output logic [1:0]  gru_s_awburst,
    output logic        gru_s_awlock,
    output logic [3:0]  gru_s_awcache,
    output logic [2:0]  gru_s_awprot,
    output logic        gru_s_wvalid,
    input  logic        gru_s_wready,
    output logic [31:0] gru_s_wdata,
    output logic [3:0]  gru_s_wstrb,
    output logic        gru_s_wlast,
    input  logic        gru_s_bvalid,
    output logic        gru_s_bready,
    input  logic [4:0]  gru_s_bid,
    input  logic [1:0]  gru_s_bresp,
    output logic        gru_s_arvalid,
    input  logic        gru_s_arready,
    output logic [31:0] gru_s_araddr,
    output logic [4:0]  gru_s_arid,
    output logic [7:0]  gru_s_arlen,
    output logic [2:0]  gru_s_arsize,
    output logic [1:0]  gru_s_arburst,
    output logic        gru_s_arlock,
    output logic [3:0]  gru_s_arcache,
    output logic [2:0]  gru_s_arprot,
    input  logic        gru_s_rvalid,
    output logic        gru_s_rready,
    input  logic [31:0] gru_s_rdata,
    input  logic [4:0]  gru_s_rid,
    input  logic [1:0]  gru_s_rresp,
    input  logic        gru_s_rlast,

    output logic        gdu_s_awvalid,
    input  logic        gdu_s_awready,
    output logic [31:0] gdu_s_awaddr,
    output logic [4:0]  gdu_s_awid,
    output logic [7:0]  gdu_s_awlen,
    output logic [2:0]  gdu_s_awsize,
    output logic [1:0]  gdu_s_awburst,
    output logic        gdu_s_awlock,
    output logic [3:0]  gdu_s_awcache,
    output logic [2:0]  gdu_s_awprot,
    output logic        gdu_s_wvalid,
    input  logic        gdu_s_wready,
    output logic [31:0] gdu_s_wdata,
    output logic [3:0]  gdu_s_wstrb,
    output logic        gdu_s_wlast,
    input  logic        gdu_s_bvalid,
    output logic        gdu_s_bready,
    input  logic [4:0]  gdu_s_bid,
    input  logic [1:0]  gdu_s_bresp,
    output logic        gdu_s_arvalid,
    input  logic        gdu_s_arready,
    output logic [31:0] gdu_s_araddr,
    output logic [4:0]  gdu_s_arid,
    output logic [7:0]  gdu_s_arlen,
    output logic [2:0]  gdu_s_arsize,
    output logic [1:0]  gdu_s_arburst,
    output logic        gdu_s_arlock,
    output logic [3:0]  gdu_s_arcache,
    output logic [2:0]  gdu_s_arprot,
    input  logic        gdu_s_rvalid,
    output logic        gdu_s_rready,
    input  logic [31:0] gdu_s_rdata,
    input  logic [4:0]  gdu_s_rid,
    input  logic [1:0]  gdu_s_rresp,
    input  logic        gdu_s_rlast
);

    localparam logic [7:0]  SINGLE_BEAT_LEN   = 8'd0;
    localparam logic [2:0]  WORD_BEAT_SIZE    = 3'd2;
    localparam logic [1:0]  INCR_BURST        = 2'b01;
    localparam logic [3:0]  FULL_WORD_STROBE  = 4'hf;
    localparam logic [31:0] GDU_REG_CTRL      = 32'h0000_0000;
    localparam logic [31:0] GDU_REG_STATUS    = 32'h0000_0004;
    localparam logic [31:0] GDU_REG_FB_BASE   = 32'h0000_0008;
    localparam logic [31:0] GDU_REG_STRIDE    = 32'h0000_000c;
    localparam logic [31:0] GDU_REG_SIZE      = 32'h0000_0010;
    localparam logic [31:0] GDU_REG_PIX_FMT   = 32'h0000_0014;
    localparam logic [31:0] GDU_REG_SWAP      = 32'h0000_0018;
    // Phase-4 GDU perf counter addresses come from gdu_defs.vh (shared macros)
    // so the phase-4 perf testbench sees the same offsets.
    localparam logic [31:0] GRU_STATUS_BUSY_MASK = (32'h1 << `GRU_STATUS_BUSY);
    localparam logic [31:0] GRU_STATUS_DONE_MASK = (32'h1 << `GRU_STATUS_DONE);
    localparam logic [31:0] GRU_STATUS_AXI_ERROR_MASK = (32'h1 << `GRU_STATUS_AXI_ERROR);
    localparam logic [31:0] GRU_STATUS_CFG_ERROR_MASK = (32'h1 << `GRU_STATUS_CFG_ERROR);
    localparam logic [31:0] GRU_STATUS_FENCE_DONE_MASK = (32'h1 << `GRU_STATUS_FENCE_DONE);
    localparam logic [31:0] GRU_STATUS_ENGINE_STALL_MASK = (32'h1 << `GRU_STATUS_ENGINE_STALL);
    localparam logic [31:0] GDU_STATUS_UNDERFLOW_MASK = 32'h1;
    localparam logic [31:0] GDU_STATUS_PRESENT_DONE_MASK = 32'h2;
    localparam logic [31:0] GDU_STATUS_AXI_ERROR_MASK = 32'h4;
    localparam logic [31:0] GDU_STATUS_SWAP_DONE_MASK = 32'h8;
    localparam logic [31:0] GDU_STATUS_SWAP_PENDING_MASK = 32'h10;

    // ---- Verilator --timing handshake-sampling compatibility ----
    // Under Verilator --timing a TB process blocking on @(posedge clk) samples a
    // slave combinational/transitional ready AFTER the slave's same-edge NBA
    // resolves, missing the 1-cycle ready pulse and deadlocking AXI-Lite.
    // Stepping a clocking block (@(cb_tb)) samples its inputs in the preponed
    // region (pre-edge value), de-racing every handshake identically for both
    // simulators. Guarded so ModelSim/other TBs keep the original direct form.
`ifdef VERILATOR_BUILD
    default clocking cb_tb @(posedge clk);
        input gru_s_awready, gru_s_wready, gru_s_bvalid;
        input gru_s_arready, gru_s_rvalid;
        input gru_s_bresp, gru_s_rresp;
        input gru_s_rdata;
        input gdu_s_awready, gdu_s_wready, gdu_s_bvalid;
        input gdu_s_arready, gdu_s_rvalid;
        input gdu_s_bresp, gdu_s_rresp;
        input gdu_s_rdata;
    endclocking
`define RD(x) cb_tb.x
`define SYNC  @(cb_tb)
`else
`define RD(x) x
`define SYNC  @(posedge clk)
`endif

    function automatic logic [31:0] pack_cmd_w0(
        input logic [4:0] opcode,
        input logic [7:0] color_idx,
        input logic [1:0] font_id,
        input logic [8:0] x0,
        input logic [8:0] y0
    );
        begin
            pack_cmd_w0 = {y0[7:0], x0, font_id, color_idx, opcode};
        end
    endfunction

    function automatic logic [31:0] pack_cmd_w1_xy(
        input logic [8:0] x1,
        input logic [8:0] y1
    );
        begin
            pack_cmd_w1_xy = {13'd0, y1[8], 1'b0, y1[7:0], x1};
        end
    endfunction

    function automatic logic [31:0] pack_cmd_w1_xy_invw0_hi(
        input logic [8:0] x1,
        input logic [8:0] y1,
        input logic [5:0] inv_w0_hi
    );
        begin
            pack_cmd_w1_xy_invw0_hi = {inv_w0_hi, 7'd0, y1[8], 1'b0, y1[7:0], x1};
        end
    endfunction

    function automatic logic [31:0] pack_cmd_w1_triangle_xy(
        input logic [8:0] x1,
        input logic [8:0] y1,
        input logic [8:0] y0
    );
        begin
            pack_cmd_w1_triangle_xy = {13'd0, y1[8], y0[8], y1[7:0], x1};
        end
    endfunction

    function automatic logic [31:0] pack_cmd_w1_triangle_xy_invw0_hi(
        input logic [8:0] x1,
        input logic [8:0] y1,
        input logic [8:0] y0,
        input logic [5:0] inv_w0_hi
    );
        begin
            pack_cmd_w1_triangle_xy_invw0_hi = {inv_w0_hi, 7'd0, y1[8], y0[8], y1[7:0], x1};
        end
    endfunction

    function automatic logic [31:0] pack_cmd_w1_ascii(input logic [7:0] ascii);
        begin
            pack_cmd_w1_ascii = {24'd0, ascii};
        end
    endfunction

    function automatic logic [31:0] pack_blit_cmd_w1_size(
        input logic [15:0] width,
        input logic [15:0] height
    );
        begin
            pack_blit_cmd_w1_size = {height, width};
        end
    endfunction

    function automatic logic [31:0] pack_blit_ext_w2_src(
        input logic [15:0] src_x,
        input logic [15:0] src_y
    );
        begin
            pack_blit_ext_w2_src = {src_y, src_x};
        end
    endfunction

    function automatic logic [31:0] pack_blit_ext_w3_dst(
        input logic [15:0] dst_x,
        input logic [15:0] dst_y
    );
        begin
            pack_blit_ext_w3_dst = {dst_y, dst_x};
        end
    endfunction

    function automatic logic [8:0] pack_signed_x9(input integer value);
        begin
            pack_signed_x9 = value[8:0];
        end
    endfunction

    function automatic logic [8:0] pack_signed_y9(input integer value);
        begin
            pack_signed_y9 = value[8:0];
        end
    endfunction

    function automatic logic [31:0] pack_triangle_ext_w0(
        input integer x2,
        input integer y2
    );
        begin
            pack_triangle_ext_w0 = {14'd0, pack_signed_y9(y2), pack_signed_x9(x2)};
        end
    endfunction

    function automatic logic [31:0] pack_triangle_ext_w1_z(
        input logic [15:0] z0,
        input logic [15:0] z1
    );
        begin
            pack_triangle_ext_w1_z = {z1, z0};
        end
    endfunction

    function automatic int font_width(input logic [1:0] font_id);
        begin
            case (font_id)
                2'd1: font_width = 5;
                2'd2: font_width = 6;
                default: font_width = 4;
            endcase
        end
    endfunction

    function automatic int font_height(input logic [1:0] font_id);
        begin
            case (font_id)
                2'd1: font_height = 7;
                2'd2: font_height = 8;
                default: font_height = 6;
            endcase
        end
    endfunction

    task automatic fatal_timeout(input string op_name, input bit is_gru);
        begin
            $fatal(1, "[CFG_DRIVER] timeout during %0s on %0s at t=%0t",
                   op_name, is_gru ? "GRU" : "GDU", $time);
        end
    endtask

    task automatic wait_posedge_cycles(input int unsigned cycles);
        int unsigned i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task automatic reset_outputs();
        begin
            gru_s_awvalid = 1'b0;
            gru_s_awaddr  = 32'd0;
            gru_s_awid    = DEFAULT_AXI_ID;
            gru_s_awlen   = SINGLE_BEAT_LEN;
            gru_s_awsize  = WORD_BEAT_SIZE;
            gru_s_awburst = INCR_BURST;
            gru_s_awlock  = 1'b0;
            gru_s_awcache = 4'd0;
            gru_s_awprot  = 3'd0;
            gru_s_wvalid  = 1'b0;
            gru_s_wdata   = 32'd0;
            gru_s_wstrb   = FULL_WORD_STROBE;
            gru_s_wlast   = 1'b0;
            gru_s_bready  = 1'b0;
            gru_s_arvalid = 1'b0;
            gru_s_araddr  = 32'd0;
            gru_s_arid    = DEFAULT_AXI_ID;
            gru_s_arlen   = SINGLE_BEAT_LEN;
            gru_s_arsize  = WORD_BEAT_SIZE;
            gru_s_arburst = INCR_BURST;
            gru_s_arlock  = 1'b0;
            gru_s_arcache = 4'd0;
            gru_s_arprot  = 3'd0;
            gru_s_rready  = 1'b0;

            gdu_s_awvalid = 1'b0;
            gdu_s_awaddr  = 32'd0;
            gdu_s_awid    = DEFAULT_AXI_ID;
            gdu_s_awlen   = SINGLE_BEAT_LEN;
            gdu_s_awsize  = WORD_BEAT_SIZE;
            gdu_s_awburst = INCR_BURST;
            gdu_s_awlock  = 1'b0;
            gdu_s_awcache = 4'd0;
            gdu_s_awprot  = 3'd0;
            gdu_s_wvalid  = 1'b0;
            gdu_s_wdata   = 32'd0;
            gdu_s_wstrb   = FULL_WORD_STROBE;
            gdu_s_wlast   = 1'b0;
            gdu_s_bready  = 1'b0;
            gdu_s_arvalid = 1'b0;
            gdu_s_araddr  = 32'd0;
            gdu_s_arid    = DEFAULT_AXI_ID;
            gdu_s_arlen   = SINGLE_BEAT_LEN;
            gdu_s_arsize  = WORD_BEAT_SIZE;
            gdu_s_arburst = INCR_BURST;
            gdu_s_arlock  = 1'b0;
            gdu_s_arcache = 4'd0;
            gdu_s_arprot  = 3'd0;
            gdu_s_rready  = 1'b0;
        end
    endtask

    task automatic ctrl_write(
        input bit         is_gru,
        input logic [31:0] addr,
        input logic [31:0] data
    );
        int unsigned timeout_count;
        begin
            if (!rst_n) begin
                @(posedge rst_n);
            end

            if (VERBOSE) begin
                $display("[CFG_DRIVER][WRITE][%0s] addr=0x%08h data=0x%08h t=%0t",
                         is_gru ? "GRU" : "GDU", addr, data, $time);
            end

            if (is_gru) begin
                gru_s_awaddr  <= addr;
                gru_s_awid    <= DEFAULT_AXI_ID;
                gru_s_awvalid <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("write address handshake", 1'b1);
                    end
                end while (!`RD(gru_s_awready));
                gru_s_awvalid <= 1'b0;

                gru_s_wdata  <= data;
                gru_s_wstrb  <= FULL_WORD_STROBE;
                gru_s_wlast  <= 1'b1;
                gru_s_wvalid <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("write data handshake", 1'b1);
                    end
                end while (!`RD(gru_s_wready));
                gru_s_wvalid <= 1'b0;
                gru_s_wlast  <= 1'b0;

                gru_s_bready <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("write response handshake", 1'b1);
                    end
                end while (!`RD(gru_s_bvalid));
                gru_s_bready <= 1'b0;

                if (`RD(gru_s_bresp) !== 2'b00) begin
                    $fatal(1, "[CFG_DRIVER] GRU write response error bresp=%0b addr=0x%08h", `RD(gru_s_bresp), addr);
                end
            end else begin
                gdu_s_awaddr  <= addr;
                gdu_s_awid    <= DEFAULT_AXI_ID;
                gdu_s_awvalid <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("write address handshake", 1'b0);
                    end
                end while (!`RD(gdu_s_awready));
                gdu_s_awvalid <= 1'b0;

                gdu_s_wdata  <= data;
                gdu_s_wstrb  <= FULL_WORD_STROBE;
                gdu_s_wlast  <= 1'b1;
                gdu_s_wvalid <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("write data handshake", 1'b0);
                    end
                end while (!`RD(gdu_s_wready));
                gdu_s_wvalid <= 1'b0;
                gdu_s_wlast  <= 1'b0;

                gdu_s_bready <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("write response handshake", 1'b0);
                    end
                end while (!`RD(gdu_s_bvalid));
                gdu_s_bready <= 1'b0;

                if (`RD(gdu_s_bresp) !== 2'b00) begin
                    $fatal(1, "[CFG_DRIVER] GDU write response error bresp=%0b addr=0x%08h", `RD(gdu_s_bresp), addr);
                end
            end
        end
    endtask

    task automatic ctrl_read(
        input  bit          is_gru,
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        int unsigned timeout_count;
        begin
            if (!rst_n) begin
                @(posedge rst_n);
            end

            if (VERBOSE) begin
                $display("[CFG_DRIVER][READ ][%0s] addr=0x%08h t=%0t",
                         is_gru ? "GRU" : "GDU", addr, $time);
            end

            if (is_gru) begin
                gru_s_araddr  <= addr;
                gru_s_arid    <= DEFAULT_AXI_ID;
                gru_s_arvalid <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("read address handshake", 1'b1);
                    end
                end while (!`RD(gru_s_arready));
                gru_s_arvalid <= 1'b0;

                gru_s_rready <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("read data handshake", 1'b1);
                    end
                end while (!`RD(gru_s_rvalid));
                data = `RD(gru_s_rdata);
                gru_s_rready <= 1'b0;

                if (`RD(gru_s_rresp) !== 2'b00) begin
                    $fatal(1, "[CFG_DRIVER] GRU read response error rresp=%0b addr=0x%08h", `RD(gru_s_rresp), addr);
                end
            end else begin
                gdu_s_araddr  <= addr;
                gdu_s_arid    <= DEFAULT_AXI_ID;
                gdu_s_arvalid <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("read address handshake", 1'b0);
                    end
                end while (!`RD(gdu_s_arready));
                gdu_s_arvalid <= 1'b0;

                gdu_s_rready <= 1'b1;
                timeout_count = 0;
                do begin
                    `SYNC;
                    timeout_count = timeout_count + 1;
                    if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                        fatal_timeout("read data handshake", 1'b0);
                    end
                end while (!`RD(gdu_s_rvalid));
                data = `RD(gdu_s_rdata);
                gdu_s_rready <= 1'b0;

                if (`RD(gdu_s_rresp) !== 2'b00) begin
                    $fatal(1, "[CFG_DRIVER] GDU read response error rresp=%0b addr=0x%08h", `RD(gdu_s_rresp), addr);
                end
            end

            if (VERBOSE) begin
                $display("[CFG_DRIVER][RDATA][%0s] addr=0x%08h data=0x%08h t=%0t",
                         is_gru ? "GRU" : "GDU", addr, data, $time);
            end
        end
    endtask

    task automatic gru_write_reg(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            ctrl_write(1'b1, addr, data);
        end
    endtask

    task automatic gdu_write_reg(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            ctrl_write(1'b0, addr, data);
        end
    endtask

    task automatic gru_read_reg(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            ctrl_read(1'b1, addr, data);
        end
    endtask

    task automatic gdu_read_reg(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            ctrl_read(1'b0, addr, data);
        end
    endtask

    task automatic gru_push_cmd(
        input logic [31:0] cmd_w0,
        input logic [31:0] cmd_w1
    );
        begin
            ctrl_write(1'b1, `GRU_REG_CMD_W0, cmd_w0);
            ctrl_write(1'b1, `GRU_REG_CMD_W1, cmd_w1);
            ctrl_write(1'b1, `GRU_REG_CMD_PUSH, 32'h0000_0001);
        end
    endtask

    task automatic gru_push_ext_cmd(
        input logic [31:0] cmd_w0,
        input logic [31:0] cmd_w1,
        input logic [31:0] ext_w0,
        input logic [31:0] ext_w1,
        input logic [31:0] ext_w2,
        input logic [31:0] ext_w3,
        input logic [31:0] ext_w4
    );
        begin
            ctrl_write(1'b1, `GRU_REG_CMD_W0, cmd_w0);
            ctrl_write(1'b1, `GRU_REG_CMD_W1, cmd_w1);
            ctrl_write(1'b1, `GRU_REG_EXT_W0, ext_w0);
            ctrl_write(1'b1, `GRU_REG_EXT_W1, ext_w1);
            ctrl_write(1'b1, `GRU_REG_EXT_W2, ext_w2);
            ctrl_write(1'b1, `GRU_REG_EXT_W3, ext_w3);
            ctrl_write(1'b1, `GRU_REG_EXT_W4, ext_w4);
            ctrl_write(1'b1, `GRU_REG_EXT_PUSH, 32'h0000_0001);
        end
    endtask

    task automatic gru_setup(
        input logic [31:0] fb_base,
        input logic [31:0] stride,
        input logic [15:0] width,
        input logic [15:0] height,
        input bit          enable
    );
        begin
            ctrl_write(1'b1, `GRU_REG_CTRL, 32'h0000_0000);
            ctrl_write(1'b1, `GRU_REG_FB_BASE, fb_base);
            ctrl_write(1'b1, `GRU_REG_STRIDE, stride);
            ctrl_write(1'b1, `GRU_REG_WIDTH_HEIGHT, {height, width});
            ctrl_write(1'b1, `GRU_REG_PIXEL_FORMAT, `GRU_PIXFMT_RGB565);
            ctrl_write(1'b1, `GRU_REG_CTRL, {30'd0, 1'b0, enable});
        end
    endtask

    task automatic gdu_setup(
        input logic [31:0] fb_base,
        input logic [31:0] stride,
        input logic [15:0] width,
        input logic [15:0] height,
        input logic [1:0]  pixel_format,
        input bit          enable
    );
        begin
            ctrl_write(1'b0, GDU_REG_CTRL, 32'h0000_0000);
            ctrl_write(1'b0, GDU_REG_FB_BASE, fb_base);
            ctrl_write(1'b0, GDU_REG_STRIDE, stride);
            ctrl_write(1'b0, GDU_REG_SIZE, {height, width});
            ctrl_write(1'b0, GDU_REG_PIX_FMT, {30'd0, pixel_format});
            ctrl_write(1'b0, GDU_REG_CTRL, {31'd0, enable});
        end
    endtask

    task automatic gdu_request_swap(input logic [31:0] next_fb_base);
        begin
            ctrl_write(1'b0, GDU_REG_FB_BASE, next_fb_base);
            ctrl_write(1'b0, GDU_REG_SWAP, 32'h0000_0001);
        end
    endtask

    task automatic gru_set_fb_base(input logic [31:0] fb_base);
        begin
            ctrl_write(1'b1, `GRU_REG_FB_BASE, fb_base);
        end
    endtask

    task automatic gru_set_pixel_format(input logic [2:0] pixel_format);
        begin
            ctrl_write(1'b1, `GRU_REG_PIXEL_FORMAT, {29'd0, pixel_format});
        end
    endtask

    task automatic gdu_enable(input bit enable);
        begin
            ctrl_write(1'b0, GDU_REG_CTRL, {31'd0, enable});
        end
    endtask

    task automatic gdu_read_status(output logic [31:0] status);
        begin
            ctrl_read(1'b0, GDU_REG_STATUS, status);
        end
    endtask

    task automatic gru_read_status(output logic [31:0] status);
        begin
            ctrl_read(1'b1, `GRU_REG_STATUS, status);
        end
    endtask

    task automatic gru_clear_status(input logic [31:0] status_mask);
        begin
            ctrl_write(1'b1, `GRU_REG_STATUS, status_mask);
        end
    endtask

    task automatic gdu_read_swap_status(output logic [31:0] status);
        begin
            ctrl_read(1'b0, GDU_REG_SWAP, status);
        end
    endtask

    task automatic gru_wait_idle(output logic [31:0] status);
        int unsigned timeout_count;
        begin
            timeout_count = 0;
            while (1'b1) begin
                gru_read_status(status);
                if (!status[0]) begin
                    break;
                end
                timeout_count = timeout_count + 1;
                if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                    fatal_timeout("wait gru idle", 1'b1);
                end
                wait_posedge_cycles(1);
            end
        end
    endtask

    task automatic gdu_wait_swap_done(output logic [31:0] status);
        int unsigned timeout_count;
        begin
            timeout_count = 0;
            while (1'b1) begin
                ctrl_read(1'b0, GDU_REG_STATUS, status);
                if (status[3]) begin
                    break;
                end
                timeout_count = timeout_count + 1;
                if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                    fatal_timeout("wait gdu swap done", 1'b0);
                end
                wait_posedge_cycles(1);
            end
        end
    endtask

    task automatic gru_wait_idle_checked(output logic [31:0] status);
        int unsigned timeout_count;
        begin
            status = 32'd0;
            timeout_count = 0;

            while ((status & GRU_STATUS_DONE_MASK) == 0) begin
                gru_read_status(status);
                if ((status & (GRU_STATUS_AXI_ERROR_MASK | GRU_STATUS_CFG_ERROR_MASK)) != 0) begin
                    $fatal(1, "[CFG_DRIVER] GRU status error while waiting done: 0x%08x", status);
                end
                timeout_count = timeout_count + 1;
                if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                    fatal_timeout("wait gru done checked", 1'b1);
                end
            end
            if ((status & (GRU_STATUS_AXI_ERROR_MASK | GRU_STATUS_CFG_ERROR_MASK)) != 0) begin
                $fatal(1, "[CFG_DRIVER] GRU status error: 0x%08x", status);
            end
        end
    endtask

    task automatic gru_wait_fence_done_checked(output logic [31:0] status);
        int unsigned timeout_count;
        begin
            gru_read_status(status);
            if ((status & GRU_STATUS_FENCE_DONE_MASK) != 0) begin
                gru_clear_status(GRU_STATUS_FENCE_DONE_MASK);
            end

            status = 32'd0;
            timeout_count = 0;
            while ((status & GRU_STATUS_FENCE_DONE_MASK) == 0) begin
                gru_read_status(status);
                if ((status & (GRU_STATUS_AXI_ERROR_MASK | GRU_STATUS_CFG_ERROR_MASK)) != 0) begin
                    $fatal(1, "[CFG_DRIVER] GRU status error while waiting fence: 0x%08x", status);
                end
                timeout_count = timeout_count + 1;
                if (timeout_count >= ACCESS_TIMEOUT_CYCLES) begin
                    fatal_timeout("wait gru fence done checked", 1'b1);
                end
            end
        end
    endtask

    task automatic gdu_wait_swap_done_checked(output logic [31:0] status);
        begin
            status = 32'd0;
            while ((status & GDU_STATUS_SWAP_DONE_MASK) == 0) begin
                ctrl_read(1'b0, GDU_REG_STATUS, status);
                if ((status & (GDU_STATUS_UNDERFLOW_MASK | GDU_STATUS_AXI_ERROR_MASK)) != 0) begin
                    $fatal(1, "[CFG_DRIVER] GDU status error while waiting swap: 0x%08x", status);
                end
            end
            if ((status & GDU_STATUS_UNDERFLOW_MASK) != 0) begin
                $fatal(1, "[CFG_DRIVER] GDU underflow after swap: 0x%08x", status);
            end
            if ((status & GDU_STATUS_AXI_ERROR_MASK) != 0) begin
                $fatal(1, "[CFG_DRIVER] GDU AXI error after swap: 0x%08x", status);
            end
        end
    endtask

    task automatic gdu_wait_present_done_checked(output logic [31:0] status);
        begin
            status = 32'd0;
            while ((status & GDU_STATUS_PRESENT_DONE_MASK) == 0) begin
                ctrl_read(1'b0, GDU_REG_STATUS, status);
                if ((status & (GDU_STATUS_UNDERFLOW_MASK | GDU_STATUS_AXI_ERROR_MASK)) != 0) begin
                    $fatal(1, "[CFG_DRIVER] GDU status error while waiting present: 0x%08x", status);
                end
            end
            if ((status & GDU_STATUS_UNDERFLOW_MASK) != 0) begin
                $fatal(1, "[CFG_DRIVER] GDU underflow after present: 0x%08x", status);
            end
            if ((status & GDU_STATUS_AXI_ERROR_MASK) != 0) begin
                $fatal(1, "[CFG_DRIVER] GDU AXI error after present: 0x%08x", status);
            end
        end
    endtask

    task automatic gru_issue_clear(input logic [7:0] color_idx);
        begin
            gru_push_cmd(pack_cmd_w0(`GRU_OP_CLEAR, color_idx, 2'd0, 9'd0, 8'd0), 32'd0);
        end
    endtask

    task automatic gru_issue_fence();
        begin
            gru_push_cmd(pack_cmd_w0(`GRU_OP_FENCE, 8'd0, 2'd0, 9'd0, 8'd0), 32'd0);
        end
    endtask

    task automatic gru_issue_fill_rect(
        input logic [8:0] x,
        input logic [7:0] y,
        input int w,
        input int h,
        input logic [7:0] color_idx
    );
        logic [8:0] x1;
        logic [7:0] y1;
        begin
            x1 = x + w - 1;
            y1 = y + h - 1;
            gru_push_cmd(
                pack_cmd_w0(`GRU_OP_FILL_RECT, color_idx, 2'd0, x, y),
                pack_cmd_w1_xy(x1, y1)
            );
        end
    endtask

    task automatic gru_issue_draw_line(
        input int x0,
        input int y0,
        input int x1,
        input int y1,
        input logic [7:0] color_idx
    );
        begin
            gru_push_cmd(
                pack_cmd_w0(`GRU_OP_DRAW_LINE, color_idx, 2'd0, x0[8:0], y0[7:0]),
                pack_cmd_w1_xy(x1[8:0], y1[7:0])
            );
        end
    endtask

    task automatic gru_issue_draw_rect(
        input int x,
        input int y,
        input int w,
        input int h,
        input logic [7:0] color_idx
    );
        begin
            if ((w <= 0) || (h <= 0)) begin
                return;
            end
            gru_issue_draw_line(x, y, x + w - 1, y, color_idx);
            gru_issue_draw_line(x, y + h - 1, x + w - 1, y + h - 1, color_idx);
            gru_issue_draw_line(x, y, x, y + h - 1, color_idx);
            gru_issue_draw_line(x + w - 1, y, x + w - 1, y + h - 1, color_idx);
        end
    endtask

    task automatic gru_issue_draw_glyph(
        input logic [8:0] x,
        input logic [7:0] y,
        input logic [7:0] ascii,
        input logic [1:0] font_id,
        input logic [7:0] color_idx
    );
        begin
            gru_push_cmd(
                pack_cmd_w0(`GRU_OP_DRAW_GLYPH, color_idx, font_id, x, y),
                pack_cmd_w1_ascii(ascii)
            );
        end
    endtask

    task automatic gru_issue_draw_text(
        input int x,
        input int y,
        input string text,
        input logic [1:0] font_id,
        input logic [7:0] color_idx
    );
        int idx;
        int cx;
        int cy;
        int step_x;
        int step_y;
        begin
            cx = x;
            cy = y;
            step_x = font_width(font_id) + 1;
            step_y = font_height(font_id) + 1;

            for (idx = 0; idx < text.len(); idx = idx + 1) begin
                if (text[idx] == 8'h0a) begin
                    cx = x;
                    cy = cy + step_y;
                end else begin
                    gru_issue_draw_glyph(cx[8:0], cy[7:0], text[idx], font_id, color_idx);
                    cx = cx + step_x;
                end
            end
        end
    endtask

    task automatic gru_issue_blit_rgb565(
        input logic [31:0] src_base_addr,
        input logic [31:0] src_stride_bytes,
        input logic [15:0] src_x,
        input logic [15:0] src_y,
        input logic [15:0] dst_x,
        input logic [15:0] dst_y,
        input logic [15:0] width,
        input logic [15:0] height
    );
        begin
            gru_push_ext_cmd(
                pack_cmd_w0(`GRU_OP_BLIT, 8'd0, 2'd0, 9'd0, 8'd0),
                pack_blit_cmd_w1_size(width, height),
                src_base_addr,
                src_stride_bytes,
                pack_blit_ext_w2_src(src_x, src_y),
                pack_blit_ext_w3_dst(dst_x, dst_y),
                {29'd0, `GRU_PIXFMT_RGB565}
            );
        end
    endtask

    task automatic gru_issue_triangle_flat(
        input integer x0,
        input integer y0,
        input integer x1,
        input integer y1,
        input integer x2,
        input integer y2,
        input logic [7:0] color_idx
    );
        begin
            gru_push_ext_cmd(
                pack_cmd_w0(`GRU_OP_TRIANGLE_FLAT, color_idx, 2'd0, pack_signed_x9(x0), pack_signed_y9(y0)),
                pack_cmd_w1_triangle_xy(pack_signed_x9(x1), pack_signed_y9(y1), pack_signed_y9(y0)),
                pack_triangle_ext_w0(x2, y2),
                32'd0,
                32'd0,
                32'd0,
                32'd0
            );
        end
    endtask

    task automatic gru_set_depth_base(input logic [31:0] depth_base);
        begin
            ctrl_write(1'b1, `GRU_REG_DEPTH_BASE, depth_base);
        end
    endtask

    task automatic gru_set_depth_ctrl(
        input bit enable,
        input bit write_enable,
        input bit lequal
    );
        logic [31:0] value;
        begin
            value = 32'd0;
            value[`GRU_DEPTH_CTRL_ENABLE_BIT] = enable;
            value[`GRU_DEPTH_CTRL_WRITE_BIT]  = write_enable;
            value[`GRU_DEPTH_CTRL_LEQUAL_BIT] = lequal;
            ctrl_write(1'b1, `GRU_REG_DEPTH_CTRL, value);
        end
    endtask

    task automatic gru_set_texture(
        input logic [31:0] tex_base,
        input logic [15:0] tex_width,
        input logic [15:0] tex_height,
        input logic [31:0] tex_stride,
        input logic [31:0] tex_ctrl
    );
        begin
            ctrl_write(1'b1, `GRU_REG_TEX_BASE, tex_base);
            ctrl_write(1'b1, `GRU_REG_TEX_SIZE, {tex_height, tex_width});
            ctrl_write(1'b1, `GRU_REG_TEX_STRIDE, tex_stride);
            ctrl_write(1'b1, `GRU_REG_TEX_CTRL, tex_ctrl);
        end
    endtask

    task automatic gru_issue_clear_depth(input logic [15:0] depth_value);
        begin
            gru_push_cmd(pack_cmd_w0(`GRU_OP_CLEAR_DEPTH, 8'd0, 2'd0, 9'd0, 8'd0), {16'd0, depth_value});
        end
    endtask

    task automatic gru_issue_triangle_z(
        input integer x0,
        input integer y0,
        input logic [15:0] z0,
        input integer x1,
        input integer y1,
        input logic [15:0] z1,
        input integer x2,
        input integer y2,
        input logic [15:0] z2,
        input logic [7:0] color_idx
    );
        begin
            gru_push_ext_cmd(
                pack_cmd_w0(`GRU_OP_TRIANGLE_Z, color_idx, 2'd0, pack_signed_x9(x0), pack_signed_y9(y0)),
                pack_cmd_w1_triangle_xy(pack_signed_x9(x1), pack_signed_y9(y1), pack_signed_y9(y0)),
                pack_triangle_ext_w0(x2, y2),
                pack_triangle_ext_w1_z(z0, z1),
                {16'd0, z2},
                32'd0,
                32'd0
            );
        end
    endtask

    task automatic gru_issue_triangle_gouraud(
        input integer x0,
        input integer y0,
        input logic [15:0] c0_rgb565,
        input integer x1,
        input integer y1,
        input logic [15:0] c1_rgb565,
        input integer x2,
        input integer y2,
        input logic [15:0] c2_rgb565
    );
        begin
            gru_push_ext_cmd(
                pack_cmd_w0(`GRU_OP_TRIANGLE_GOURAUD, 8'd0, 2'd0, pack_signed_x9(x0), pack_signed_y9(y0)),
                pack_cmd_w1_triangle_xy(pack_signed_x9(x1), pack_signed_y9(y1), pack_signed_y9(y0)),
                pack_triangle_ext_w0(x2, y2),
                c0_rgb565,
                c1_rgb565,
                c2_rgb565,
                32'd0
            );
        end
    endtask

    task automatic gru_issue_triangle_textured(
        input integer x0,
        input integer y0,
        input logic signed [15:0] u0_q8_8,
        input logic signed [15:0] v0_q8_8,
        input integer x1,
        input integer y1,
        input logic signed [15:0] u1_q8_8,
        input logic signed [15:0] v1_q8_8,
        input integer x2,
        input integer y2,
        input logic signed [15:0] u2_q8_8,
        input logic signed [15:0] v2_q8_8
    );
        begin
            gru_push_ext_cmd(
                pack_cmd_w0(`GRU_OP_TRIANGLE_TEXTURED, 8'd0, 2'd0, pack_signed_x9(x0), pack_signed_y9(y0)),
                pack_cmd_w1_triangle_xy(pack_signed_x9(x1), pack_signed_y9(y1), pack_signed_y9(y0)),
                pack_triangle_ext_w0(x2, y2),
                {v0_q8_8, u0_q8_8},
                {v1_q8_8, u1_q8_8},
                {v2_q8_8, u2_q8_8},
                32'd0
            );
        end
    endtask

    task automatic gru_issue_triangle_textured_perspective(
        input integer x0,
        input integer y0,
        input logic signed [15:0] u0_over_w_q8_8,
        input logic signed [15:0] v0_over_w_q8_8,
        input logic signed [15:0] inv_w0_q8_8,
        input integer x1,
        input integer y1,
        input logic signed [15:0] u1_over_w_q8_8,
        input logic signed [15:0] v1_over_w_q8_8,
        input logic signed [15:0] inv_w1_q8_8,
        input integer x2,
        input integer y2,
        input logic signed [15:0] u2_over_w_q8_8,
        input logic signed [15:0] v2_over_w_q8_8,
        input logic signed [15:0] inv_w2_q8_8
    );
        begin
            gru_push_ext_cmd(
                pack_cmd_w0(`GRU_OP_TRIANGLE_TEXTURED_PC, inv_w0_q8_8[7:0], inv_w0_q8_8[9:8], pack_signed_x9(x0), pack_signed_y9(y0)),
                pack_cmd_w1_triangle_xy_invw0_hi(pack_signed_x9(x1), pack_signed_y9(y1), pack_signed_y9(y0), inv_w0_q8_8[15:10]),
                pack_triangle_ext_w0(x2, y2),
                {v0_over_w_q8_8, u0_over_w_q8_8},
                {v1_over_w_q8_8, u1_over_w_q8_8},
                {v2_over_w_q8_8, u2_over_w_q8_8},
                {inv_w2_q8_8, inv_w1_q8_8}
            );
        end
    endtask

    initial begin
        reset_outputs();
    end

    always @(negedge rst_n) begin
        reset_outputs();
    end

endmodule
