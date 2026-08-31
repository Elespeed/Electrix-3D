`include "gru_defs.vh"

// =============================================================================
// gru_blit_engine — native 128-bit RGB565 blit/copy engine.
//
// Phase-2 rewrite (doc/03_phase2_blit_engine_native128.md).  The engine is now a
// native 128-bit AXI4 master (8 pixels/beat).  Source/destination lane alignment
// is handled internally, so the blit path no longer depends on the external
// axi_width_adapter_32_to_128 that the old 32-bit engine needed.
//
// Datapath: per row, two phases.
//   READ  — read every 128-bit src beat covering the row's active pixels into a
//           combinational line buffer (line_buf).  The beat containing src_x
//           (the "lead-in" beat) is read in full; its lower lanes are simply
//           never consumed.  Reads issue in bursts capped at 16 beats / 4 KB.
//   WRITE — emit dst beats (first partial / middle full / last partial) by
//           barrel-selecting pixels out of line_buf.  Because stride and both FB
//           bases are 16-byte aligned, src_lane_start = src_x%8 and
//           dst_lane_start = dst_x%8 are constant for the whole blit, so the
//           src/dst framing offset is fixed; the pixel stream between the two
//           phases is just the contiguous `width` active pixels.
//
// The command interface (cmd_data layout, cmd_done_pulse, axi_error_pulse,
// blit_busy) is unchanged from the 32-bit engine — gru_top, the cfg driver, the
// reference model and all existing testbenches are unaffected.
// =============================================================================

module gru_blit_engine (
    input  logic        clk,
    input  logic        rstn,
    input  logic        clr,
    input  logic [31:0] fb_base,
    input  logic [31:0] dst_stride,
    input  logic [15:0] frame_w,
    input  logic [15:0] frame_h,

    input  logic        cmd_valid,
    output logic        cmd_ready,
    input  logic [199:0] cmd_data,

    output logic        cmd_done_pulse,
    output logic        axi_error_pulse,
    output logic        blit_busy,

    // -------------------------------------------------------------------------
    // Phase-4 cumulative performance counters (reset only on `!rstn`; survive
    // soft-reset).  These are session-lifetime totals across ALL blits, exposed
    // via the GRU perf MMIO window.  The per-blit counters below
    // (blit_read_burst_count etc.) are unaffected and stay internal for TB use.
    // -------------------------------------------------------------------------
    output logic [31:0] cum_blit_count,       // blit commands accepted
    output logic [31:0] cum_rd_beat_count,    // 128-bit read beats received
    output logic [31:0] cum_wr_beat_count,    // 128-bit write beats sent
    output logic [31:0] cum_pixel_count,      // destination pixels written
    output logic [31:0] cum_cycle_count,      // cycles spent busy (cycle_running)

    // Native 128-bit AXI4 master (read + write channels share the bus).
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
    output logic [15:0] m_axi_wstrb,
    output logic        m_axi_wlast,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [4:0]  m_axi_bid,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready
);
    //==========================================================================
    // Geometry constants
    //==========================================================================
    // 128-bit beat = 16 bytes = 8 RGB565 pixels = 8 lanes.
    localparam int BEAT_BYTES    = 16;
    localparam int BEAT_PIXELS   = 8;
    localparam int MAX_BURST_BEATS = 16;   // ARLEN/AWLEN cap (len = beats-1)
    // Max src beats in one row: src_lane_start (<=7) + width (<=320) -> <=41.
    localparam int LINE_BUF_BEATS = 64;

    //==========================================================================
    // State encoding
    //==========================================================================
    typedef enum logic [3:0] {
        BLIT_IDLE     = 4'd0,
        BLIT_ROW_INIT = 4'd1,
        BLIT_RD_AR    = 4'd2,
        BLIT_RD_R     = 4'd3,
        BLIT_WR_AW    = 4'd4,
        BLIT_WR_W     = 4'd5,
        BLIT_WR_B     = 4'd6,
        BLIT_DONE     = 4'd7
    } blit_state_t;

    blit_state_t state;

    //==========================================================================
    // Command latch (constants for the whole blit)
    //==========================================================================
    logic [31:0] src_base_addr;
    logic [31:0] src_stride_bytes;
    logic [15:0] src_x_base;
    logic [15:0] src_y_base;
    logic [15:0] dst_x_base;
    logic [15:0] dst_y_base;
    logic [15:0] width_eff;          // clipped width (pixels)
    logic [15:0] height_eff;         // clipped height (rows)
    logic [2:0]  src_pixel_format;
    logic [`GRU_SEQ_W-1:0] seq_id;

    // Per-blit lane offsets (constant across rows): stride & FB bases are
    // 16-byte aligned, so the lane offset depends only on the x coordinate.
    // Derived combinationally from the registered x bases (set in IDLE), so
    // they are valid from ROW_INIT onward.
    wire  [2:0]  src_lane_start;     // = src_x_base % 8
    wire  [2:0]  dst_lane_start;     // = dst_x_base % 8
    assign src_lane_start = src_x_base[2:0];
    assign dst_lane_start = dst_x_base[2:0];

    //==========================================================================
    // Per-row runtime state
    //==========================================================================
    logic [31:0] cur_src_row_base;   // 16-byte-aligned src row beat-0 address
    logic [31:0] cur_dst_row_base;   // 16-byte-aligned dst row beat-0 address
    logic [15:0] cur_y;              // current row (0..height_eff-1)

    logic [7:0]  src_total_beats;    // src beats covering this row's active px
    logic [7:0]  dst_total_beats;    // dst beats covering this row's active px
    logic [7:0]  src_beat_idx;       // global src beat index (burst start)
    logic [7:0]  dst_beat_idx;       // global dst beat index (burst start)

    logic [7:0]  cur_rd_burst;       // latched read burst length (beats)
    logic [4:0]  rd_beat_cnt;        // beats received in current read burst
    logic [7:0]  cur_wr_burst;       // latched write burst length (beats)
    logic [4:0]  wr_beat_cnt;        // beats sent in current write burst

    logic [15:0] active_consumed;    // active stream pixels written so far (row)

    //==========================================================================
    // Line buffer (combinational read) — holds one row's src beats
    //==========================================================================
    logic [127:0] line_buf [0:LINE_BUF_BEATS-1];

    //==========================================================================
    // Performance / debug counters (internal, not exposed)
    //==========================================================================
    logic [31:0] blit_read_burst_count;
    logic [31:0] blit_write_burst_count;
    logic [31:0] blit_pixel_count;
    logic [31:0] blit_cycle_count;
    logic        cycle_running;
    // cum_* are declared as output ports above.

    //==========================================================================
    // Combinational row base addresses (byte-addressed, before alignment)
    //==========================================================================
    wire [31:0] row_src_base_raw = src_base_addr +
                                   ((src_y_base + cur_y) * src_stride_bytes) +
                                   ({15'd0, src_x_base, 1'b0});
    wire [31:0] row_dst_base_raw = fb_base +
                                   ((dst_y_base + cur_y) * dst_stride) +
                                   ({15'd0, dst_x_base, 1'b0});

    //==========================================================================
    // Burst-length helpers (16-byte beats, 4 KB / 16-beat caps)
    //==========================================================================
    function automatic [7:0] beats_to_4k(input logic [31:0] addr);
        // addr is 16-byte aligned; beats remaining before the 4 KB boundary.
        // Saturate at MAX_BURST_BEATS: any larger value is unconstraining
        // (bursts are capped at 16) AND avoids the 256->0 wraparound that a
        // plain [7:0] truncation would produce for a page-aligned address.
        logic [12:0] v;
        begin
            v = (13'd4096 - {1'b0, addr[11:0]}) >> 4;
            beats_to_4k = (v >= MAX_BURST_BEATS) ? MAX_BURST_BEATS[7:0] : v[7:0];
        end
    endfunction

    function automatic [7:0] min3_u8(
        input logic [7:0] a,
        input logic [7:0] b,
        input logic [7:0] c
    );
        logic [7:0] m;
        begin
            m = (a < b) ? a : b;
            min3_u8 = (m < c) ? m : c;
        end
    endfunction

    // Build a per-lane byte-strobe mask: 2 bits set for each active lane in
    // [lane_start .. lane_start+pixel_count-1].  Copied from gru_axi_writer.sv.
    function automatic [15:0] build_partial_strb(
        input logic [2:0] lane_start,
        input logic [3:0] pixel_count
    );
        integer lane;
        begin
            build_partial_strb = 16'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if ((lane >= lane_start) && (lane < (lane_start + pixel_count))) begin
                    build_partial_strb[(lane * 2) +: 2] = 2'b11;
                end
            end
        end
    endfunction

    `ifndef SYNTHESIS
    task automatic validate_burst(
        input string       stage,
        input logic [31:0] addr_in,
        input logic [7:0]  beats_in
    );
        logic [15:0] burst_bytes;
        begin
            if (beats_in == 8'd0) begin
                $fatal(1, "[GRU_BLIT] %0s invalid burst beats=0 addr=0x%08x", stage, addr_in);
            end
            if (beats_in > MAX_BURST_BEATS) begin
                $fatal(1, "[GRU_BLIT] %0s burst exceeds %0d beats=%0d addr=0x%08x",
                       stage, MAX_BURST_BEATS, beats_in, addr_in);
            end
            burst_bytes = {8'd0, beats_in} << 4;
            if (({20'd0, addr_in[11:0]} + {16'd0, burst_bytes}) > 17'd4096) begin
                $fatal(1, "[GRU_BLIT] %0s burst crosses 4KB addr=0x%08x beats=%0d",
                       stage, addr_in, beats_in);
            end
        end
    endtask
    `endif

    //==========================================================================
    // Current write-beat geometry (combinational, from active_consumed)
    //==========================================================================
    // The active pixel stream (width_eff pixels, indexed 0..width_eff-1) is
    // distributed across dst beats.  Beat 0 occupies dst lanes
    // [dst_lane_start .. ]; every later beat starts at lane 0.  active_consumed
    // counts stream pixels already emitted, so it is 0 only for beat 0.
    logic        cur_is_first;
    logic [2:0]  cur_lane_lo;
    logic [3:0]  cur_n;               // active pixels in the current dst beat
    logic [15:0] cur_p_lo;            // stream index of this beat's first pixel
    logic [15:0] cur_rem;             // active pixels remaining at this beat
    logic [15:0] cur_sa;              // src absolute pixel index of stream px p_lo
    logic [12:0] cur_sbeat_idx;       // line_buf beat holding stream px p_lo
    logic [2:0]  cur_soff;            // lane offset of stream px p_lo in that beat
    logic [4:0]  room_first;          // 8 - dst_lane_start (1..8)
    logic [255:0] cur_cat;            // 2-beat window, shifted to stream px p_lo
    logic [255:0] cur_wdata_shift;

    always_comb begin
        cur_is_first  = (active_consumed == 16'd0);
        cur_lane_lo   = cur_is_first ? dst_lane_start : 3'd0;
        room_first    = 5'd8 - {2'd0, dst_lane_start};
        if (cur_is_first) begin
            // First beat: up to (8 - dst_lane_start) pixels, or fewer if width is tiny.
            if (width_eff < {11'd0, room_first}) begin
                cur_rem = width_eff;
                cur_n   = cur_rem[3:0];
            end else begin
                cur_n = room_first[3:0];
            end
            cur_p_lo = 16'd0;
        end else begin
            cur_rem = width_eff - active_consumed;
            if (cur_rem >= 16'd8) begin
                cur_n = 4'd8;
            end else begin
                cur_n = cur_rem[3:0];
            end
            cur_p_lo = active_consumed;
        end

        // Map stream pixel p_lo into the line buffer.
        cur_sa        = {13'd0, src_lane_start} + cur_p_lo;
        cur_sbeat_idx = cur_sa[15:3];
        cur_soff      = cur_sa[2:0];
        // 2-beat window barrel-shifted so that the low lane holds stream px p_lo.
        cur_cat       = {line_buf[cur_sbeat_idx + 1], line_buf[cur_sbeat_idx]} >> (16 * cur_soff);
        // Position the n active pixels at dst lanes [cur_lane_lo .. ].
        cur_wdata_shift = cur_cat << (16 * cur_lane_lo);
    end

    //==========================================================================
    // Write-data outputs (combinational, valid while in BLIT_WR_W && wvalid)
    //==========================================================================
    always_comb begin
        m_axi_wdata = cur_wdata_shift[127:0];
        m_axi_wstrb = (state == BLIT_WR_W)
                      ? build_partial_strb(cur_lane_lo, cur_n)
                      : 16'd0;
        m_axi_wlast = (state == BLIT_WR_W) && (wr_beat_cnt == (cur_wr_burst - 8'd1));
    end

    assign blit_busy = (state != BLIT_IDLE);

    //==========================================================================
    // Main state machine
    //==========================================================================
    always_ff @(posedge clk or negedge rstn) begin
        logic [31:0] next_width;
        logic [31:0] next_height;
        logic [7:0]  rd_burst;
        logic [7:0]  wr_burst;
        logic [31:0] ar_addr;
        logic [31:0] aw_addr;
        logic [7:0]  next_src_idx;
        logic [7:0]  next_dst_idx;

        if (!rstn) begin
            state                  <= BLIT_IDLE;
            src_base_addr          <= '0;
            src_stride_bytes       <= '0;
            src_x_base             <= '0;
            src_y_base             <= '0;
            dst_x_base             <= '0;
            dst_y_base             <= '0;
            width_eff              <= '0;
            height_eff             <= '0;
            src_pixel_format       <= '0;
            seq_id                 <= '0;
            cur_src_row_base       <= '0;
            cur_dst_row_base       <= '0;
            cur_y                  <= '0;
            src_total_beats        <= '0;
            dst_total_beats        <= '0;
            src_beat_idx           <= '0;
            dst_beat_idx           <= '0;
            cur_rd_burst           <= '0;
            rd_beat_cnt            <= '0;
            cur_wr_burst           <= '0;
            wr_beat_cnt            <= '0;
            active_consumed        <= '0;
            cmd_done_pulse         <= 1'b0;
            axi_error_pulse        <= 1'b0;
            cmd_ready              <= 1'b0;
            blit_read_burst_count  <= '0;
            blit_write_burst_count <= '0;
            blit_pixel_count       <= '0;
            blit_cycle_count       <= '0;
            cycle_running          <= 1'b0;
            cum_blit_count         <= '0;
            cum_rd_beat_count      <= '0;
            cum_wr_beat_count      <= '0;
            cum_pixel_count        <= '0;
            cum_cycle_count        <= '0;
            m_axi_arid             <= 5'd3;
            m_axi_araddr           <= 32'd0;
            m_axi_arlen            <= 8'd0;
            m_axi_arsize           <= 3'b100;   // 16 bytes/transfer
            m_axi_arburst          <= 2'b01;    // INCR
            m_axi_arlock           <= 1'b0;
            m_axi_arcache          <= 4'b0011;
            m_axi_arprot           <= 3'b000;
            m_axi_arvalid          <= 1'b0;
            m_axi_rready           <= 1'b0;
            m_axi_awid             <= 5'd4;
            m_axi_awaddr           <= 32'd0;
            m_axi_awlen            <= 8'd0;
            m_axi_awsize           <= 3'b100;
            m_axi_awburst          <= 2'b01;
            m_axi_awlock           <= 1'b0;
            m_axi_awcache          <= 4'b0011;
            m_axi_awprot           <= 3'b000;
            m_axi_awvalid          <= 1'b0;
            m_axi_wvalid           <= 1'b0;
            m_axi_bready           <= 1'b0;
        end else if (clr) begin
            state                  <= BLIT_IDLE;
            cur_y                  <= '0;
            src_beat_idx           <= '0;
            dst_beat_idx           <= '0;
            cur_rd_burst           <= '0;
            rd_beat_cnt            <= '0;
            cur_wr_burst           <= '0;
            wr_beat_cnt            <= '0;
            active_consumed        <= '0;
            cmd_done_pulse         <= 1'b0;
            axi_error_pulse        <= 1'b0;
            cmd_ready              <= 1'b0;
            cycle_running          <= 1'b0;
            m_axi_arvalid          <= 1'b0;
            m_axi_rready           <= 1'b0;
            m_axi_awvalid          <= 1'b0;
            m_axi_wvalid           <= 1'b0;
            m_axi_bready           <= 1'b0;
        end else begin
            cmd_done_pulse  <= 1'b0;
            axi_error_pulse <= 1'b0;

            // Default AXI control deassert; individual states re-assert.
            m_axi_arvalid <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_rready  <= 1'b0;

            if (cycle_running) begin
                blit_cycle_count <= blit_cycle_count + 32'd1;
                cum_cycle_count  <= cum_cycle_count + 32'd1;
            end

            case (state)
                //================================================================
                // IDLE — accept a new command
                //================================================================
                BLIT_IDLE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_valid) begin
                        src_base_addr    <= cmd_data[31:0];
                        src_stride_bytes <= cmd_data[63:32];
                        src_x_base       <= cmd_data[79:64];
                        src_y_base       <= cmd_data[95:80];
                        dst_x_base       <= cmd_data[111:96];
                        dst_y_base       <= cmd_data[127:112];
                        src_pixel_format <= cmd_data[162:160];
                        seq_id           <= cmd_data[170:163];
                        cur_y            <= 16'd0;
                        cmd_ready        <= 1'b0;

                        // Clipping: trim to frame (same logic as the 32-bit engine).
                        next_width  = cmd_data[143:128];
                        next_height = cmd_data[159:144];
                        if ((cmd_data[111:96] + next_width) > frame_w) begin
                            next_width = frame_w - cmd_data[111:96];
                        end
                        if ((cmd_data[127:112] + next_height) > frame_h) begin
                            next_height = frame_h - cmd_data[127:112];
                        end

                        // Validate: must be RGB565, non-zero, in-frame.
                        if ((cmd_data[162:160] != `GRU_PIXFMT_RGB565) ||
                            (cmd_data[143:128] == 16'd0) ||
                            (cmd_data[159:144] == 16'd0) ||
                            (cmd_data[111:96] >= frame_w) ||
                            (cmd_data[127:112] >= frame_h) ||
                            (next_width == 32'd0) ||
                            (next_height == 32'd0)) begin
                            cmd_done_pulse <= 1'b1;
                            state <= BLIT_DONE;
                        end else begin
                            width_eff  <= next_width[15:0];
                            height_eff <= next_height[15:0];
                            blit_read_burst_count  <= 32'd0;
                            blit_write_burst_count <= 32'd0;
                            blit_pixel_count       <= 32'd0;
                            blit_cycle_count       <= 32'd0;
                            cycle_running          <= 1'b1;
                            cum_blit_count         <= cum_blit_count + 32'd1;
                            state <= BLIT_ROW_INIT;
                        end
                    end
                end

                //================================================================
                // ROW_INIT — compute row bases & beat counts, reset counters
                //================================================================
                BLIT_ROW_INIT: begin
                    cur_src_row_base <= {row_src_base_raw[31:4], 4'b0000};
                    cur_dst_row_base <= {row_dst_base_raw[31:4], 4'b0000};
                    src_total_beats  <= (({13'd0, src_lane_start} + width_eff) + 16'd7) >> 3;
                    dst_total_beats  <= (({13'd0, dst_lane_start} + width_eff) + 16'd7) >> 3;
                    src_beat_idx     <= 8'd0;
                    dst_beat_idx     <= 8'd0;
                    rd_beat_cnt      <= 5'd0;
                    wr_beat_cnt      <= 5'd0;
                    active_consumed  <= 16'd0;
                    state            <= BLIT_RD_AR;

                    `ifndef SYNTHESIS
                    if (((({13'd0, src_lane_start} + width_eff) + 16'd7) >> 3) > LINE_BUF_BEATS) begin
                        $fatal(1, "[GRU_BLIT] row src beats exceed LINE_BUF_BEATS=%0d (w=%0d slane=%0d)",
                               LINE_BUF_BEATS, width_eff, src_lane_start);
                    end
                    `endif
                end

                //================================================================
                // RD_AR — issue a read burst (<=16 beats, no 4KB crossing)
                //================================================================
                BLIT_RD_AR: begin
                    ar_addr  = cur_src_row_base + ({24'd0, src_beat_idx} << 4);
                    rd_burst = min3_u8((src_total_beats - src_beat_idx),
                                       MAX_BURST_BEATS,
                                       beats_to_4k(ar_addr));
                    `ifndef SYNTHESIS
                    validate_burst("RD_AR", ar_addr, rd_burst);
                    `endif
                    m_axi_araddr  <= ar_addr;
                    m_axi_arlen   <= rd_burst - 8'd1;
                    m_axi_arsize  <= 3'b100;
                    m_axi_arburst <= 2'b01;
                    m_axi_arvalid <= 1'b1;
                    cur_rd_burst  <= rd_burst;
                    rd_beat_cnt   <= 5'd0;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        blit_read_burst_count <= blit_read_burst_count + 32'd1;
                        state <= BLIT_RD_R;
                    end
                end

                //================================================================
                // RD_R — receive beats into line_buf
                //================================================================
                BLIT_RD_R: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        // Store at the global src beat index for this received beat.
                        line_buf[src_beat_idx + rd_beat_cnt] <= m_axi_rdata;
                        cum_rd_beat_count <= cum_rd_beat_count + 32'd1;
                        if (m_axi_rresp != 2'b00) begin
                            axi_error_pulse <= 1'b1;
                        end
                        if (rd_beat_cnt == (cur_rd_burst - 8'd1)) begin
                            // Last beat of this read burst.
                            next_src_idx = src_beat_idx + cur_rd_burst;
                            src_beat_idx <= next_src_idx;
                            rd_beat_cnt  <= 5'd0;
                            m_axi_rready <= 1'b0;
                            if (next_src_idx >= src_total_beats) begin
                                state <= BLIT_WR_AW;
                            end else begin
                                state <= BLIT_RD_AR;
                            end
                        end else begin
                            rd_beat_cnt <= rd_beat_cnt + 5'd1;
                        end
                    end
                end

                //================================================================
                // WR_AW — issue a write burst (<=16 beats, no 4KB crossing)
                //================================================================
                BLIT_WR_AW: begin
                    aw_addr  = cur_dst_row_base + ({24'd0, dst_beat_idx} << 4);
                    wr_burst = min3_u8((dst_total_beats - dst_beat_idx),
                                       MAX_BURST_BEATS,
                                       beats_to_4k(aw_addr));
                    `ifndef SYNTHESIS
                    validate_burst("WR_AW", aw_addr, wr_burst);
                    `endif
                    m_axi_awaddr  <= aw_addr;
                    m_axi_awlen   <= wr_burst - 8'd1;
                    m_axi_awsize  <= 3'b100;
                    m_axi_awburst <= 2'b01;
                    m_axi_awvalid <= 1'b1;
                    cur_wr_burst  <= wr_burst;
                    wr_beat_cnt   <= 5'd0;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        blit_write_burst_count <= blit_write_burst_count + 32'd1;
                        state <= BLIT_WR_W;
                    end
                end

                //================================================================
                // WR_W — emit dst beats assembled from line_buf
                //================================================================
                BLIT_WR_W: begin
                    m_axi_wvalid <= 1'b1;
                    if (m_axi_wvalid && m_axi_wready) begin
                        // wdata/wstrb/wlast are combinational for this beat
                        // (global beat = dst_beat_idx + wr_beat_cnt).
                        blit_pixel_count  <= blit_pixel_count + {28'd0, cur_n};
                        cum_wr_beat_count <= cum_wr_beat_count + 32'd1;
                        cum_pixel_count   <= cum_pixel_count   + {28'd0, cur_n};
                        active_consumed   <= active_consumed + {12'd0, cur_n};
                        if (wr_beat_cnt == (cur_wr_burst - 8'd1)) begin
                            wr_beat_cnt  <= 5'd0;
                            m_axi_wvalid <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state <= BLIT_WR_B;
                        end else begin
                            wr_beat_cnt <= wr_beat_cnt + 5'd1;
                        end
                    end
                end

                //================================================================
                // WR_B — write response, advance to next burst / row / done
                //================================================================
                BLIT_WR_B: begin
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        if (m_axi_bresp != 2'b00) begin
                            axi_error_pulse <= 1'b1;
                        end
                        next_dst_idx = dst_beat_idx + cur_wr_burst;
                        dst_beat_idx <= next_dst_idx;
                        if (next_dst_idx >= dst_total_beats) begin
                            // Row complete.
                            if (cur_y + 16'd1 >= height_eff) begin
                                state <= BLIT_DONE;
                            end else begin
                                cur_y <= cur_y + 16'd1;
                                state <= BLIT_ROW_INIT;
                            end
                        end else begin
                            state <= BLIT_WR_AW;
                        end
                    end
                end

                //================================================================
                // DONE — emit completion pulse
                //================================================================
                BLIT_DONE: begin
                    cmd_done_pulse <= 1'b1;
                    cycle_running  <= 1'b0;
                    state <= BLIT_IDLE;
                end

                default: begin
                    state <= BLIT_IDLE;
                end
            endcase
        end
    end

endmodule
