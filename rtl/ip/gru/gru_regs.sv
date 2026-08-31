`include "../../config.h"
`include "gru_defs.vh"

module gru_regs (
    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_awaddr,
    input  logic [4:0]  s_awid,
    input  logic [7:0]  s_awlen,
    input  logic [2:0]  s_awsize,
    input  logic [1:0]  s_awburst,
    input  logic        s_awlock,
    input  logic [3:0]  s_awcache,
    input  logic [2:0]  s_awprot,
    input  logic        s_wvalid,
    output logic        s_wready,
    input  logic [31:0] s_wdata,
    input  logic [3:0]  s_wstrb,
    input  logic        s_wlast,
    output logic        s_bvalid,
    input  logic        s_bready,
    output logic [4:0]  s_bid,
    output logic [1:0]  s_bresp,
    input  logic        s_arvalid,
    output logic        s_arready,
    input  logic [31:0] s_araddr,
    input  logic [4:0]  s_arid,
    input  logic [7:0]  s_arlen,
    input  logic [2:0]  s_arsize,
    input  logic [1:0]  s_arburst,
    input  logic        s_arlock,
    input  logic [3:0]  s_arcache,
    input  logic [2:0]  s_arprot,
    output logic        s_rvalid,
    input  logic        s_rready,
    output logic [31:0] s_rdata,
    output logic [4:0]  s_rid,
    output logic [1:0]  s_rresp,
    output logic        s_rlast,

    input  logic        status_busy,
    input  logic        status_done,
    input  logic        status_axi_error,
    input  logic        status_cfg_error,
    input  logic        status_fence_done,
    input  logic        status_engine_stall,
    input  logic [$clog2(`GRU_CMD_FIFO_DEPTH):0] cmd_level,
    input  logic        cmd_fifo_full,
    input  logic        cmd_fifo_empty,
    input  logic        ext_cmd_fifo_full,
    input  logic        cmd_buffer_busy,
    input  logic        cmd_buffer_done,
    input  logic        cmd_buffer_cfg_error,
    input  logic        cmd_buffer_axi_error,
    input  logic        cmd_buffer_present_done,

    output logic        gru_enable,
    output logic        soft_reset_pulse,
    output logic [31:0] fb_base,
    output logic [31:0] depth_base,
    output logic [31:0] depth_ctrl,
    output logic [31:0] tex_base,
    output logic [31:0] tex_stride,
    output logic [15:0] tex_width,
    output logic [15:0] tex_height,
    output logic [31:0] tex_ctrl,
    output logic [31:0] stride,
    output logic [15:0] width,
    output logic [15:0] height,
    output logic [2:0]  pixel_format,
    output logic        cfg_write_reject_pulse,
    output logic [31:0] status_w1c_mask,
    output logic        cmd_push_valid,
    output logic [63:0] cmd_push_data,
    output logic        ext_cmd_push_valid,
    output logic [31:0] ext_cmd_w0,
    output logic [31:0] ext_cmd_w1,
    output logic [31:0] ext_cmd_w2,
    output logic [31:0] ext_cmd_w3,
    output logic [31:0] ext_cmd_w4,
    output logic [31:0] cmd_buffer_base,
    output logic [15:0] cmd_buffer_word_count,
    output logic        cmd_buffer_exec_pulse,
    output logic        cmd_buffer_irq_enable,
    output logic [4:0]  cmd_buffer_status_w1c_mask,

    // Phase-4 cumulative perf counters (read-only MMIO window).  Driven by
    // gru_axi_writer (WCB) and gru_blit_engine via gru_top.
    input  logic [31:0] perf_wcb_span_in,
    input  logic [31:0] perf_wcb_pix_in,
    input  logic [31:0] perf_wcb_aw_txn,
    input  logic [31:0] perf_wcb_beat_out,
    input  logic [31:0] perf_wcb_full_beat,
    input  logic [31:0] perf_wcb_partial,
    input  logic [31:0] perf_wcb_flush,
    input  logic [31:0] perf_blit_count,
    input  logic [31:0] perf_blit_rd_beat,
    input  logic [31:0] perf_blit_wr_beat,
    input  logic [31:0] perf_blit_pixel,
    input  logic [31:0] perf_blit_cycle,

    input  logic        aclk,
    input  logic        aresetn
);
    logic busy;
    logic write_phase;
    logic req_is_read;
    logic [4:0] req_id;
    logic [31:0] req_addr;

    logic [31:0] cmd_w0_shadow;
    logic [31:0] cmd_w1_shadow;
    logic [31:0] ext_w0_shadow;
    logic [31:0] ext_w1_shadow;
    logic [31:0] ext_w2_shadow;
    logic [31:0] ext_w3_shadow;
    logic [31:0] ext_w4_shadow;
    logic [31:0] cb_base_shadow;
    logic [15:0] cb_word_count_shadow;
    logic        cb_irq_enable_shadow;

    wire ar_enter = s_arvalid & s_arready;
    wire aw_enter = s_awvalid & s_awready;
    wire w_enter  = s_wvalid & s_wready & s_wlast;
    wire r_retire = s_rvalid & s_rready & s_rlast;
    wire b_retire = s_bvalid & s_bready;

    wire [7:0] addr_lsb = req_addr[7:0];
    wire push_addr = (req_addr[7:0] == `GRU_REG_CMD_PUSH);
    wire ext_push_addr = (req_addr[7:0] == `GRU_REG_EXT_PUSH);
    wire push_hit = w_enter && push_addr;
    wire ext_push_hit = w_enter && ext_push_addr;
    wire cfg_write_hit = w_enter &&
                         ((addr_lsb == `GRU_REG_FB_BASE) ||
                          (addr_lsb == `GRU_REG_STRIDE) ||
                          (addr_lsb == `GRU_REG_WIDTH_HEIGHT) ||
                          (addr_lsb == `GRU_REG_PIXEL_FORMAT));
    wire cfg_write_blocked = cfg_write_hit && status_busy;

    assign s_arready = ~busy & (~req_is_read | ~s_awvalid);
    assign s_awready = ~busy & ( req_is_read | ~s_arvalid);
    assign s_rid = req_id;
    assign s_bid = req_id;
    assign s_rresp = 2'b00;
    assign s_bresp = 2'b00;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            busy <= 1'b0;
        end else begin
            if (ar_enter | aw_enter) begin
                busy <= 1'b1;
            end else if (r_retire | b_retire) begin
                busy <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            req_is_read <= 1'b0;
            req_id <= 5'd0;
            req_addr <= 32'd0;
        end else if (ar_enter | aw_enter) begin
            req_is_read <= ar_enter;
            req_id <= ar_enter ? s_arid : s_awid;
            req_addr <= ar_enter ? s_araddr : s_awaddr;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            write_phase <= 1'b0;
            s_wready <= 1'b0;
        end else begin
            if (aw_enter) begin
                write_phase <= 1'b1;
                s_wready <= ~((((s_awaddr[7:0] == `GRU_REG_CMD_PUSH) && cmd_fifo_full) ||
                               ((s_awaddr[7:0] == `GRU_REG_EXT_PUSH) && (cmd_fifo_full || ext_cmd_fifo_full))) ||
                              (((s_awaddr[7:0] == `GRU_REG_CMD_PUSH) ||
                                (s_awaddr[7:0] == `GRU_REG_EXT_PUSH)) && cmd_buffer_busy));
            end else if (ar_enter) begin
                write_phase <= 1'b0;
                s_wready <= 1'b0;
            end else if (write_phase && ~s_wready && push_addr && ~cmd_fifo_full) begin
                s_wready <= ~cmd_buffer_busy;
            end else if (write_phase && ~s_wready && ext_push_addr && ~(cmd_fifo_full || ext_cmd_fifo_full)) begin
                s_wready <= ~cmd_buffer_busy;
            end else if (w_enter) begin
                s_wready <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_rvalid <= 1'b0;
            s_rlast <= 1'b0;
            s_rdata <= 32'd0;
        end else begin
            if (busy && ~write_phase && ~r_retire) begin
                s_rvalid <= 1'b1;
                s_rlast <= 1'b1;
                case (addr_lsb)
                    `GRU_REG_CTRL: begin
                        s_rdata <= {30'd0, 1'b0, gru_enable};
                    end
                    `GRU_REG_STATUS: begin
                        s_rdata <= {26'd0,
                                    status_engine_stall,
                                    status_fence_done,
                                    status_cfg_error,
                                    status_axi_error,
                                    status_done,
                                    cmd_fifo_empty,
                                    cmd_fifo_full,
                                    status_busy};
                    end
                    `GRU_REG_FB_BASE: begin
                        s_rdata <= fb_base;
                    end
                    `GRU_REG_STRIDE: begin
                        s_rdata <= stride;
                    end
                    `GRU_REG_WIDTH_HEIGHT: begin
                        s_rdata <= {height, width};
                    end
                    `GRU_REG_PIXEL_FORMAT: begin
                        s_rdata <= {29'd0, pixel_format};
                    end
                    `GRU_REG_CMD_W0: begin
                        s_rdata <= cmd_w0_shadow;
                    end
                    `GRU_REG_CMD_W1: begin
                        s_rdata <= cmd_w1_shadow;
                    end
                    `GRU_REG_CMD_LEVEL: begin
                        s_rdata <= {{(32-$bits(cmd_level)){1'b0}}, cmd_level};
                    end
                    `GRU_REG_EXT_W0: begin
                        s_rdata <= ext_w0_shadow;
                    end
                    `GRU_REG_EXT_W1: begin
                        s_rdata <= ext_w1_shadow;
                    end
                    `GRU_REG_EXT_W2: begin
                        s_rdata <= ext_w2_shadow;
                    end
                    `GRU_REG_EXT_W3: begin
                        s_rdata <= ext_w3_shadow;
                    end
                    `GRU_REG_EXT_W4: begin
                        s_rdata <= ext_w4_shadow;
                    end
                    `GRU_REG_DEPTH_BASE: begin
                        s_rdata <= depth_base;
                    end
                    `GRU_REG_DEPTH_CTRL: begin
                        s_rdata <= depth_ctrl;
                    end
                    `GRU_REG_TEX_BASE: begin
                        s_rdata <= tex_base;
                    end
                    `GRU_REG_TEX_SIZE: begin
                        s_rdata <= {tex_height, tex_width};
                    end
                    `GRU_REG_TEX_STRIDE: begin
                        s_rdata <= tex_stride;
                    end
                    `GRU_REG_TEX_CTRL: begin
                        s_rdata <= tex_ctrl;
                    end
                    `GRU_REG_CB_BASE: begin
                        s_rdata <= cb_base_shadow;
                    end
                    `GRU_REG_CB_WORD_COUNT: begin
                        s_rdata <= {16'd0, cb_word_count_shadow};
                    end
                    `GRU_REG_CB_CTRL: begin
                        s_rdata <= {30'd0, cb_irq_enable_shadow, 1'b0};
                    end
                    `GRU_REG_CB_STATUS: begin
                        s_rdata <= {27'd0,
                                    cmd_buffer_present_done,
                                    cmd_buffer_axi_error,
                                    cmd_buffer_cfg_error,
                                    cmd_buffer_done,
                                    cmd_buffer_busy};
                    end
                    `GRU_REG_PERF_WCB_SPAN_IN:  s_rdata <= perf_wcb_span_in;
                    `GRU_REG_PERF_WCB_PIX_IN:   s_rdata <= perf_wcb_pix_in;
                    `GRU_REG_PERF_WCB_AW_TXN:   s_rdata <= perf_wcb_aw_txn;
                    `GRU_REG_PERF_WCB_BEAT_OUT: s_rdata <= perf_wcb_beat_out;
                    `GRU_REG_PERF_WCB_FULL_BEAT:s_rdata <= perf_wcb_full_beat;
                    `GRU_REG_PERF_WCB_PARTIAL:  s_rdata <= perf_wcb_partial;
                    `GRU_REG_PERF_WCB_FLUSH:    s_rdata <= perf_wcb_flush;
                    `GRU_REG_PERF_BLIT_COUNT:   s_rdata <= perf_blit_count;
                    `GRU_REG_PERF_BLIT_RD_BEAT: s_rdata <= perf_blit_rd_beat;
                    `GRU_REG_PERF_BLIT_WR_BEAT: s_rdata <= perf_blit_wr_beat;
                    `GRU_REG_PERF_BLIT_PIXEL:   s_rdata <= perf_blit_pixel;
                    `GRU_REG_PERF_BLIT_CYCLE:   s_rdata <= perf_blit_cycle;
                    default: begin
                        s_rdata <= 32'd0;
                    end
                endcase
            end else if (r_retire) begin
                s_rvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_bvalid <= 1'b0;
        end else begin
            if (w_enter) begin
                s_bvalid <= 1'b1;
            end else if (b_retire) begin
                s_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            gru_enable <= 1'b0;
            soft_reset_pulse <= 1'b0;
            fb_base <= `GDU_DEFAULT_FB_BASE;
            depth_base <= 32'd0;
            depth_ctrl <= 32'd0;
            tex_base <= 32'd0;
            tex_stride <= 32'd0;
            tex_width <= 16'd0;
            tex_height <= 16'd0;
            tex_ctrl <= 32'd0;
            stride <= `GDU_DEFAULT_STRIDE;
            width <= `GDU_DEFAULT_WIDTH;
            height <= `GDU_DEFAULT_HEIGHT;
            pixel_format <= `GRU_PIXFMT_RGB565;
            cmd_w0_shadow <= 32'd0;
            cmd_w1_shadow <= 32'd0;
            ext_w0_shadow <= 32'd0;
            ext_w1_shadow <= 32'd0;
            ext_w2_shadow <= 32'd0;
            ext_w3_shadow <= 32'd0;
            ext_w4_shadow <= 32'd0;
            cb_base_shadow <= 32'd0;
            cb_word_count_shadow <= 16'd0;
            cb_irq_enable_shadow <= 1'b0;
            cfg_write_reject_pulse <= 1'b0;
            status_w1c_mask <= 32'd0;
            cmd_buffer_exec_pulse <= 1'b0;
            cmd_buffer_status_w1c_mask <= 5'd0;
        end else begin
            soft_reset_pulse <= 1'b0;
            cfg_write_reject_pulse <= 1'b0;
            status_w1c_mask <= 32'd0;
            cmd_buffer_exec_pulse <= 1'b0;
            cmd_buffer_status_w1c_mask <= 5'd0;
            if (w_enter) begin
                case (addr_lsb)
                    `GRU_REG_CTRL: begin
                        gru_enable <= s_wdata[0];
                        soft_reset_pulse <= s_wdata[1];
                    end
                    `GRU_REG_STATUS: begin
                        status_w1c_mask <= s_wdata;
                    end
                    `GRU_REG_FB_BASE: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            fb_base <= s_wdata;
                        end
                    end
                    `GRU_REG_DEPTH_BASE: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            depth_base <= s_wdata;
                        end
                    end
                    `GRU_REG_DEPTH_CTRL: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            depth_ctrl <= s_wdata;
                        end
                    end
                    `GRU_REG_TEX_BASE: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            tex_base <= s_wdata;
                        end
                    end
                    `GRU_REG_TEX_SIZE: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            tex_width <= s_wdata[15:0];
                            tex_height <= s_wdata[31:16];
                        end
                    end
                    `GRU_REG_TEX_STRIDE: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            tex_stride <= s_wdata;
                        end
                    end
                    `GRU_REG_TEX_CTRL: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            tex_ctrl <= s_wdata;
                        end
                    end
                    `GRU_REG_CB_BASE: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            cb_base_shadow <= s_wdata;
                        end
                    end
                    `GRU_REG_CB_WORD_COUNT: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            cb_word_count_shadow <= s_wdata[15:0];
                        end
                    end
                    `GRU_REG_CB_CTRL: begin
                        cb_irq_enable_shadow <= s_wdata[`GRU_CB_CTRL_IRQ_EN_BIT];
                        cmd_buffer_exec_pulse <= s_wdata[`GRU_CB_CTRL_EXEC_BIT];
                    end
                    `GRU_REG_CB_STATUS: begin
                        cmd_buffer_status_w1c_mask <= s_wdata[4:0];
                    end
                    `GRU_REG_STRIDE: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            stride <= s_wdata;
                        end
                    end
                    `GRU_REG_WIDTH_HEIGHT: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            width <= s_wdata[15:0];
                            height <= s_wdata[31:16];
                        end
                    end
                    `GRU_REG_PIXEL_FORMAT: begin
                        if (status_busy) begin
                            cfg_write_reject_pulse <= 1'b1;
                        end else begin
                            pixel_format <= s_wdata[2:0];
                        end
                    end
                    `GRU_REG_CMD_W0: begin
                        cmd_w0_shadow <= s_wdata;
                    end
                    `GRU_REG_CMD_W1: begin
                        cmd_w1_shadow <= s_wdata;
                    end
                    `GRU_REG_EXT_W0: begin
                        ext_w0_shadow <= s_wdata;
                    end
                    `GRU_REG_EXT_W1: begin
                        ext_w1_shadow <= s_wdata;
                    end
                    `GRU_REG_EXT_W2: begin
                        ext_w2_shadow <= s_wdata;
                    end
                    `GRU_REG_EXT_W3: begin
                        ext_w3_shadow <= s_wdata;
                    end
                    `GRU_REG_EXT_W4: begin
                        ext_w4_shadow <= s_wdata;
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    assign cmd_push_valid = (push_hit & s_wdata[0] & ~cmd_fifo_full) |
                            (ext_push_hit & s_wdata[0] & ~cmd_fifo_full & ~ext_cmd_fifo_full);
    assign cmd_push_data = {cmd_w1_shadow, cmd_w0_shadow};
    assign ext_cmd_push_valid = ext_push_hit & s_wdata[0] & ~cmd_fifo_full & ~ext_cmd_fifo_full;
    assign ext_cmd_w0 = ext_w0_shadow;
    assign ext_cmd_w1 = ext_w1_shadow;
    assign ext_cmd_w2 = ext_w2_shadow;
    assign ext_cmd_w3 = ext_w3_shadow;
    assign ext_cmd_w4 = ext_w4_shadow;
    assign cmd_buffer_base = cb_base_shadow;
    assign cmd_buffer_word_count = cb_word_count_shadow;
    assign cmd_buffer_irq_enable = cb_irq_enable_shadow;
endmodule
