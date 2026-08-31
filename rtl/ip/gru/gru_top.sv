`include "../../config.h"
`include "gru_defs.vh"

module gru_top #(
    parameter bit ENABLE_3D = 1'b1
) (
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

    output logic [4:0]  m_axi_arid,
    output logic [31:0] m_axi_araddr,
    output logic [7:0]  m_axi_arlen,
    output logic [2:0]  m_axi_arsize,
    output logic [1:0]  m_axi_arburst,
    output logic        m_axi_arlock,
    output logic [3:0]  m_axi_arcache,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [4:0]  m_axi_rid,
    input  logic [127:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rlast,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    output logic [4:0]  m_axi_awid,
    output logic [31:0] m_axi_awaddr,
    output logic [7:0]  m_axi_awlen,
    output logic [2:0]  m_axi_awsize,
    output logic [1:0]  m_axi_awburst,
    output logic        m_axi_awlock,
    output logic [3:0]  m_axi_awcache,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [127:0] m_axi_wdata,
    output logic [15:0]  m_axi_wstrb,
    output logic        m_axi_wlast,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [4:0]  m_axi_bid,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic        status_axi_error,
    output logic        status_cfg_error,
    output logic        status_engine_stall,

    input  logic        aclk,
    input  logic        aresetn
);
    logic        gru_enable;
    logic        soft_reset_pulse;
    logic [31:0] fb_base;
    logic [31:0] stride;
    logic [15:0] width;
    logic [15:0] height;
    logic [2:0]  pixel_format;
    logic        regs_cmd_push_valid;
    logic [63:0] regs_cmd_push_data;
    logic        regs_ext_cmd_push_valid;
    logic [31:0] regs_ext_cmd_w0;
    logic [31:0] regs_ext_cmd_w1;
    logic [31:0] regs_ext_cmd_w2;
    logic [31:0] regs_ext_cmd_w3;
    logic [31:0] regs_ext_cmd_w4;
    logic        cmd_push_valid;
    logic [63:0] cmd_push_data;
    logic        ext_cmd_push_valid;
    logic [31:0] ext_cmd_w0;
    logic [31:0] ext_cmd_w1;
    logic [31:0] ext_cmd_w2;
    logic [31:0] ext_cmd_w3;
    logic [31:0] ext_cmd_w4;
    logic        fifo_cmd_push_valid;
    logic [63:0] fifo_cmd_push_data;
    logic        fifo_ext_cmd_push_valid;
    logic [31:0] fifo_ext_cmd_w0;
    logic [31:0] fifo_ext_cmd_w1;
    logic [31:0] fifo_ext_cmd_w2;
    logic [31:0] fifo_ext_cmd_w3;
    logic [31:0] fifo_ext_cmd_w4;
    logic        regs_cfg_write_reject_pulse;
    logic [31:0] status_w1c_mask;
    logic [31:0] cmd_buffer_base;
    logic [15:0] cmd_buffer_word_count;
    logic        cmd_buffer_exec_pulse;
    logic        cmd_buffer_irq_enable;
    logic [4:0]  cmd_buffer_status_w1c_mask;

    logic [$clog2(`GRU_CMD_FIFO_DEPTH):0] cmd_level;
    logic        cmd_fifo_full;
    logic        cmd_fifo_empty;
    logic [63:0] cmd_fifo_rd_data;
    logic        cmd_fifo_rd_en;
    logic        ext_cmd_fifo_full;
    logic        ext_cmd_fifo_empty;
    logic [159:0] ext_cmd_fifo_rd_data;
    logic        ext_cmd_fifo_rd_en;
    logic        blit_cmd_full;
    logic        blit_cmd_empty;
    logic [199:0] blit_cmd_rd_data;
    logic        blit_cmd_rd_en;
    logic        blit_cmd_valid;
    logic [`GRU_SEQ_W-1:0] blit_cmd_seq;

    logic [`GRU_SEQ_W-1:0] alloc_seq;
    logic [`GRU_SEQ_W-1:0] next_seq_dbg;
    logic        dispatch_fire;
    logic        blit_dispatch_fire;
    logic        decoder_cfg_error_pulse;
    logic        cmd_drop_fire;
    logic        fence_accept_fire;
    logic        clear_q_wr_en;
    logic        rect_q_wr_en;
    logic        line_q_wr_en;
    logic        glyph_q_wr_en;
    logic        triangle_q_wr_en;
    logic        depth_q_wr_en;
    logic [63:0] clear_q_wr_data;
    logic [63:0] rect_q_wr_data;
    logic [63:0] line_q_wr_data;
    logic [63:0] glyph_q_wr_data;
    logic [`GRU_TRI_CMD_W-1:0] triangle_q_wr_data;
    logic [`GRU_DEPTH_CMD_W-1:0] depth_q_wr_data;

    logic        clear_cmd_full;
    logic        rect_cmd_full;
    logic        line_cmd_full;
    logic        glyph_cmd_full;
    logic        triangle_cmd_full;
    logic        depth_cmd_full;
    logic        clear_cmd_empty;
    logic        rect_cmd_empty;
    logic        line_cmd_empty;
    logic        glyph_cmd_empty;
    logic        triangle_cmd_empty;
    logic        depth_cmd_empty;
    logic [63:0] clear_cmd_rd_data;
    logic [63:0] rect_cmd_rd_data;
    logic [63:0] line_cmd_rd_data;
    logic [63:0] glyph_cmd_rd_data;
    logic        clear_cmd_rd_en;
    logic        rect_cmd_rd_en;
    logic        line_cmd_rd_en;
    logic        glyph_cmd_rd_en;
    logic        triangle_cmd_rd_en;
    logic        depth_cmd_rd_en;
    logic        clear_cmd_ready;
    logic        rect_cmd_ready;
    logic        line_cmd_ready;
    logic        glyph_cmd_ready;
    logic        triangle_cmd_ready;
    logic        depth_cmd_ready;

    logic        clear_span_valid_raw;
    logic        rect_span_valid_raw;
    logic        line_span_valid_raw;
    logic        glyph_span_valid_raw;
    logic        triangle_span_valid_raw;
    logic        clear_span_ready_raw;
    logic        rect_span_ready_raw;
    logic        line_span_ready_raw;
    logic        glyph_span_ready_raw;
    logic        triangle_span_ready_raw;
    logic [63:0] clear_span_data_raw;
    logic [63:0] rect_span_data_raw;
    logic [63:0] line_span_data_raw;
    logic [63:0] glyph_span_data_raw;
    logic [63:0] triangle_span_data_raw;
    logic        clear_span_valid_clip;
    logic        rect_span_valid_clip;
    logic        line_span_valid_clip;
    logic        glyph_span_valid_clip;
    logic        triangle_span_valid_clip;
    logic        clear_span_ready_clip;
    logic        rect_span_ready_clip;
    logic        line_span_ready_clip;
    logic        glyph_span_ready_clip;
    logic        triangle_span_ready_clip;
    logic [63:0] clear_span_data_clip;
    logic [63:0] rect_span_data_clip;
    logic [63:0] line_span_data_clip;
    logic [63:0] glyph_span_data_clip;
    logic [63:0] triangle_span_data_clip;

    logic        clear_span_fifo_full;
    logic        rect_span_fifo_full;
    logic        line_span_fifo_full;
    logic        glyph_span_fifo_full;
    logic        triangle_span_fifo_full;
    logic        clear_span_fifo_empty;
    logic        rect_span_fifo_empty;
    logic        line_span_fifo_empty;
    logic        glyph_span_fifo_empty;
    logic        triangle_span_fifo_empty;
    logic [63:0] clear_span_fifo_rd_data;
    logic [63:0] rect_span_fifo_rd_data;
    logic [63:0] line_span_fifo_rd_data;
    logic [63:0] glyph_span_fifo_rd_data;
    logic [63:0] triangle_span_fifo_rd_data;
    logic        clear_span_fifo_rd_en;
    logic        rect_span_fifo_rd_en;
    logic        line_span_fifo_rd_en;
    logic        glyph_span_fifo_rd_en;
    logic        triangle_span_fifo_rd_en;
    logic [`GRU_TRI_CMD_W-1:0] triangle_cmd_rd_data;
    logic [`GRU_DEPTH_CMD_W-1:0] depth_cmd_rd_data;

    logic [`GRU_SEQ_W-1:0] retire_seq;
    logic [`GRU_SEQ_W-1:0] fence_target_seq;
    logic        arb_writer_valid;
    logic [63:0] arb_writer_data;
    logic        writer_span_ready;
    logic        writer_cmd_done_pulse;
    logic        writer_axi_error_pulse;
    logic        writer_busy;
    wire         sim_aw_allow = 1'b1;
    wire         sim_w_allow  = 1'b1;
    wire         sim_ar_allow = 1'b1;
    wire         sim_r_allow = 1'b1;
    wire         sim_b_allow = 1'b1;
    logic [4:0]  writer_axi_awid;
    logic [31:0] writer_axi_awaddr;
    logic [7:0]  writer_axi_awlen;
    logic [2:0]  writer_axi_awsize;
    logic [1:0]  writer_axi_awburst;
    logic        writer_axi_awlock;
    logic [3:0]  writer_axi_awcache;
    logic [2:0]  writer_axi_awprot;
    logic        writer_axi_awvalid;
    logic [127:0] writer_axi_wdata;
    logic [15:0]  writer_axi_wstrb;
    logic        writer_axi_wlast;
    logic        writer_axi_wvalid;
    logic        writer_axi_bready;
    logic        blit_cmd_ready;
    logic        blit_cmd_done_pulse;
    logic        blit_axi_error_pulse;
    logic        blit_busy;
    // blit_bus_* are the blit engine's native 128-bit master OUTPUT nets
    // (they feed the GRU m_axi_* outputs / write mux below).  blit_s_* carry
    // the slave-side responses back into the engine (the old
    // axi_width_adapter_32_to_128 used to bridge these; the blit engine is now
    // native 128-bit, so they wire straight to the top ports with the same
    // sim_/use_blit_write gating the adapter applied).
    logic        blit_s_arready;
    logic [4:0]  blit_s_rid;
    logic [127:0] blit_s_rdata;
    logic [1:0]  blit_s_rresp;
    logic        blit_s_rlast;
    logic        blit_s_rvalid;
    logic        blit_s_awready;
    logic        blit_s_wready;
    logic [4:0]  blit_s_bid;
    logic [1:0]  blit_s_bresp;
    logic        blit_s_bvalid;
    logic [4:0]  blit_bus_arid;
    logic [31:0] blit_bus_araddr;
    logic [7:0]  blit_bus_arlen;
    logic [2:0]  blit_bus_arsize;
    logic [1:0]  blit_bus_arburst;
    logic        blit_bus_arlock;
    logic [3:0]  blit_bus_arcache;
    logic [2:0]  blit_bus_arprot;
    logic        blit_bus_arvalid;
    logic        blit_bus_rready;
    logic [4:0]  blit_bus_awid;
    logic [31:0] blit_bus_awaddr;
    logic [7:0]  blit_bus_awlen;
    logic [2:0]  blit_bus_awsize;
    logic [1:0]  blit_bus_awburst;
    logic        blit_bus_awlock;
    logic [3:0]  blit_bus_awcache;
    logic [2:0]  blit_bus_awprot;
    logic        blit_bus_awvalid;
    logic [127:0] blit_bus_wdata;
    logic [15:0]  blit_bus_wstrb;
    logic        blit_bus_wlast;
    logic        blit_bus_wvalid;
    logic        blit_bus_bready;
    logic        use_blit_write;

    // Phase-4 perf counters (internal nets; the regs file exposes them as a
    // read-only MMIO window).  No external port change to gru_top.
    logic [31:0] depth_base;
    logic [31:0] depth_ctrl;
    logic [31:0] tex_base;
    logic [31:0] tex_stride;
    logic [15:0] tex_width;
    logic [15:0] tex_height;
    logic [31:0] tex_ctrl;
    logic        depth_state_enable;
    logic        depth_state_write_enable;
    logic        depth_state_lequal;
    logic [31:0] wcb_span_in_count, wcb_pixel_in_count, wcb_aw_txn_count;
    logic [31:0] wcb_beat_out_count, wcb_full_beat_count, wcb_partial_beat_count, wcb_flush_count;
    logic [31:0] cum_blit_count, cum_rd_beat_count, cum_wr_beat_count, cum_pixel_count, cum_cycle_count;

    logic status_done;
    logic status_fence_done;
    logic status_busy;
    logic status_busy_q;
    logic core_clr;
    logic fence_pending;
    logic cmd_head_valid;
    logic [`GRU_OPCODE_W-1:0] cmd_head_opcode;
    logic cmd_head_is_render;
    logic cmd_head_is_2d_render;
    logic cmd_head_is_triangle;
    logic cmd_head_is_textured_triangle;
    logic cmd_head_is_depth;
    logic cmd_head_is_blit;
    logic cmd_head_is_fence;
    logic cmd_head_illegal;
    logic cmd_head_needs_ext;
    logic render_cfg_valid;
    logic cmd_cfg_error;
    logic depth_cfg_valid;
    logic texture_cfg_valid;
    logic fence_complete;
    logic engine_stall_event;
    logic decoder_cmd_valid;
    logic depth_cmd_valid;
    logic [`GRU_SEQ_W-1:0] depth_cmd_seq;
    logic depth_cmd_done_pulse;
    logic depth_axi_error_pulse;
    logic depth_busy;
    logic [4:0]  depth_axi_arid;
    logic [31:0] depth_axi_araddr;
    logic [7:0]  depth_axi_arlen;
    logic [2:0]  depth_axi_arsize;
    logic [1:0]  depth_axi_arburst;
    logic        depth_axi_arlock;
    logic [3:0]  depth_axi_arcache;
    logic [2:0]  depth_axi_arprot;
    logic        depth_axi_arvalid;
    logic        depth_axi_rready;
    logic [4:0]  depth_axi_awid;
    logic [31:0] depth_axi_awaddr;
    logic [7:0]  depth_axi_awlen;
    logic [2:0]  depth_axi_awsize;
    logic [1:0]  depth_axi_awburst;
    logic        depth_axi_awlock;
    logic [3:0]  depth_axi_awcache;
    logic [2:0]  depth_axi_awprot;
    logic        depth_axi_awvalid;
    logic [127:0] depth_axi_wdata;
    logic [15:0]  depth_axi_wstrb;
    logic        depth_axi_wlast;
    logic        depth_axi_wvalid;
    logic        depth_axi_bready;
    logic        use_depth_rw;
    logic [4:0]  texture_axi_arid;
    logic [31:0] texture_axi_araddr;
    logic [7:0]  texture_axi_arlen;
    logic [2:0]  texture_axi_arsize;
    logic [1:0]  texture_axi_arburst;
    logic        texture_axi_arlock;
    logic [3:0]  texture_axi_arcache;
    logic [2:0]  texture_axi_arprot;
    logic        texture_axi_arvalid;
    logic        texture_axi_rready;
    logic        use_texture_read;
    logic        cmd_buffer_busy;
    logic        cmd_buffer_done;
    logic        cmd_buffer_cfg_error;
    logic        cmd_buffer_axi_error;
    logic        cmd_buffer_present_done;
    logic        cmd_buffer_present_pulse;
    logic        cmd_buffer_done_pulse;
    logic        cmd_buffer_cfg_error_pulse;
    logic        cmd_buffer_axi_error_pulse;
    logic        fetch_start_pulse;
    logic        fetch_busy;
    logic        fetch_done_pulse;
    logic        fetch_cfg_error_pulse;
    logic        fetch_axi_error_pulse;
    logic        fetch_word_valid;
    logic        fetch_word_ready;
    logic [31:0] fetch_word_data;
    logic [4:0]  cmd_fetch_axi_arid;
    logic [31:0] cmd_fetch_axi_araddr;
    logic [7:0]  cmd_fetch_axi_arlen;
    logic [2:0]  cmd_fetch_axi_arsize;
    logic [1:0]  cmd_fetch_axi_arburst;
    logic        cmd_fetch_axi_arlock;
    logic [3:0]  cmd_fetch_axi_arcache;
    logic [2:0]  cmd_fetch_axi_arprot;
    logic        cmd_fetch_axi_arvalid;
    logic        cmd_fetch_axi_rready;
    logic        use_cmd_fetch_read;

    function automatic logic signed [15:0] signext_x9(input logic [8:0] value);
        begin
            signext_x9 = $signed({{7{value[8]}}, value});
        end
    endfunction

    function automatic logic signed [15:0] signext_y9(input logic [8:0] value);
        begin
            signext_y9 = $signed({{7{value[8]}}, value});
        end
    endfunction

    assign core_clr = soft_reset_pulse | ~gru_enable;
    assign cmd_head_valid = ~cmd_fifo_empty & gru_enable;
    assign cmd_head_opcode = cmd_fifo_rd_data[`GRU_CMD0_OPCODE_MSB:`GRU_CMD0_OPCODE_LSB];
    assign cmd_head_is_2d_render = (cmd_head_opcode == `GRU_OP_CLEAR) ||
                                   (cmd_head_opcode == `GRU_OP_FILL_RECT) ||
                                   (cmd_head_opcode == `GRU_OP_DRAW_LINE) ||
                                   (cmd_head_opcode == `GRU_OP_DRAW_GLYPH);
    // Production GRU is Flat-Lite only.  Unsupported legacy 3D opcodes fall
    // through cmd_head_illegal, are consumed with CFG_ERROR, and cannot stall
    // the retire/Fence path.
    assign cmd_head_is_textured_triangle = 1'b0;
    assign cmd_head_is_triangle = ENABLE_3D &&
                                  (cmd_head_opcode == `GRU_OP_TRIANGLE_FLAT);
    assign cmd_head_is_depth = 1'b0;
    assign cmd_head_is_render = cmd_head_is_2d_render | cmd_head_is_triangle;
    assign cmd_head_is_blit = (cmd_head_opcode == `GRU_OP_BLIT);
    assign cmd_head_is_fence = (cmd_head_opcode == `GRU_OP_FENCE);
    assign cmd_head_needs_ext = (cmd_head_opcode == `GRU_OP_BLIT) ||
                                (cmd_head_opcode == `GRU_OP_TRIANGLE_FLAT) ||
                                (cmd_head_opcode == `GRU_OP_TRIANGLE_GOURAUD) ||
                                (cmd_head_opcode == `GRU_OP_TRIANGLE_Z) ||
                                (cmd_head_opcode == `GRU_OP_TRIANGLE_TEXTURED) ||
                                (cmd_head_opcode == `GRU_OP_TRIANGLE_TEXTURED_PC);
    assign cmd_head_illegal = cmd_head_valid & ~cmd_head_is_render & ~cmd_head_is_blit & ~cmd_head_is_fence & ~cmd_head_is_depth;
    assign render_cfg_valid = (width != 16'd0) &&
                              (height != 16'd0) &&
                              (stride != 32'd0) &&
                              (fb_base[1:0] == 2'b00) &&
                              (pixel_format == `GRU_PIXFMT_RGB565) &&
                              (stride >= {15'd0, width, 1'b0});
    assign depth_cfg_valid = render_cfg_valid &&
                             (depth_base[1:0] == 2'b00) &&
                             (depth_base != 32'd0);
    assign texture_cfg_valid = (tex_base[1:0] == 2'b00) &&
                               (tex_base != 32'd0) &&
                               (tex_width != 16'd0) &&
                               (tex_height != 16'd0) &&
                               (tex_stride != 32'd0) &&
                               (tex_ctrl[`GRU_TEX_CTRL_FORMAT_MSB:`GRU_TEX_CTRL_FORMAT_LSB] == `GRU_PIXFMT_RGB565) &&
                               (tex_stride >= {15'd0, tex_width, 1'b0});
    assign cmd_cfg_error = cmd_head_valid & ~fence_pending &
                           (cmd_head_illegal |
                            ((cmd_head_is_render | cmd_head_is_blit) & ~render_cfg_valid) |
                            (cmd_head_is_textured_triangle & ~texture_cfg_valid) |
                            (cmd_head_is_depth & ~depth_cfg_valid) |
                            (cmd_head_needs_ext & ext_cmd_fifo_empty));
    assign fence_accept_fire = cmd_head_valid & ~fence_pending & cmd_head_is_fence;
    assign decoder_cmd_valid = cmd_head_valid & ~fence_pending & cmd_head_is_2d_render & render_cfg_valid;
    assign blit_dispatch_fire = cmd_head_valid & ~fence_pending & cmd_head_is_blit &
                                render_cfg_valid & ~ext_cmd_fifo_empty & ~blit_cmd_full;
    assign triangle_q_wr_en = cmd_head_valid & ~fence_pending & cmd_head_is_triangle &
                              render_cfg_valid &
                              ~ext_cmd_fifo_empty & ~triangle_cmd_full;
    assign depth_q_wr_en = cmd_head_valid & ~fence_pending & cmd_head_is_depth &
                           depth_cfg_valid &
                           ((cmd_head_opcode == `GRU_OP_CLEAR_DEPTH) || ~ext_cmd_fifo_empty) &
                           ~depth_cmd_full;
    assign engine_stall_event = (clear_span_valid_raw & ~clear_span_ready_raw) |
                                (rect_span_valid_raw & ~rect_span_ready_raw) |
                                (line_span_valid_raw & ~line_span_ready_raw) |
                                (glyph_span_valid_raw & ~glyph_span_ready_raw) |
                                (triangle_span_valid_raw & ~triangle_span_ready_raw);
    // fence_complete retires once every command dispatched up to (and including)
    // this fence's target seq has fully committed:
    //   * retire_seq == fence_target_seq  -> each blit/render op with seq<target
    //                                        has emitted its done_pulse (which
    //                                        only fires after the engine's last
    //                                        AXI B response, i.e. after commit)
    //   * *_cmd_empty / *_span_fifo_empty -> the render engines have drained
    //                                        their dispatched work
    //   * *_cmd_ready                     -> each render engine is idle
    //   * ~writer_busy / ~blit_busy       -> both write engines are idle
    // NOTE: ext_cmd_fifo_empty is intentionally NOT required.  A driver may
    // pipeline later fenced batches (push their blit + ext-cmds) before this
    // fence retires; those later blits cannot dispatch (blit_dispatch_fire is
    // gated by ~fence_pending), so their ext-cmds correctly remain queued.
    // Requiring ext_cmd_fifo_empty here deadlocked that pipelined case: the
    // fence waited for ext-cmds that could only drain after the fence cleared.
    assign fence_complete = fence_pending &&
                            (retire_seq == fence_target_seq) &&
                            clear_cmd_empty && rect_cmd_empty && line_cmd_empty && glyph_cmd_empty &&
                            triangle_cmd_empty && depth_cmd_empty && blit_cmd_empty &&
                            clear_span_fifo_empty && rect_span_fifo_empty &&
                            line_span_fifo_empty && glyph_span_fifo_empty && triangle_span_fifo_empty &&
                            clear_cmd_ready && rect_cmd_ready && line_cmd_ready && glyph_cmd_ready && triangle_cmd_ready &&
                            depth_cmd_ready &&
                            ~writer_busy && ~blit_busy && ~depth_busy;
    assign status_busy = ~cmd_fifo_empty |
                         ~ext_cmd_fifo_empty | ~blit_cmd_empty |
                         ~clear_cmd_empty | ~rect_cmd_empty | ~line_cmd_empty | ~glyph_cmd_empty | ~triangle_cmd_empty | ~depth_cmd_empty |
                         ~clear_span_fifo_empty | ~rect_span_fifo_empty | ~line_span_fifo_empty |
                         ~glyph_span_fifo_empty | ~triangle_span_fifo_empty |
                         ~clear_cmd_ready | ~rect_cmd_ready | ~line_cmd_ready | ~glyph_cmd_ready | ~triangle_cmd_ready | ~depth_cmd_ready |
                         fence_pending |
                         writer_busy | blit_busy | depth_busy | cmd_buffer_busy;
    assign depth_state_enable = depth_ctrl[`GRU_DEPTH_CTRL_ENABLE_BIT];
    assign depth_state_write_enable = depth_ctrl[`GRU_DEPTH_CTRL_WRITE_BIT];
    assign depth_state_lequal = depth_ctrl[`GRU_DEPTH_CTRL_LEQUAL_BIT];

    gru_regs u_gru_regs (
        .s_awvalid      (s_awvalid),
        .s_awready      (s_awready),
        .s_awaddr       (s_awaddr),
        .s_awid         (s_awid),
        .s_awlen        (s_awlen),
        .s_awsize       (s_awsize),
        .s_awburst      (s_awburst),
        .s_awlock       (s_awlock),
        .s_awcache      (s_awcache),
        .s_awprot       (s_awprot),
        .s_wvalid       (s_wvalid),
        .s_wready       (s_wready),
        .s_wdata        (s_wdata),
        .s_wstrb        (s_wstrb),
        .s_wlast        (s_wlast),
        .s_bvalid       (s_bvalid),
        .s_bready       (s_bready),
        .s_bid          (s_bid),
        .s_bresp        (s_bresp),
        .s_arvalid      (s_arvalid),
        .s_arready      (s_arready),
        .s_araddr       (s_araddr),
        .s_arid         (s_arid),
        .s_arlen        (s_arlen),
        .s_arsize       (s_arsize),
        .s_arburst      (s_arburst),
        .s_arlock       (s_arlock),
        .s_arcache      (s_arcache),
        .s_arprot       (s_arprot),
        .s_rvalid       (s_rvalid),
        .s_rready       (s_rready),
        .s_rdata        (s_rdata),
        .s_rid          (s_rid),
        .s_rresp        (s_rresp),
        .s_rlast        (s_rlast),
        .status_busy    (status_busy),
        .status_done    (status_done),
        .status_axi_error(status_axi_error),
        .status_cfg_error(status_cfg_error),
        .status_fence_done(status_fence_done),
        .status_engine_stall(status_engine_stall),
        .cmd_level      (cmd_level),
        .cmd_fifo_full  (cmd_fifo_full),
        .cmd_fifo_empty (cmd_fifo_empty),
        .ext_cmd_fifo_full(ext_cmd_fifo_full),
        .cmd_buffer_busy(cmd_buffer_busy),
        .cmd_buffer_done(cmd_buffer_done),
        .cmd_buffer_cfg_error(cmd_buffer_cfg_error),
        .cmd_buffer_axi_error(cmd_buffer_axi_error),
        .cmd_buffer_present_done(cmd_buffer_present_done),
        .gru_enable     (gru_enable),
        .soft_reset_pulse(soft_reset_pulse),
        .fb_base        (fb_base),
        .depth_ctrl     (depth_ctrl),
        .tex_base       (tex_base),
        .tex_stride     (tex_stride),
        .tex_width      (tex_width),
        .tex_height     (tex_height),
        .tex_ctrl       (tex_ctrl),
        .stride         (stride),
        .width          (width),
        .height         (height),
        .pixel_format   (pixel_format),
        .cfg_write_reject_pulse(regs_cfg_write_reject_pulse),
        .status_w1c_mask(status_w1c_mask),
        .cmd_push_valid (regs_cmd_push_valid),
        .cmd_push_data  (regs_cmd_push_data),
        .ext_cmd_push_valid(regs_ext_cmd_push_valid),
        .ext_cmd_w0     (regs_ext_cmd_w0),
        .ext_cmd_w1     (regs_ext_cmd_w1),
        .ext_cmd_w2     (regs_ext_cmd_w2),
        .ext_cmd_w3     (regs_ext_cmd_w3),
        .ext_cmd_w4     (regs_ext_cmd_w4),
        .cmd_buffer_base(cmd_buffer_base),
        .cmd_buffer_word_count(cmd_buffer_word_count),
        .cmd_buffer_exec_pulse(cmd_buffer_exec_pulse),
        .cmd_buffer_irq_enable(cmd_buffer_irq_enable),
        .cmd_buffer_status_w1c_mask(cmd_buffer_status_w1c_mask),
        .depth_base     (depth_base),
        .perf_wcb_span_in  (wcb_span_in_count),
        .perf_wcb_pix_in   (wcb_pixel_in_count),
        .perf_wcb_aw_txn   (wcb_aw_txn_count),
        .perf_wcb_beat_out (wcb_beat_out_count),
        .perf_wcb_full_beat(wcb_full_beat_count),
        .perf_wcb_partial  (wcb_partial_beat_count),
        .perf_wcb_flush    (wcb_flush_count),
        .perf_blit_count   (cum_blit_count),
        .perf_blit_rd_beat (cum_rd_beat_count),
        .perf_blit_wr_beat (cum_wr_beat_count),
        .perf_blit_pixel   (cum_pixel_count),
        .perf_blit_cycle   (cum_cycle_count),
        .aclk           (aclk),
        .aresetn        (aresetn)
    );

    gru_cmd_buffer_ctrl u_gru_cmd_buffer_ctrl (
        .clk                 (aclk),
        .rstn                (aresetn),
        .clr                 (core_clr),
        .exec_start_pulse    (cmd_buffer_exec_pulse),
        .exec_base_addr      (cmd_buffer_base),
        .exec_word_count     (cmd_buffer_word_count),
        .fetch_start_pulse   (fetch_start_pulse),
        .fetch_base_addr     (),
        .fetch_word_count    (),
        .fetch_busy          (fetch_busy),
        .fetch_done_pulse    (fetch_done_pulse),
        .fetch_cfg_error_pulse(fetch_cfg_error_pulse),
        .fetch_axi_error_pulse(fetch_axi_error_pulse),
        .fetch_word_valid    (fetch_word_valid),
        .fetch_word_ready    (fetch_word_ready),
        .fetch_word_data     (fetch_word_data),
        .cmd_fifo_full       (cmd_fifo_full),
        .ext_cmd_fifo_full   (ext_cmd_fifo_full),
        .cmd_push_valid      (fifo_cmd_push_valid),
        .cmd_push_data       (fifo_cmd_push_data),
        .ext_cmd_push_valid  (fifo_ext_cmd_push_valid),
        .ext_cmd_w0          (fifo_ext_cmd_w0),
        .ext_cmd_w1          (fifo_ext_cmd_w1),
        .ext_cmd_w2          (fifo_ext_cmd_w2),
        .ext_cmd_w3          (fifo_ext_cmd_w3),
        .ext_cmd_w4          (fifo_ext_cmd_w4),
        .present_pulse       (cmd_buffer_present_pulse),
        .cb_busy             (cmd_buffer_busy),
        .cb_done_pulse       (cmd_buffer_done_pulse),
        .cb_cfg_error_pulse  (cmd_buffer_cfg_error_pulse),
        .cb_axi_error_pulse  (cmd_buffer_axi_error_pulse)
    );

    gru_cmd_fetch u_gru_cmd_fetch (
        .clk            (aclk),
        .rstn           (aresetn),
        .clr            (core_clr),
        .start_pulse    (fetch_start_pulse),
        .start_addr     (cmd_buffer_base),
        .start_word_count(cmd_buffer_word_count),
        .busy           (fetch_busy),
        .done_pulse     (fetch_done_pulse),
        .cfg_error_pulse(fetch_cfg_error_pulse),
        .axi_error_pulse(fetch_axi_error_pulse),
        .word_valid     (fetch_word_valid),
        .word_ready     (fetch_word_ready),
        .word_data      (fetch_word_data),
        .m_axi_arid     (cmd_fetch_axi_arid),
        .m_axi_araddr   (cmd_fetch_axi_araddr),
        .m_axi_arlen    (cmd_fetch_axi_arlen),
        .m_axi_arsize   (cmd_fetch_axi_arsize),
        .m_axi_arburst  (cmd_fetch_axi_arburst),
        .m_axi_arlock   (cmd_fetch_axi_arlock),
        .m_axi_arcache  (cmd_fetch_axi_arcache),
        .m_axi_arprot   (cmd_fetch_axi_arprot),
        .m_axi_arvalid  (cmd_fetch_axi_arvalid),
        .m_axi_arready  (m_axi_arready & sim_ar_allow & use_cmd_fetch_read),
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid & sim_r_allow & use_cmd_fetch_read),
        .m_axi_rready   (cmd_fetch_axi_rready)
    );

    assign cmd_push_valid = regs_cmd_push_valid | fifo_cmd_push_valid;
    assign cmd_push_data = regs_cmd_push_valid ? regs_cmd_push_data : fifo_cmd_push_data;
    assign ext_cmd_push_valid = regs_ext_cmd_push_valid | fifo_ext_cmd_push_valid;
    assign ext_cmd_w0 = regs_ext_cmd_push_valid ? regs_ext_cmd_w0 : fifo_ext_cmd_w0;
    assign ext_cmd_w1 = regs_ext_cmd_push_valid ? regs_ext_cmd_w1 : fifo_ext_cmd_w1;
    assign ext_cmd_w2 = regs_ext_cmd_push_valid ? regs_ext_cmd_w2 : fifo_ext_cmd_w2;
    assign ext_cmd_w3 = regs_ext_cmd_push_valid ? regs_ext_cmd_w3 : fifo_ext_cmd_w3;
    assign ext_cmd_w4 = regs_ext_cmd_push_valid ? regs_ext_cmd_w4 : fifo_ext_cmd_w4;

    gru_fifo #(
        .WIDTH(`GRU_CMD_W),
        .DEPTH(`GRU_CMD_FIFO_DEPTH)
    ) u_cmd_fifo (
        .clk     (aclk),
        .rstn    (aresetn),
        .clr     (core_clr),
        .wr_en   (cmd_push_valid),
        .wr_data (cmd_push_data),
        .rd_en   (cmd_fifo_rd_en),
        .rd_data (cmd_fifo_rd_data),
        .full    (cmd_fifo_full),
        .empty   (cmd_fifo_empty),
        .level   (cmd_level)
    );

    gru_fifo #(
        .WIDTH(160),
        .DEPTH(`GRU_CMD_FIFO_DEPTH)
    ) u_ext_cmd_fifo (
        .clk     (aclk),
        .rstn    (aresetn),
        .clr     (core_clr),
        .wr_en   (ext_cmd_push_valid),
        .wr_data ({ext_cmd_w4, ext_cmd_w3, ext_cmd_w2, ext_cmd_w1, ext_cmd_w0}),
        .rd_en   (ext_cmd_fifo_rd_en),
        .rd_data (ext_cmd_fifo_rd_data),
        .full    (ext_cmd_fifo_full),
        .empty   (ext_cmd_fifo_empty),
        .level   ()
    );

    gru_seq_tracker u_gru_seq_tracker (
        .clk         (aclk),
        .rstn        (aresetn),
        .clr         (core_clr),
        .alloc_fire  (dispatch_fire | blit_dispatch_fire | triangle_q_wr_en | depth_q_wr_en),
        .alloc_seq   (alloc_seq),
        .next_seq_dbg(next_seq_dbg)
    );

    gru_cmd_decoder u_gru_cmd_decoder (
        .cmd_valid      (decoder_cmd_valid),
        .cmd_data       (cmd_fifo_rd_data),
        .alloc_seq      (alloc_seq),
        .clear_q_full   (clear_cmd_full),
        .rect_q_full    (rect_cmd_full),
        .line_q_full    (line_cmd_full),
        .glyph_q_full   (glyph_cmd_full),
        .triangle_q_full(triangle_cmd_full),
        .dispatch_fire  (dispatch_fire),
        .cfg_error_pulse(decoder_cfg_error_pulse),
        .clear_q_wr_en  (clear_q_wr_en),
        .rect_q_wr_en   (rect_q_wr_en),
        .line_q_wr_en   (line_q_wr_en),
        .glyph_q_wr_en  (glyph_q_wr_en),
        .triangle_q_wr_en(),
        .clear_q_wr_data(clear_q_wr_data),
        .rect_q_wr_data (rect_q_wr_data),
        .line_q_wr_data (line_q_wr_data),
        .glyph_q_wr_data(glyph_q_wr_data),
        .triangle_q_wr_data()
    );
    assign cmd_drop_fire = cmd_cfg_error;
    assign cmd_fifo_rd_en = dispatch_fire | blit_dispatch_fire | triangle_q_wr_en | depth_q_wr_en | cmd_drop_fire | fence_accept_fire;
    assign ext_cmd_fifo_rd_en = blit_dispatch_fire |
                                triangle_q_wr_en |
                                (depth_q_wr_en & (cmd_head_opcode == `GRU_OP_TRIANGLE_Z)) |
                                (cmd_drop_fire & cmd_head_needs_ext & ~ext_cmd_fifo_empty);

    gru_fifo #(
        .WIDTH(200),
        .DEPTH(`GRU_CMD_FIFO_DEPTH)
    ) u_blit_cmd_fifo (
        .clk     (aclk),
        .rstn    (aresetn),
        .clr     (core_clr),
        .wr_en   (blit_dispatch_fire),
        .wr_data ({29'd0,
                   alloc_seq,
                   ext_cmd_fifo_rd_data[130:128],
                   cmd_fifo_rd_data[63:48],
                   cmd_fifo_rd_data[47:32],
                   ext_cmd_fifo_rd_data[127:112],
                   ext_cmd_fifo_rd_data[111:96],
                   ext_cmd_fifo_rd_data[95:80],
                   ext_cmd_fifo_rd_data[79:64],
                   ext_cmd_fifo_rd_data[63:32],
                   ext_cmd_fifo_rd_data[31:0]}),
        .rd_en   (blit_cmd_rd_en),
        .rd_data (blit_cmd_rd_data),
        .full    (blit_cmd_full),
        .empty   (blit_cmd_empty),
        .level   ()
    );
    assign blit_cmd_seq = blit_cmd_rd_data[170:163];
    assign blit_cmd_valid = ~blit_cmd_empty & (blit_cmd_seq == retire_seq);
    assign blit_cmd_rd_en = blit_cmd_valid & blit_cmd_ready;

    gru_fifo #(.WIDTH(`GRU_ENGINE_CMD_W), .DEPTH(`GRU_ENGINE_FIFO_DEPTH)) u_clear_cmd_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(clear_q_wr_en), .wr_data(clear_q_wr_data),
        .rd_en(clear_cmd_rd_en), .rd_data(clear_cmd_rd_data), .full(clear_cmd_full), .empty(clear_cmd_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_ENGINE_CMD_W), .DEPTH(`GRU_ENGINE_FIFO_DEPTH)) u_rect_cmd_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(rect_q_wr_en), .wr_data(rect_q_wr_data),
        .rd_en(rect_cmd_rd_en), .rd_data(rect_cmd_rd_data), .full(rect_cmd_full), .empty(rect_cmd_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_ENGINE_CMD_W), .DEPTH(`GRU_ENGINE_FIFO_DEPTH)) u_line_cmd_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(line_q_wr_en), .wr_data(line_q_wr_data),
        .rd_en(line_cmd_rd_en), .rd_data(line_cmd_rd_data), .full(line_cmd_full), .empty(line_cmd_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_ENGINE_CMD_W), .DEPTH(`GRU_ENGINE_FIFO_DEPTH)) u_glyph_cmd_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(glyph_q_wr_en), .wr_data(glyph_q_wr_data),
        .rd_en(glyph_cmd_rd_en), .rd_data(glyph_cmd_rd_data), .full(glyph_cmd_full), .empty(glyph_cmd_empty), .level()
    );
    always_comb begin
        triangle_q_wr_data = '0;
        triangle_q_wr_data[`GRU_TRI_CMD_SEQ_MSB:`GRU_TRI_CMD_SEQ_LSB] = alloc_seq;
        triangle_q_wr_data[`GRU_TRI_CMD_OPCODE_MSB:`GRU_TRI_CMD_OPCODE_LSB] = cmd_head_opcode;
        triangle_q_wr_data[`GRU_TRI_CMD_X0_MSB:`GRU_TRI_CMD_X0_LSB] =
            signext_x9(cmd_fifo_rd_data[`GRU_CMD0_X0_MSB:`GRU_CMD0_X0_LSB]);
        triangle_q_wr_data[`GRU_TRI_CMD_Y0_MSB:`GRU_TRI_CMD_Y0_LSB] =
            signext_y9({cmd_fifo_rd_data[32 + `GRU_CMD1_Y0_HI_BIT], cmd_fifo_rd_data[`GRU_CMD0_Y0_MSB:`GRU_CMD0_Y0_LSB]});
        triangle_q_wr_data[`GRU_TRI_CMD_X1_MSB:`GRU_TRI_CMD_X1_LSB] =
            signext_x9(cmd_fifo_rd_data[32 + `GRU_CMD1_X1_MSB:32 + `GRU_CMD1_X1_LSB]);
        triangle_q_wr_data[`GRU_TRI_CMD_Y1_MSB:`GRU_TRI_CMD_Y1_LSB] =
            signext_y9({cmd_fifo_rd_data[32 + `GRU_CMD1_Y1_HI_BIT], cmd_fifo_rd_data[32 + `GRU_CMD1_Y1_MSB:32 + `GRU_CMD1_Y1_LSB]});
        triangle_q_wr_data[`GRU_TRI_CMD_X2_MSB:`GRU_TRI_CMD_X2_LSB] = signext_x9(ext_cmd_fifo_rd_data[8:0]);
        triangle_q_wr_data[`GRU_TRI_CMD_Y2_MSB:`GRU_TRI_CMD_Y2_LSB] = signext_y9({ext_cmd_fifo_rd_data[17], ext_cmd_fifo_rd_data[16:9]});

        case (cmd_head_opcode)
            `GRU_OP_TRIANGLE_FLAT: begin
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB] =
                    {8'd0, cmd_fifo_rd_data[`GRU_CMD0_COLOR_MSB:`GRU_CMD0_COLOR_LSB]};
            end
            `GRU_OP_TRIANGLE_GOURAUD: begin
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB] = ext_cmd_fifo_rd_data[47:32];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR1_LO_MSB:`GRU_TRI_CMD_ATTR1_LO_LSB] = ext_cmd_fifo_rd_data[79:64];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR2_LO_MSB:`GRU_TRI_CMD_ATTR2_LO_LSB] = ext_cmd_fifo_rd_data[111:96];
            end
            `GRU_OP_TRIANGLE_TEXTURED: begin
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB] = ext_cmd_fifo_rd_data[47:32];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR0_HI_MSB:`GRU_TRI_CMD_ATTR0_HI_LSB] = ext_cmd_fifo_rd_data[63:48];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR1_LO_MSB:`GRU_TRI_CMD_ATTR1_LO_LSB] = ext_cmd_fifo_rd_data[79:64];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR1_HI_MSB:`GRU_TRI_CMD_ATTR1_HI_LSB] = ext_cmd_fifo_rd_data[95:80];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR2_LO_MSB:`GRU_TRI_CMD_ATTR2_LO_LSB] = ext_cmd_fifo_rd_data[111:96];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR2_HI_MSB:`GRU_TRI_CMD_ATTR2_HI_LSB] = ext_cmd_fifo_rd_data[127:112];
            end
            `GRU_OP_TRIANGLE_TEXTURED_PC: begin
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR0_LO_MSB:`GRU_TRI_CMD_ATTR0_LO_LSB] = ext_cmd_fifo_rd_data[47:32];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR0_HI_MSB:`GRU_TRI_CMD_ATTR0_HI_LSB] = ext_cmd_fifo_rd_data[63:48];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR1_LO_MSB:`GRU_TRI_CMD_ATTR1_LO_LSB] = ext_cmd_fifo_rd_data[79:64];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR1_HI_MSB:`GRU_TRI_CMD_ATTR1_HI_LSB] = ext_cmd_fifo_rd_data[95:80];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR2_LO_MSB:`GRU_TRI_CMD_ATTR2_LO_LSB] = ext_cmd_fifo_rd_data[111:96];
                triangle_q_wr_data[`GRU_TRI_CMD_ATTR2_HI_MSB:`GRU_TRI_CMD_ATTR2_HI_LSB] = ext_cmd_fifo_rd_data[127:112];
                triangle_q_wr_data[`GRU_TRI_CMD_EXTRA0_MSB:`GRU_TRI_CMD_EXTRA0_LSB] =
                    {cmd_fifo_rd_data[32 + 31:32 + 26],
                     cmd_fifo_rd_data[`GRU_CMD0_FONT_MSB:`GRU_CMD0_FONT_LSB],
                     cmd_fifo_rd_data[`GRU_CMD0_COLOR_MSB:`GRU_CMD0_COLOR_LSB]};
                triangle_q_wr_data[`GRU_TRI_CMD_EXTRA1_MSB:`GRU_TRI_CMD_EXTRA1_LSB] = ext_cmd_fifo_rd_data[143:128];
                triangle_q_wr_data[`GRU_TRI_CMD_EXTRA2_MSB:`GRU_TRI_CMD_EXTRA2_LSB] = ext_cmd_fifo_rd_data[159:144];
            end
            default: begin
            end
        endcase
    end

    gru_fifo #(.WIDTH(`GRU_TRI_CMD_W), .DEPTH(`GRU_ENGINE_FIFO_DEPTH)) u_triangle_cmd_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(triangle_q_wr_en),
        .wr_data(triangle_q_wr_data),
        .rd_en(triangle_cmd_rd_en), .rd_data(triangle_cmd_rd_data), .full(triangle_cmd_full), .empty(triangle_cmd_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_DEPTH_CMD_W), .DEPTH(`GRU_ENGINE_FIFO_DEPTH)) u_depth_cmd_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(depth_q_wr_en),
        .wr_data({
            21'd0,
            depth_state_lequal,
            depth_state_write_enable,
            depth_state_enable,
            (cmd_head_opcode == `GRU_OP_TRIANGLE_Z) ? ext_cmd_fifo_rd_data[79:64] : cmd_fifo_rd_data[47:32],
            // Z1/Z0 ext slices must follow the cfg_driver packing
            // pack_triangle_ext_w1_z(z0,z1) = {z1,z0} -> ext_w1[15:0]=z0, [31:16]=z1
            (cmd_head_opcode == `GRU_OP_TRIANGLE_Z) ? ext_cmd_fifo_rd_data[63:48] : 16'd0,
            (cmd_head_opcode == `GRU_OP_TRIANGLE_Z) ? ext_cmd_fifo_rd_data[47:32] : 16'd0,
            (cmd_head_opcode == `GRU_OP_TRIANGLE_Z) ? ext_cmd_fifo_rd_data[16:9] : 8'd0,
            (cmd_head_opcode == `GRU_OP_TRIANGLE_Z) ? ext_cmd_fifo_rd_data[8:0] : 9'd0,
            cmd_fifo_rd_data[48:41],
            cmd_fifo_rd_data[40:32],
            cmd_fifo_rd_data[31:24],
            cmd_fifo_rd_data[23:15],
            cmd_fifo_rd_data[12:5],
            cmd_head_opcode,
            alloc_seq
        }),
        .rd_en(depth_cmd_rd_en), .rd_data(depth_cmd_rd_data), .full(depth_cmd_full), .empty(depth_cmd_empty), .level()
    );

    assign clear_cmd_rd_en = ~clear_cmd_empty & clear_cmd_ready;
    assign rect_cmd_rd_en  = ~rect_cmd_empty & rect_cmd_ready;
    assign line_cmd_rd_en  = ~line_cmd_empty & line_cmd_ready;
    assign glyph_cmd_rd_en = ~glyph_cmd_empty & glyph_cmd_ready;
    assign triangle_cmd_rd_en = ~triangle_cmd_empty & triangle_cmd_ready;
    assign depth_cmd_seq = depth_cmd_rd_data[`GRU_DEPTH_CMD_SEQ_MSB:`GRU_DEPTH_CMD_SEQ_LSB];
    assign depth_cmd_valid = ~depth_cmd_empty & (depth_cmd_seq == retire_seq);
    assign depth_cmd_rd_en = depth_cmd_valid & depth_cmd_ready;

    gru_clear_engine u_gru_clear_engine (
        .clk       (aclk),
        .rstn      (aresetn),
        .clr       (core_clr),
        .frame_w   (width),
        .frame_h   (height),
        .cmd_valid (~clear_cmd_empty),
        .cmd_ready (clear_cmd_ready),
        .cmd_data  (clear_cmd_rd_data),
        .span_valid(clear_span_valid_raw),
        .span_ready(clear_span_ready_raw),
        .span_data (clear_span_data_raw)
    );
    gru_rect_engine u_gru_rect_engine (
        .clk       (aclk),
        .rstn      (aresetn),
        .clr       (core_clr),
        .frame_w   (width),
        .frame_h   (height),
        .cmd_valid (~rect_cmd_empty),
        .cmd_ready (rect_cmd_ready),
        .cmd_data  (rect_cmd_rd_data),
        .span_valid(rect_span_valid_raw),
        .span_ready(rect_span_ready_raw),
        .span_data (rect_span_data_raw)
    );
    gru_line_engine u_gru_line_engine (
        .clk       (aclk),
        .rstn      (aresetn),
        .clr       (core_clr),
        .frame_w   (width),
        .frame_h   (height),
        .cmd_valid (~line_cmd_empty),
        .cmd_ready (line_cmd_ready),
        .cmd_data  (line_cmd_rd_data),
        .span_valid(line_span_valid_raw),
        .span_ready(line_span_ready_raw),
        .span_data (line_span_data_raw)
    );
    gru_glyph_engine u_gru_glyph_engine (
        .clk       (aclk),
        .rstn      (aresetn),
        .clr       (core_clr),
        .frame_w   (width),
        .frame_h   (height),
        .cmd_valid (~glyph_cmd_empty),
        .cmd_ready (glyph_cmd_ready),
        .cmd_data  (glyph_cmd_rd_data),
        .span_valid(glyph_span_valid_raw),
        .span_ready(glyph_span_ready_raw),
        .span_data (glyph_span_data_raw)
    );
    generate
        if (1'b0) begin : gen_full_3d_engines
            gru_triangle_engine u_gru_triangle_engine (
                .clk       (aclk),
                .rstn      (aresetn),
                .clr       (core_clr),
                .frame_w   (width),
                .frame_h   (height),
                .tex_base   (tex_base),
                .tex_stride (tex_stride),
                .tex_width  (tex_width),
                .tex_height (tex_height),
                .tex_format (tex_ctrl[`GRU_TEX_CTRL_FORMAT_MSB:`GRU_TEX_CTRL_FORMAT_LSB]),
                .tex_wrap_mode(tex_ctrl[`GRU_TEX_CTRL_WRAP_BIT]),
                .cmd_valid (~triangle_cmd_empty),
                .cmd_ready (triangle_cmd_ready),
                .cmd_data  (triangle_cmd_rd_data),
                .span_valid(triangle_span_valid_raw),
                .span_ready(triangle_span_ready_raw),
                .span_data (triangle_span_data_raw),
                .m_axi_arid    (texture_axi_arid),
                .m_axi_araddr  (texture_axi_araddr),
                .m_axi_arlen   (texture_axi_arlen),
                .m_axi_arsize  (texture_axi_arsize),
                .m_axi_arburst (texture_axi_arburst),
                .m_axi_arlock  (texture_axi_arlock),
                .m_axi_arcache (texture_axi_arcache),
                .m_axi_arprot  (texture_axi_arprot),
                .m_axi_arvalid (texture_axi_arvalid),
                .m_axi_arready (m_axi_arready & sim_ar_allow & use_texture_read),
                .m_axi_rid     (m_axi_rid),
                .m_axi_rdata   (m_axi_rdata),
                .m_axi_rresp   (m_axi_rresp),
                .m_axi_rlast   (m_axi_rlast),
                .m_axi_rvalid  (m_axi_rvalid & sim_r_allow & use_texture_read),
                .m_axi_rready  (texture_axi_rready)
            );
            gru_depth_rw u_gru_depth_rw (
                .clk            (aclk),
                .rstn           (aresetn),
                .clr            (core_clr),
                .fb_base        (fb_base),
                .depth_base     (depth_base),
                .stride         (stride),
                .frame_w        (width),
                .frame_h        (height),
                .cmd_valid      (depth_cmd_valid),
                .cmd_ready      (depth_cmd_ready),
                .cmd_data       (depth_cmd_rd_data),
                .cmd_done_pulse (depth_cmd_done_pulse),
                .axi_error_pulse(depth_axi_error_pulse),
                .depth_busy     (depth_busy),
                .m_axi_arid     (depth_axi_arid),
                .m_axi_araddr   (depth_axi_araddr),
                .m_axi_arlen    (depth_axi_arlen),
                .m_axi_arsize   (depth_axi_arsize),
                .m_axi_arburst  (depth_axi_arburst),
                .m_axi_arlock   (depth_axi_arlock),
                .m_axi_arcache  (depth_axi_arcache),
                .m_axi_arprot   (depth_axi_arprot),
                .m_axi_arvalid  (depth_axi_arvalid),
                .m_axi_arready  (m_axi_arready & sim_ar_allow & use_depth_rw),
                .m_axi_rid      (m_axi_rid),
                .m_axi_rdata    (m_axi_rdata),
                .m_axi_rresp    (m_axi_rresp),
                .m_axi_rlast    (m_axi_rlast),
                .m_axi_rvalid   (m_axi_rvalid & sim_r_allow & use_depth_rw),
                .m_axi_rready   (depth_axi_rready),
                .m_axi_awid     (depth_axi_awid),
                .m_axi_awaddr   (depth_axi_awaddr),
                .m_axi_awlen    (depth_axi_awlen),
                .m_axi_awsize   (depth_axi_awsize),
                .m_axi_awburst  (depth_axi_awburst),
                .m_axi_awlock   (depth_axi_awlock),
                .m_axi_awcache  (depth_axi_awcache),
                .m_axi_awprot   (depth_axi_awprot),
                .m_axi_awvalid  (depth_axi_awvalid),
                .m_axi_awready  (m_axi_awready & sim_aw_allow & use_depth_rw),
                .m_axi_wdata    (depth_axi_wdata),
                .m_axi_wstrb    (depth_axi_wstrb),
                .m_axi_wlast    (depth_axi_wlast),
                .m_axi_wvalid   (depth_axi_wvalid),
                .m_axi_wready   (m_axi_wready & sim_w_allow & use_depth_rw),
                .m_axi_bid      (m_axi_bid),
                .m_axi_bresp    (m_axi_bresp),
                .m_axi_bvalid   (m_axi_bvalid & sim_b_allow & use_depth_rw),
                .m_axi_bready   (depth_axi_bready)
            );
        end else if (ENABLE_3D) begin : gen_lite_3d_engine
            gru_lite_triangle_engine u_gru_lite_triangle_engine (
                .clk            (aclk),
                .rstn           (aresetn),
                .clr            (core_clr),
                .frame_w        (width),
                .frame_h        (height),
                .cmd_valid      (~triangle_cmd_empty),
                .cmd_ready      (triangle_cmd_ready),
                .cmd_data       (triangle_cmd_rd_data),
                .retire_seq     (retire_seq),
                .span_valid     (triangle_span_valid_raw),
                .span_ready     (triangle_span_ready_raw),
                .span_data      (triangle_span_data_raw),
                .cmd_done_pulse (),
                .cfg_error_pulse()
            );
            assign texture_axi_arid = '0;
            assign texture_axi_araddr = '0;
            assign texture_axi_arlen = '0;
            assign texture_axi_arsize = '0;
            assign texture_axi_arburst = '0;
            assign texture_axi_arlock = 1'b0;
            assign texture_axi_arcache = '0;
            assign texture_axi_arprot = '0;
            assign texture_axi_arvalid = 1'b0;
            assign texture_axi_rready = 1'b0;
            assign depth_cmd_ready = 1'b1;
            assign depth_cmd_done_pulse = 1'b0;
            assign depth_axi_error_pulse = 1'b0;
            assign depth_busy = 1'b0;
            assign depth_axi_arid = '0;
            assign depth_axi_araddr = '0;
            assign depth_axi_arlen = '0;
            assign depth_axi_arsize = '0;
            assign depth_axi_arburst = '0;
            assign depth_axi_arlock = 1'b0;
            assign depth_axi_arcache = '0;
            assign depth_axi_arprot = '0;
            assign depth_axi_arvalid = 1'b0;
            assign depth_axi_rready = 1'b0;
            assign depth_axi_awid = '0;
            assign depth_axi_awaddr = '0;
            assign depth_axi_awlen = '0;
            assign depth_axi_awsize = '0;
            assign depth_axi_awburst = '0;
            assign depth_axi_awlock = 1'b0;
            assign depth_axi_awcache = '0;
            assign depth_axi_awprot = '0;
            assign depth_axi_awvalid = 1'b0;
            assign depth_axi_wdata = '0;
            assign depth_axi_wstrb = '0;
            assign depth_axi_wlast = 1'b0;
            assign depth_axi_wvalid = 1'b0;
            assign depth_axi_bready = 1'b0;
        end else begin : gen_no_3d_engines
            assign triangle_cmd_ready = 1'b1;
            assign triangle_span_valid_raw = 1'b0;
            assign triangle_span_data_raw = '0;
            assign texture_axi_arid = '0;
            assign texture_axi_araddr = '0;
            assign texture_axi_arlen = '0;
            assign texture_axi_arsize = '0;
            assign texture_axi_arburst = '0;
            assign texture_axi_arlock = 1'b0;
            assign texture_axi_arcache = '0;
            assign texture_axi_arprot = '0;
            assign texture_axi_arvalid = 1'b0;
            assign texture_axi_rready = 1'b0;

            assign depth_cmd_ready = 1'b1;
            assign depth_cmd_done_pulse = 1'b0;
            assign depth_axi_error_pulse = 1'b0;
            assign depth_busy = 1'b0;
            assign depth_axi_arid = '0;
            assign depth_axi_araddr = '0;
            assign depth_axi_arlen = '0;
            assign depth_axi_arsize = '0;
            assign depth_axi_arburst = '0;
            assign depth_axi_arlock = 1'b0;
            assign depth_axi_arcache = '0;
            assign depth_axi_arprot = '0;
            assign depth_axi_arvalid = 1'b0;
            assign depth_axi_rready = 1'b0;
            assign depth_axi_awid = '0;
            assign depth_axi_awaddr = '0;
            assign depth_axi_awlen = '0;
            assign depth_axi_awsize = '0;
            assign depth_axi_awburst = '0;
            assign depth_axi_awlock = 1'b0;
            assign depth_axi_awcache = '0;
            assign depth_axi_awprot = '0;
            assign depth_axi_awvalid = 1'b0;
            assign depth_axi_wdata = '0;
            assign depth_axi_wstrb = '0;
            assign depth_axi_wlast = 1'b0;
            assign depth_axi_wvalid = 1'b0;
            assign depth_axi_bready = 1'b0;
        end
    endgenerate

    gru_span_clipper u_clear_span_clipper (
        .in_valid (clear_span_valid_raw),
        .in_ready (clear_span_ready_raw),
        .in_span  (clear_span_data_raw),
        .out_valid(clear_span_valid_clip),
        .out_ready(clear_span_ready_clip),
        .out_span (clear_span_data_clip),
        .frame_w  (width),
        .frame_h  (height)
    );
    gru_span_clipper u_rect_span_clipper (
        .in_valid (rect_span_valid_raw),
        .in_ready (rect_span_ready_raw),
        .in_span  (rect_span_data_raw),
        .out_valid(rect_span_valid_clip),
        .out_ready(rect_span_ready_clip),
        .out_span (rect_span_data_clip),
        .frame_w  (width),
        .frame_h  (height)
    );
    gru_span_clipper u_line_span_clipper (
        .in_valid (line_span_valid_raw),
        .in_ready (line_span_ready_raw),
        .in_span  (line_span_data_raw),
        .out_valid(line_span_valid_clip),
        .out_ready(line_span_ready_clip),
        .out_span (line_span_data_clip),
        .frame_w  (width),
        .frame_h  (height)
    );
    gru_span_clipper u_glyph_span_clipper (
        .in_valid (glyph_span_valid_raw),
        .in_ready (glyph_span_ready_raw),
        .in_span  (glyph_span_data_raw),
        .out_valid(glyph_span_valid_clip),
        .out_ready(glyph_span_ready_clip),
        .out_span (glyph_span_data_clip),
        .frame_w  (width),
        .frame_h  (height)
    );
    gru_span_clipper u_triangle_span_clipper (
        .in_valid (triangle_span_valid_raw),
        .in_ready (triangle_span_ready_raw),
        .in_span  (triangle_span_data_raw),
        .out_valid(triangle_span_valid_clip),
        .out_ready(triangle_span_ready_clip),
        .out_span (triangle_span_data_clip),
        .frame_w  (width),
        .frame_h  (height)
    );

    assign clear_span_ready_clip = ~clear_span_fifo_full;
    assign rect_span_ready_clip  = ~rect_span_fifo_full;
    assign line_span_ready_clip  = ~line_span_fifo_full;
    assign glyph_span_ready_clip = ~glyph_span_fifo_full;
    assign triangle_span_ready_clip = ~triangle_span_fifo_full;

    gru_fifo #(.WIDTH(`GRU_SPAN_W), .DEPTH(`GRU_SPAN_FIFO_DEPTH)) u_clear_span_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(clear_span_valid_clip & clear_span_ready_clip), .wr_data(clear_span_data_clip),
        .rd_en(clear_span_fifo_rd_en), .rd_data(clear_span_fifo_rd_data), .full(clear_span_fifo_full), .empty(clear_span_fifo_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_SPAN_W), .DEPTH(`GRU_SPAN_FIFO_DEPTH)) u_rect_span_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(rect_span_valid_clip & rect_span_ready_clip), .wr_data(rect_span_data_clip),
        .rd_en(rect_span_fifo_rd_en), .rd_data(rect_span_fifo_rd_data), .full(rect_span_fifo_full), .empty(rect_span_fifo_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_SPAN_W), .DEPTH(`GRU_SPAN_FIFO_DEPTH)) u_line_span_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(line_span_valid_clip & line_span_ready_clip), .wr_data(line_span_data_clip),
        .rd_en(line_span_fifo_rd_en), .rd_data(line_span_fifo_rd_data), .full(line_span_fifo_full), .empty(line_span_fifo_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_SPAN_W), .DEPTH(`GRU_SPAN_FIFO_DEPTH)) u_glyph_span_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(glyph_span_valid_clip & glyph_span_ready_clip), .wr_data(glyph_span_data_clip),
        .rd_en(glyph_span_fifo_rd_en), .rd_data(glyph_span_fifo_rd_data), .full(glyph_span_fifo_full), .empty(glyph_span_fifo_empty), .level()
    );
    gru_fifo #(.WIDTH(`GRU_SPAN_W), .DEPTH(`GRU_SPAN_FIFO_DEPTH)) u_triangle_span_fifo (
        .clk(aclk), .rstn(aresetn), .clr(core_clr), .wr_en(triangle_span_valid_clip & triangle_span_ready_clip), .wr_data(triangle_span_data_clip),
        .rd_en(triangle_span_fifo_rd_en), .rd_data(triangle_span_fifo_rd_data), .full(triangle_span_fifo_full), .empty(triangle_span_fifo_empty), .level()
    );

    gru_span_arbiter u_gru_span_arbiter (
        .retire_seq  (retire_seq),
        .writer_ready(writer_span_ready),
        .clear_valid (~clear_span_fifo_empty),
        .clear_data  (clear_span_fifo_rd_data),
        .clear_rd_en (clear_span_fifo_rd_en),
        .rect_valid  (~rect_span_fifo_empty),
        .rect_data   (rect_span_fifo_rd_data),
        .rect_rd_en  (rect_span_fifo_rd_en),
        .line_valid  (~line_span_fifo_empty),
        .line_data   (line_span_fifo_rd_data),
        .line_rd_en  (line_span_fifo_rd_en),
        .glyph_valid (~glyph_span_fifo_empty),
        .glyph_data  (glyph_span_fifo_rd_data),
        .glyph_rd_en (glyph_span_fifo_rd_en),
        .triangle_valid(~triangle_span_fifo_empty),
        .triangle_data (triangle_span_fifo_rd_data),
        .triangle_rd_en(triangle_span_fifo_rd_en),
        .writer_valid(arb_writer_valid),
        .writer_data (arb_writer_data)
    );

    // blit_s_* slave-side responses into the (now native 128-bit) blit engine,
    // with the same gating the removed u_blit_axi_adapter applied on its
    // master side.
    assign blit_s_arready = m_axi_arready & sim_ar_allow & ~use_depth_rw & ~use_cmd_fetch_read & ~use_texture_read;
    assign blit_s_rid     = m_axi_rid;
    assign blit_s_rdata   = m_axi_rdata;
    assign blit_s_rresp   = m_axi_rresp;
    assign blit_s_rlast   = m_axi_rlast;
    assign blit_s_rvalid  = m_axi_rvalid & sim_r_allow & ~use_depth_rw & ~use_cmd_fetch_read & ~use_texture_read;
    assign blit_s_awready = m_axi_awready & sim_aw_allow & use_blit_write;
    assign blit_s_wready  = m_axi_wready & sim_w_allow & use_blit_write;
    assign blit_s_bid     = m_axi_bid;
    assign blit_s_bresp   = m_axi_bresp;
    assign blit_s_bvalid  = m_axi_bvalid & use_blit_write & sim_b_allow;

    assign use_depth_rw = depth_axi_arvalid | depth_axi_rready |
                          depth_axi_awvalid | depth_axi_wvalid | depth_axi_bready;
    assign use_cmd_fetch_read = ~use_depth_rw & (cmd_fetch_axi_arvalid | cmd_fetch_axi_rready);
    assign use_texture_read = ~use_depth_rw & ~use_cmd_fetch_read & (texture_axi_arvalid | texture_axi_rready);
    assign use_blit_write = blit_bus_awvalid | blit_bus_wvalid | blit_bus_bready;
    assign m_axi_arid    = use_depth_rw ? depth_axi_arid : (use_cmd_fetch_read ? cmd_fetch_axi_arid : (use_texture_read ? texture_axi_arid : blit_bus_arid));
    assign m_axi_araddr  = use_depth_rw ? depth_axi_araddr : (use_cmd_fetch_read ? cmd_fetch_axi_araddr : (use_texture_read ? texture_axi_araddr : blit_bus_araddr));
    assign m_axi_arlen   = use_depth_rw ? depth_axi_arlen : (use_cmd_fetch_read ? cmd_fetch_axi_arlen : (use_texture_read ? texture_axi_arlen : blit_bus_arlen));
    assign m_axi_arsize  = use_depth_rw ? depth_axi_arsize : (use_cmd_fetch_read ? cmd_fetch_axi_arsize : (use_texture_read ? texture_axi_arsize : blit_bus_arsize));
    assign m_axi_arburst = use_depth_rw ? depth_axi_arburst : (use_cmd_fetch_read ? cmd_fetch_axi_arburst : (use_texture_read ? texture_axi_arburst : blit_bus_arburst));
    assign m_axi_arlock  = use_depth_rw ? depth_axi_arlock : (use_cmd_fetch_read ? cmd_fetch_axi_arlock : (use_texture_read ? texture_axi_arlock : blit_bus_arlock));
    assign m_axi_arcache = use_depth_rw ? depth_axi_arcache : (use_cmd_fetch_read ? cmd_fetch_axi_arcache : (use_texture_read ? texture_axi_arcache : blit_bus_arcache));
    assign m_axi_arprot  = use_depth_rw ? depth_axi_arprot : (use_cmd_fetch_read ? cmd_fetch_axi_arprot : (use_texture_read ? texture_axi_arprot : blit_bus_arprot));
    assign m_axi_arvalid = (use_depth_rw ? depth_axi_arvalid : (use_cmd_fetch_read ? cmd_fetch_axi_arvalid : (use_texture_read ? texture_axi_arvalid : blit_bus_arvalid))) & sim_ar_allow;
    assign m_axi_rready  = use_depth_rw ? (depth_axi_rready & sim_r_allow) : (use_cmd_fetch_read ? (cmd_fetch_axi_rready & sim_r_allow) : (use_texture_read ? (texture_axi_rready & sim_r_allow) : (blit_bus_rready & sim_r_allow)));
    assign m_axi_awid    = use_depth_rw ? depth_axi_awid : (use_blit_write ? blit_bus_awid : writer_axi_awid);
    assign m_axi_awaddr  = use_depth_rw ? depth_axi_awaddr : (use_blit_write ? blit_bus_awaddr : writer_axi_awaddr);
    assign m_axi_awlen   = use_depth_rw ? depth_axi_awlen : (use_blit_write ? blit_bus_awlen : writer_axi_awlen);
    assign m_axi_awsize  = use_depth_rw ? depth_axi_awsize : (use_blit_write ? blit_bus_awsize : writer_axi_awsize);
    assign m_axi_awburst = use_depth_rw ? depth_axi_awburst : (use_blit_write ? blit_bus_awburst : writer_axi_awburst);
    assign m_axi_awlock  = use_depth_rw ? depth_axi_awlock : (use_blit_write ? blit_bus_awlock : writer_axi_awlock);
    assign m_axi_awcache = use_depth_rw ? depth_axi_awcache : (use_blit_write ? blit_bus_awcache : writer_axi_awcache);
    assign m_axi_awprot  = use_depth_rw ? depth_axi_awprot : (use_blit_write ? blit_bus_awprot : writer_axi_awprot);
    assign m_axi_awvalid = (use_depth_rw ? depth_axi_awvalid : (use_blit_write ? blit_bus_awvalid : writer_axi_awvalid)) & sim_aw_allow;
    assign m_axi_wdata   = use_depth_rw ? depth_axi_wdata : (use_blit_write ? blit_bus_wdata : writer_axi_wdata);
    assign m_axi_wstrb   = use_depth_rw ? depth_axi_wstrb : (use_blit_write ? blit_bus_wstrb : writer_axi_wstrb);
    assign m_axi_wlast   = use_depth_rw ? depth_axi_wlast : (use_blit_write ? blit_bus_wlast : writer_axi_wlast);
    assign m_axi_wvalid  = (use_depth_rw ? depth_axi_wvalid : (use_blit_write ? blit_bus_wvalid : writer_axi_wvalid)) & sim_w_allow;
    assign m_axi_bready  = use_depth_rw ? (depth_axi_bready & sim_b_allow) : (use_blit_write ? (blit_bus_bready & sim_b_allow) : writer_axi_bready);

    gru_axi_writer #(
        .LINE_BEATS(`GRU_WCB_LINE_BEATS)
    ) u_gru_axi_writer (
        .clk           (aclk),
        .rstn          (aresetn),
        .clr           (core_clr),
        .fb_base       (fb_base),
        .stride        (stride),
        .span_valid    (arb_writer_valid),
        .span_ready    (writer_span_ready),
        .span_data     (arb_writer_data),
        .cmd_done_pulse(writer_cmd_done_pulse),
        .axi_error_pulse(writer_axi_error_pulse),
        .writer_busy   (writer_busy),
        .m_axi_awid    (writer_axi_awid),
        .m_axi_awaddr  (writer_axi_awaddr),
        .m_axi_awlen   (writer_axi_awlen),
        .m_axi_awsize  (writer_axi_awsize),
        .m_axi_awburst (writer_axi_awburst),
        .m_axi_awlock  (writer_axi_awlock),
        .m_axi_awcache (writer_axi_awcache),
        .m_axi_awprot  (writer_axi_awprot),
        .m_axi_awvalid (writer_axi_awvalid),
        .m_axi_awready (m_axi_awready & sim_aw_allow & ~use_blit_write & ~use_depth_rw),
        .m_axi_wdata   (writer_axi_wdata),
        .m_axi_wstrb   (writer_axi_wstrb),
        .m_axi_wlast   (writer_axi_wlast),
        .m_axi_wvalid  (writer_axi_wvalid),
        .m_axi_wready  (m_axi_wready & sim_w_allow & ~use_blit_write & ~use_depth_rw),
        .m_axi_bid     (m_axi_bid),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid & ~use_blit_write & ~use_depth_rw),
        .m_axi_bready  (writer_axi_bready),
        .wcb_span_in_count    (wcb_span_in_count),
        .wcb_pixel_in_count   (wcb_pixel_in_count),
        .wcb_aw_txn_count     (wcb_aw_txn_count),
        .wcb_beat_out_count   (wcb_beat_out_count),
        .wcb_full_beat_count  (wcb_full_beat_count),
        .wcb_partial_beat_count(wcb_partial_beat_count),
        .wcb_flush_count      (wcb_flush_count)
    );

    gru_blit_engine u_gru_blit_engine (
        .clk           (aclk),
        .rstn          (aresetn),
        .clr           (core_clr),
        .fb_base       (fb_base),
        .dst_stride    (stride),
        .frame_w       (width),
        .frame_h       (height),
        .cmd_valid     (blit_cmd_valid),
        .cmd_ready     (blit_cmd_ready),
        .cmd_data      (blit_cmd_rd_data),
        .cmd_done_pulse(blit_cmd_done_pulse),
        .axi_error_pulse(blit_axi_error_pulse),
        .blit_busy     (blit_busy),
        .m_axi_arid    (blit_bus_arid),
        .m_axi_araddr  (blit_bus_araddr),
        .m_axi_arlen   (blit_bus_arlen),
        .m_axi_arsize  (blit_bus_arsize),
        .m_axi_arburst (blit_bus_arburst),
        .m_axi_arlock  (blit_bus_arlock),
        .m_axi_arcache (blit_bus_arcache),
        .m_axi_arprot  (blit_bus_arprot),
        .m_axi_arvalid (blit_bus_arvalid),
        .m_axi_arready (blit_s_arready),
        .m_axi_rid     (blit_s_rid),
        .m_axi_rdata   (blit_s_rdata),
        .m_axi_rresp   (blit_s_rresp),
        .m_axi_rlast   (blit_s_rlast),
        .m_axi_rvalid  (blit_s_rvalid),
        .m_axi_rready  (blit_bus_rready),
        .m_axi_awid    (blit_bus_awid),
        .m_axi_awaddr  (blit_bus_awaddr),
        .m_axi_awlen   (blit_bus_awlen),
        .m_axi_awsize  (blit_bus_awsize),
        .m_axi_awburst (blit_bus_awburst),
        .m_axi_awlock  (blit_bus_awlock),
        .m_axi_awcache (blit_bus_awcache),
        .m_axi_awprot  (blit_bus_awprot),
        .m_axi_awvalid (blit_bus_awvalid),
        .m_axi_awready (blit_s_awready),
        .m_axi_wdata   (blit_bus_wdata),
        .m_axi_wstrb   (blit_bus_wstrb),
        .m_axi_wlast   (blit_bus_wlast),
        .m_axi_wvalid  (blit_bus_wvalid),
        .m_axi_wready  (blit_s_wready),
        .m_axi_bid     (blit_s_bid),
        .m_axi_bresp   (blit_s_bresp),
        .m_axi_bvalid  (blit_s_bvalid),
        .m_axi_bready  (blit_bus_bready),
        .cum_blit_count    (cum_blit_count),
        .cum_rd_beat_count (cum_rd_beat_count),
        .cum_wr_beat_count (cum_wr_beat_count),
        .cum_pixel_count   (cum_pixel_count),
        .cum_cycle_count   (cum_cycle_count)
    );

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            retire_seq <= '0;
            fence_target_seq <= '0;
            fence_pending <= 1'b0;
            status_done <= 1'b0;
            status_fence_done <= 1'b0;
            status_axi_error <= 1'b0;
            status_cfg_error <= 1'b0;
            status_engine_stall <= 1'b0;
            status_busy_q <= 1'b0;
            cmd_buffer_done <= 1'b0;
            cmd_buffer_cfg_error <= 1'b0;
            cmd_buffer_axi_error <= 1'b0;
            cmd_buffer_present_done <= 1'b0;
        end else if (core_clr) begin
            retire_seq <= '0;
            fence_target_seq <= '0;
            fence_pending <= 1'b0;
            status_done <= 1'b0;
            status_fence_done <= 1'b0;
            status_axi_error <= 1'b0;
            status_cfg_error <= 1'b0;
            status_engine_stall <= 1'b0;
            status_busy_q <= 1'b0;
            cmd_buffer_done <= 1'b0;
            cmd_buffer_cfg_error <= 1'b0;
            cmd_buffer_axi_error <= 1'b0;
            cmd_buffer_present_done <= 1'b0;
        end else begin
            status_busy_q <= status_busy;
            if (cmd_push_valid || cmd_buffer_exec_pulse) begin
                status_done <= 1'b0;
                cmd_buffer_done <= 1'b0;
                if (cmd_buffer_exec_pulse) begin
                    cmd_buffer_present_done <= 1'b0;
                end
            end
            if (cmd_buffer_status_w1c_mask[`GRU_CB_STATUS_DONE_BIT]) begin
                cmd_buffer_done <= 1'b0;
            end
            if (cmd_buffer_status_w1c_mask[`GRU_CB_STATUS_CFG_ERROR_BIT]) begin
                cmd_buffer_cfg_error <= 1'b0;
            end
            if (cmd_buffer_status_w1c_mask[`GRU_CB_STATUS_AXI_ERROR_BIT]) begin
                cmd_buffer_axi_error <= 1'b0;
            end
            if (cmd_buffer_status_w1c_mask[`GRU_CB_STATUS_PRESENT_BIT]) begin
                cmd_buffer_present_done <= 1'b0;
            end
            if (status_w1c_mask[`GRU_STATUS_DONE]) begin
                status_done <= 1'b0;
            end
            if (status_w1c_mask[`GRU_STATUS_FENCE_DONE]) begin
                status_fence_done <= 1'b0;
            end
            if (status_w1c_mask[`GRU_STATUS_AXI_ERROR]) begin
                status_axi_error <= 1'b0;
            end
            if (status_w1c_mask[`GRU_STATUS_CFG_ERROR]) begin
                status_cfg_error <= 1'b0;
            end
            if (status_w1c_mask[`GRU_STATUS_ENGINE_STALL]) begin
                status_engine_stall <= 1'b0;
            end
            if (decoder_cfg_error_pulse) begin
                status_cfg_error <= 1'b1;
            end
            if (cmd_drop_fire) begin
                status_cfg_error <= 1'b1;
            end
            if (regs_cfg_write_reject_pulse) begin
                status_cfg_error <= 1'b1;
            end
            if (cmd_buffer_cfg_error_pulse) begin
                status_cfg_error <= 1'b1;
                cmd_buffer_cfg_error <= 1'b1;
            end
            if (writer_axi_error_pulse || blit_axi_error_pulse || depth_axi_error_pulse) begin
                status_axi_error <= 1'b1;
            end
            if (cmd_buffer_axi_error_pulse) begin
                status_axi_error <= 1'b1;
                cmd_buffer_axi_error <= 1'b1;
            end
            if (cmd_buffer_done_pulse) begin
                cmd_buffer_done <= 1'b1;
            end
            if (cmd_buffer_present_pulse) begin
                cmd_buffer_present_done <= 1'b1;
            end
            if (engine_stall_event) begin
                status_engine_stall <= 1'b1;
            end
            if (fence_accept_fire) begin
                fence_pending <= 1'b1;
                fence_target_seq <= alloc_seq;
            end
            if (fence_complete) begin
                fence_pending <= 1'b0;
                status_fence_done <= 1'b1;
            end
            if (writer_cmd_done_pulse || blit_cmd_done_pulse || depth_cmd_done_pulse) begin
                retire_seq <= retire_seq + 1'b1;
            end
            if (status_busy_q && !status_busy) begin
                status_done <= 1'b1;
            end
        end
    end
endmodule
