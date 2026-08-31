`include "gru_defs.vh"

// =============================================================================
// gru_axi_writer — write-combine line buffer for the GRU render write path.
//
// Phase-3 rewrite (doc/04_phase3_memory_pipeline_for_3d.md).  The module keeps
// the EXACT same external port list / instance name / contract as the previous
// per-span writer (span_valid/ready/data, cmd_done_pulse, axi_error_pulse,
// writer_busy, 128-bit AXI4 master), so gru_top wiring and every testbench are
// unaffected at the interface level.  Only the internals change.
//
// Why a write-combine buffer.  The glyph engine emits one span of len=1 per
// visible pixel (gru_glyph_engine.sv).  The old writer turned each 1px span
// into a full AXI AW→W→B round-trip (partial-lane write) — the fine-grained
// DDR access the phase-3 doc warns about.  This module aggregates same-row
// pixel writes into an on-chip line buffer and writes them back as concentrated
// 128-bit beats (coalescing N same-row 1px spans into 1–2 beat writes).
//
// Architecture (single-row line buffer + block-on-flush):
//   * line_buf[LINE_BEATS] holds one framebuffer row of 128-bit beats (8 px
//     each).  dirty_mask[LINE_BEATS] is a per-beat 16-bit byte mask (2 bits
//     per pixel lane).  buf_y is the row currently held; valid while any beat
//     is dirty.
//   * Absorb: a span (y,x,len,color) is written into line_buf in a single
//     cycle (all touched beats updated, lanes merged last-writer-wins, masks
//     OR-ed).  Solid colour comes from gru_colour_lut.
//   * Flush triggers: (a) a span whose y differs from buf_y while the buffer
//     is dirty (evict the old row first), or (b) the last span of a command
//     (done_pending).  Flush scans dirty beats over several clocks, groups
//     consecutive ones into runs, and emits each run as one INCR burst (capped
//     at 16 beats, no 4KB crossing), with wstrb = per-beat dirty mask (middle
//     beats 0xFFFF, ends partial).  After each burst's B response the covered
//     masks are cleared.
//
// Key ordering invariant (do not violate): the span arbiter only presents
// span[N+1] after span[N]'s cmd_done_pulse has fired (it seq-gates on
// retire_seq, which advances solely on cmd_done_pulse — see gru_top).  So the
// buffer is guaranteed empty at every command boundary, and cmd_done_pulse
// must fire only after every dirty beat of the command is committed (B done).
// writer_busy stays asserted continuously from the first absorb until that
// done pulse, so a following fence cannot retire early.
//
// Depth-buffer hook (phase-3 scope: interface only, not implemented): the
// dirty_mask + flush machinery below is the attachment point for a future
// 16-bit depth buffer.  A depth RMW path would reuse this as a second tagged
// line buffer (read-beat → merge → dirty → flush) sharing the GRU write mux;
// see doc/04_phase3_memory_pipeline_for_3d_results.md.
// =============================================================================

module gru_axi_writer #(
    parameter BURST_MAX_BEATS = 16,
    // The enclosing profile selects the required capacity at instantiation.
    parameter int LINE_BEATS  = 64
) (
    input  logic                   clk,
    input  logic                   rstn,
    input  logic                   clr,
    input  logic [31:0]            fb_base,
    input  logic [31:0]            stride,
    input  logic                   span_valid,
    output logic                   span_ready,
    input  logic [`GRU_SPAN_W-1:0] span_data,
    output logic                   cmd_done_pulse,
    output logic                   axi_error_pulse,
    output logic                   writer_busy,

    // -------------------------------------------------------------------------
    // Phase-4 performance counters (cumulative since hard reset `!rstn`;
    // survive soft-reset / enable toggles so software can sample a window by
    // differencing two reads).  Exposed verbatim via the GRU perf MMIO window.
    // -------------------------------------------------------------------------
    output logic [31:0]            wcb_span_in_count,     // accepted spans with len>0
    output logic [31:0]            wcb_pixel_in_count,    // pixels absorbed
    output logic [31:0]            wcb_aw_txn_count,      // AXI AW transactions (bursts) issued
    output logic [31:0]            wcb_beat_out_count,    // W beats committed
    output logic [31:0]            wcb_full_beat_count,   // W beats with wstrb==0xFFFF
    output logic [31:0]            wcb_partial_beat_count,// W beats with wstrb!=0xFFFF
    output logic [31:0]            wcb_flush_count,       // row-eviction / done flush events

    output logic [4:0]             m_axi_awid,
    output logic [31:0]            m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic                   m_axi_awlock,
    output logic [3:0]             m_axi_awcache,
    output logic [2:0]             m_axi_awprot,
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,
    output logic [127:0]           m_axi_wdata,
    output logic [15:0]            m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,
    input  logic [4:0]             m_axi_bid,
    input  logic [1:0]             m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready
);
    //==========================================================================
    // Localparams
    //==========================================================================
    localparam int MAX_BURST_BEATS = 16;   // AXI4 INCR cap (awlen = beats-1)

    typedef enum logic [2:0] {
        WCB_IDLE       = 3'd0,
        WCB_APPLY_SPAN = 3'd1,
        WCB_FLUSH_SCAN = 3'd2,
        WCB_FLUSH_RUN  = 3'd3,
        WCB_FLUSH_PLAN = 3'd4,
        WCB_FLUSH_AW   = 3'd5,
        WCB_FLUSH_W    = 3'd6,
        WCB_FLUSH_B    = 3'd7
    } wcb_state_t;

    //==========================================================================
    // Span field decode (combinational)
    //==========================================================================
    // The span FIFO exposes a combinational read port.  Capture it before
    // coordinate arithmetic and the line-buffer update so the FIFO read mux
    // cannot form one path with the write-combine datapath.
    logic [`GRU_SPAN_W-1:0] span_q;
    logic                    span_q_valid;

    wire [`GRU_Y_W-1:0] span_in_y = span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB];
    wire [9:0]          span_in_len = span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB];

    wire [`GRU_Y_W-1:0] span_y = span_q[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB];
    wire [8:0]          span_x = span_q[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB];
    wire [9:0]          span_len = span_q[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB];
    wire [15:0]         span_color565 = span_q[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB];
    wire                span_last = span_q[`GRU_SPAN_LAST_BIT];

    //==========================================================================
    // Line buffer storage
    //==========================================================================
    logic [127:0] line_buf   [0:LINE_BEATS-1];
    logic [15:0]  dirty_mask [0:LINE_BEATS-1];
    logic [LINE_BEATS-1:0] dirty_beat;
    logic [`GRU_Y_W-1:0] buf_y;   // row held in the buffer (valid while any beat dirty)
    logic         done_pending;   // last span absorbed; flush must end in cmd_done_pulse

    //==========================================================================
    // Flush machine state
    //==========================================================================
    wcb_state_t state;
    logic [6:0]  flush_beat;      // scan cursor (next beat to consider)
    logic [6:0]  run_start;       // first beat of the current burst (latched at AW)
    logic [6:0]  scan_start_q;    // first dirty beat captured by FLUSH_SCAN
    logic [6:0]  scan_end_q;      // last consecutive dirty beat captured by FLUSH_SCAN
    logic [4:0]  burst_len;       // beats in the current burst (1..16)
    logic [4:0]  wr_cnt;          // W beat index within the current burst
    logic [31:0] aw_addr_q;       // registered AW address for the current burst
    logic [7:0]  aw_len_q;        // registered beat count for the current burst

    //==========================================================================
    // Performance counters (declared as output ports above; still reset/incremented
    // in the main always_ff below).  Read hierarchically by phase-3 TBs AND via
    // the GRU perf MMIO window by software (phase 4).
    //==========================================================================

    //==========================================================================
    // Helper functions
    //==========================================================================
    // 128-bit lane enable mask: lanes [cov_lo..cov_hi] each get 16'hFFFF.
    function automatic [127:0] lane_mask_128(input int cov_lo, input int cov_hi);
        int lane;
        logic [127:0] m;
        begin
            m = 128'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if ((lane >= cov_lo) && (lane <= cov_hi)) begin
                    m[lane*16 +: 16] = 16'hFFFF;
                end
            end
            lane_mask_128 = m;
        end
    endfunction

    // 16-bit byte mask: lanes [cov_lo..cov_hi] each get 2'b11.
    function automatic [15:0] byte_mask_16(input int cov_lo, input int cov_hi);
        int lane;
        logic [15:0] m;
        begin
            m = 16'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if ((lane >= cov_lo) && (lane <= cov_hi)) begin
                    m[lane*2 +: 2] = 2'b11;
                end
            end
            byte_mask_16 = m;
        end
    endfunction

    // beats remaining to the 4KB boundary from a 16-byte-aligned address,
    // saturated at MAX_BURST_BEATS (avoids the 256→0 wrap on page-aligned addr).
    function automatic [7:0] beats_to_4k(input logic [31:0] addr);
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

    //==========================================================================
    // Derived combinational signals
    //==========================================================================
    // any_dirty: true if any beat holds dirty (unflushed) data.  While a flush
    // is in progress the masks are still set until the B handshake clears them,
    // so this naturally stays 1 through the flush and only drops once the last
    // dirty beat has been committed.
    logic any_dirty;
    always_comb begin
        any_dirty = 1'b0;
        for (int i = 0; i < LINE_BEATS; i = i + 1) begin
            if (dirty_beat[i]) any_dirty = 1'b1;
        end
    end

    //==========================================================================
    // Output assignments
    //==========================================================================
    // span_ready: accept in IDLE unless this is a y-change that requires
    // evicting the currently-buffered row first (then we hold the span and
    // flush; the arbiter keeps presenting it until we are ready).
    assign span_ready = (state == WCB_IDLE) && !span_q_valid && span_valid &&
                         ~((span_in_len != 10'd0) && any_dirty && (span_in_y != buf_y));

    assign writer_busy = (state != WCB_IDLE) || any_dirty || done_pending;

    // AXI write-data: beat = run_start + wr_cnt (combinational read of buffer).
    wire [6:0] cur_w_beat = run_start + {2'd0, wr_cnt};
    always_comb begin
        m_axi_awid    = 5'd2;
        m_axi_awaddr  = aw_addr_q;
        m_axi_awlen   = aw_len_q - 8'd1;
        m_axi_awsize  = 3'b100;     // 16 bytes/transfer
        m_axi_awburst = 2'b01;      // INCR
        m_axi_awlock  = 1'b0;
        m_axi_awcache = 4'b0011;
        m_axi_awprot  = 3'b000;
        m_axi_awvalid = (state == WCB_FLUSH_AW);

        m_axi_wdata   = line_buf[cur_w_beat];
        m_axi_wstrb   = (state == WCB_FLUSH_W) ? dirty_mask[cur_w_beat] : 16'd0;
        m_axi_wlast   = (state == WCB_FLUSH_W) && (wr_cnt == (burst_len - 5'd1));
        m_axi_wvalid  = (state == WCB_FLUSH_W);

        m_axi_bready  = (state == WCB_FLUSH_B);
    end

    //==========================================================================
    // Main state machine
    //==========================================================================
    always_ff @(posedge clk or negedge rstn) begin : proc
        // Procedural scratch (assigned/used within this single process only).
        int sx;
        int slen;
        int beat_lo;
        int beat_hi;
        int fb;
        int b;
        int scan_start;
        int scan_end;
        logic [31:0] scan_addr;
        logic [7:0]  scan_len;
        bit found_run;
        bit stopped_run;
        if (!rstn) begin
            state          <= WCB_IDLE;
            span_q         <= '0;
            span_q_valid   <= 1'b0;
            buf_y          <= '0;
            done_pending   <= 1'b0;
            flush_beat     <= 7'd0;
            run_start      <= 7'd0;
            scan_start_q   <= 7'd0;
            scan_end_q     <= 7'd0;
            burst_len      <= 5'd0;
            wr_cnt         <= 5'd0;
            aw_addr_q      <= 32'd0;
            aw_len_q       <= 8'd0;
            cmd_done_pulse <= 1'b0;
            axi_error_pulse<= 1'b0;
            wcb_span_in_count     <= 32'd0;
            wcb_pixel_in_count    <= 32'd0;
            wcb_aw_txn_count      <= 32'd0;
            wcb_beat_out_count    <= 32'd0;
            wcb_full_beat_count   <= 32'd0;
            wcb_partial_beat_count<= 32'd0;
            wcb_flush_count       <= 32'd0;
            for (b = 0; b < LINE_BEATS; b = b + 1) begin
                line_buf[b]   <= 128'd0;
                dirty_mask[b] <= 16'd0;
            end
            dirty_beat      <= '0;
        end else if (clr) begin
            state          <= WCB_IDLE;
            span_q         <= '0;
            span_q_valid   <= 1'b0;
            buf_y          <= '0;
            done_pending   <= 1'b0;
            flush_beat     <= 7'd0;
            run_start      <= 7'd0;
            scan_start_q   <= 7'd0;
            scan_end_q     <= 7'd0;
            burst_len      <= 5'd0;
            wr_cnt         <= 5'd0;
            aw_addr_q      <= 32'd0;
            aw_len_q       <= 8'd0;
            cmd_done_pulse <= 1'b0;
            axi_error_pulse<= 1'b0;
            for (b = 0; b < LINE_BEATS; b = b + 1) begin
                dirty_mask[b] <= 16'd0;
            end
            dirty_beat      <= '0;
        end else begin
            cmd_done_pulse  <= 1'b0;
            axi_error_pulse <= 1'b0;

            case (state)
                //--------------------------------------------------------------
                // IDLE — capture a span or evict a dirty row before accepting
                // a span for another row.
                //--------------------------------------------------------------
                WCB_IDLE: begin
                    if (span_valid && span_ready) begin
                        span_q       <= span_data;
                        span_q_valid <= 1'b1;
                        state        <= WCB_APPLY_SPAN;
                    end else if (span_valid && !span_ready) begin
                        // y-change while buffer dirty: evict the old row, then
                        // the (still-presented) span will be captured in IDLE.
                        flush_beat      <= 7'd0;
                        wcb_flush_count <= wcb_flush_count + 32'd1;
                        state           <= WCB_FLUSH_SCAN;
                    end
                end

                //--------------------------------------------------------------
                // APPLY_SPAN — merge the registered span into the line buffer.
                //--------------------------------------------------------------
                WCB_APPLY_SPAN: begin
                    span_q_valid <= 1'b0;
                    if (span_q_valid) begin
                        sx    = span_x;
                        slen  = span_len;
                        beat_lo = sx >> 3;
                        beat_hi = (sx + slen - 1) >> 3;

                        if (slen == 0) begin
                            // len=0 span (always last in practice).  Consume it.
                            if (any_dirty) begin
                                // Dirty data buffered (e.g. glyph off-screen last
                                // pixel after visible pixels): flush then done.
                                done_pending   <= 1'b1;
                                flush_beat     <= 7'd0;
                                wcb_flush_count<= wcb_flush_count + 32'd1;
                                state          <= WCB_FLUSH_SCAN;
                            end else begin
                                // Empty buffer: retire immediately.
                                cmd_done_pulse <= 1'b1;
                                state          <= WCB_IDLE;
                            end
                        end else begin
                            // len>0: absorb this span's pixels into the buffer.
                            `ifndef SYNTHESIS
                            if (beat_hi >= LINE_BEATS) begin
                                $fatal(1, "[gru_axi_writer] span overflows line_buf: x=%0d len=%0d y=%0d beat_hi=%0d LINE_BEATS=%0d",
                                       sx, slen, span_y, beat_hi, LINE_BEATS);
                            end
                            `endif
                            buf_y <= span_y;
                            wcb_span_in_count  <= wcb_span_in_count  + 32'd1;
                            wcb_pixel_in_count <= wcb_pixel_in_count + {22'd0, span_len};
                            for (fb = 0; fb < LINE_BEATS; fb = fb + 1) begin
                                int clo, chi;
                                logic [127:0] lmask;
                                logic [15:0]  bmask;
                                if ((fb >= beat_lo) && (fb <= beat_hi)) begin
                                    clo   = (sx      > fb*8) ? (sx - fb*8)           : 0;
                                    chi   = ((sx+slen-1) < (fb*8+7)) ? (sx+slen-1 - fb*8) : 7;
                                    lmask = lane_mask_128(clo, chi);
                                    bmask = byte_mask_16(clo, chi);
                                    // (BLKLOOPINIT) the 2-state simulator cannot schedule a
                                    // non-blocking array write inside a for-loop. Each
                                    // line_buf[fb]/dirty_mask[fb] is written exactly once per
                                    // trigger (distinct fb) and is not read again in this same
                                    // clock edge, so a blocking write is observationally identical
                                    // to the non-blocking original. ModelSim/synthesis keep the
                                    // non-blocking form (else branch).
`ifdef VERILATOR_BUILD
                                    line_buf[fb]   = (line_buf[fb] & ~lmask) | ({8{span_color565}} & lmask);
                                    dirty_mask[fb] = dirty_mask[fb] | bmask;
                                    dirty_beat[fb] = 1'b1;
`else
                                    line_buf[fb]   <= (line_buf[fb] & ~lmask) | ({8{span_color565}} & lmask);
                                    dirty_mask[fb] <= dirty_mask[fb] | bmask;
                                    dirty_beat[fb] <= 1'b1;
`endif
                                end
                            end
                            if (span_last) begin
                                done_pending   <= 1'b1;
                                flush_beat     <= 7'd0;
                                wcb_flush_count<= wcb_flush_count + 32'd1;
                                state          <= WCB_FLUSH_SCAN;
                            end else begin
                                state <= WCB_IDLE;
                            end
                        end
                    end else begin
                        // Defensive recovery: APPLY_SPAN is entered only after
                        // an accepted span, but never retain a stale state.
                        state <= WCB_IDLE;
                    end
                end

                //--------------------------------------------------------------
                // FLUSH_SCAN — find the next dirty beat one entry per cycle.
                // This deliberately avoids a 128-bit priority chain.
                //--------------------------------------------------------------
                WCB_FLUSH_SCAN: begin
                    if (dirty_beat[flush_beat]) begin
                        scan_start_q <= flush_beat;
                        scan_end_q   <= flush_beat;
                        state        <= WCB_FLUSH_RUN;
                    end else if (flush_beat == (LINE_BEATS - 1)) begin
                        if (done_pending) begin
                            cmd_done_pulse <= 1'b1;
                            done_pending   <= 1'b0;
                        end
                        state <= WCB_IDLE;
                    end else begin
                        flush_beat <= flush_beat + 1'b1;
                    end
                end

                //--------------------------------------------------------------
                // FLUSH_RUN — extend the current dirty run one entry per cycle.
                // The burst cap is checked here, so PLAN receives at most 16
                // beats and never needs to inspect the whole line.
                //--------------------------------------------------------------
                WCB_FLUSH_RUN: begin
                    if ((scan_end_q == (LINE_BEATS - 1)) ||
                        ((scan_end_q - scan_start_q) == (MAX_BURST_BEATS - 1))) begin
                        state <= WCB_FLUSH_PLAN;
                    end else if (dirty_beat[scan_end_q + 1'b1]) begin
                        scan_end_q <= scan_end_q + 1'b1;
                    end else begin
                        state <= WCB_FLUSH_PLAN;
                    end
                end

                WCB_FLUSH_PLAN: begin
                    scan_addr = fb_base + ({24'd0, buf_y} * stride) + (scan_start_q * 16);
                    scan_len  = min3_u8(scan_end_q - scan_start_q + 1,
                                        MAX_BURST_BEATS[7:0],
                                        beats_to_4k(scan_addr));
                    run_start <= scan_start_q;
                    burst_len <= scan_len[4:0];
                    aw_addr_q <= scan_addr;
                    aw_len_q  <= scan_len;
                    wr_cnt    <= 5'd0;
                    state     <= WCB_FLUSH_AW;
                end

                //--------------------------------------------------------------
                // FLUSH_AW — issue AW for the registered dirty run
                //--------------------------------------------------------------
                WCB_FLUSH_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        wr_cnt    <= 5'd0;
                        wcb_aw_txn_count <= wcb_aw_txn_count + 32'd1;
                        state <= WCB_FLUSH_W;
                    end
                end

                //--------------------------------------------------------------
                // FLUSH_W — stream the burst's beats
                //--------------------------------------------------------------
                WCB_FLUSH_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (dirty_mask[cur_w_beat] == 16'hFFFF) begin
                            wcb_full_beat_count <= wcb_full_beat_count + 32'd1;
                        end else begin
                            wcb_partial_beat_count <= wcb_partial_beat_count + 32'd1;
                        end
                        wcb_beat_out_count <= wcb_beat_out_count + 32'd1;
                        if (wr_cnt == (burst_len - 5'd1)) begin
                            state <= WCB_FLUSH_B;
                        end else begin
                            wr_cnt <= wr_cnt + 5'd1;
                        end
                    end
                end

                //--------------------------------------------------------------
                // FLUSH_B — write response, clear covered masks, advance
                //--------------------------------------------------------------
                WCB_FLUSH_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (m_axi_bresp != 2'b00) begin
                            axi_error_pulse <= 1'b1;
                        end
                        for (b = 0; b < LINE_BEATS; b = b + 1) begin
                            if ((b >= run_start) && (b < (run_start + {2'd0, burst_len}))) begin
                                dirty_mask[b] <= 16'd0;
                                dirty_beat[b] <= 1'b0;
                            end
                        end
                        flush_beat <= run_start + {2'd0, burst_len};
                        state      <= WCB_FLUSH_SCAN;
                    end
                end

                default: begin
                    state <= WCB_IDLE;
                end
            endcase
        end
    end
endmodule
