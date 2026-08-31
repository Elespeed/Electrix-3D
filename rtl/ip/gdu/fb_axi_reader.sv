module fb_axi_reader #(
    // Optionally expand each framebuffer pixel to a 2x scanout stream.
    parameter bit SCALE_2X = 1'b0,
    parameter int unsigned FIFO_HIGH_WATER = 1800,
    parameter int unsigned MAX_SAFE_BURST = 32
) (
    input  logic        clk,
    input  logic        rstn,
    input  logic        enable,
    input  logic        reload,
    input  logic [31:0] fb_base,
    input  logic [31:0] stride,
    input  logic [15:0] width,
    input  logic [15:0] height,

    input  logic [11:0] fifo_level,
    output logic        fifo_wr_en,
    output logic [15:0] fifo_wr_data,
    output logic        axi_error,

    // -------------------------------------------------------------------------
    // Phase-4 cumulative performance counters (reset only on `!rstn`; survive
    // enable/reload toggles).  Exposed via the GDU perf MMIO window.
    // -------------------------------------------------------------------------
    output logic [31:0] rd_ar_txn_count,     // AXI AR transactions accepted
    output logic [31:0] rd_beat_count,       // 128-bit read beats received
    output logic [31:0] rd_wait_cycle_count, // cycles AR valid but not accepted

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
    output logic        m_axi_rready
);
    localparam int PIXELS_PER_BEAT = SCALE_2X ? 16 : 8;
    localparam int PIX_Q_DEPTH = SCALE_2X ? 512 : 256;
    localparam int PIX_Q_PTR_W = $clog2(PIX_Q_DEPTH);
    logic [15:0] fetch_y;
    logic        repeat_line;
    logic        line_active;

    logic [31:0] cur_addr;
    logic [15:0] beats_left;
    logic [8:0]  beats_outstanding;
    logic [8:0]  ar_issue_beats;
    logic        reload_pending;

    logic [15:0] pix_q_mem [0:PIX_Q_DEPTH-1];
    logic [PIX_Q_PTR_W-1:0] pix_q_wptr;
    logic [PIX_Q_PTR_W-1:0] pix_q_rptr;
    logic [9:0]  pix_q_count;

    logic [31:0] addr_line_base;

    // Phase-4 cumulative perf counters (declared as output ports above).

    wire [15:0] line_beats = stride[31:4];
    wire can_accept_rbeat = (pix_q_count <= (PIX_Q_DEPTH - PIXELS_PER_BEAT));
    wire [15:0] next_fetch_y = (fetch_y + 16'd1 >= height) ? 16'd0 : (fetch_y + 16'd1);
    wire line_fetch_ready = (height != 16'd0) &&
                            (line_beats != 16'd0) &&
                            (fifo_level < FIFO_HIGH_WATER);
    wire [16:0] _unused_width = {1'b0, width};
    wire [5:0] _unused_axi = {m_axi_rid[0], m_axi_rlast, _unused_width[0], 3'b000};

    logic [15:0] fifo_free_pixels;
    logic [8:0] max_beats_by_fifo;
    logic [8:0] beats_fifo_limited;
    logic [8:0] beats_capped;

    function automatic [PIX_Q_PTR_W-1:0] ptr_add(
        input [PIX_Q_PTR_W-1:0] ptr,
        input [4:0] step
    );
        begin
            ptr_add = ptr + step;
        end
    endfunction

    fb_addr_gen u_fb_addr_gen (
        .fb_base    (fb_base),
        .stride     (stride),
        .x          (16'd0),
        .y          (fetch_y),
        .line_base  (addr_line_base),
        .pixel_addr ()
    );

    assign m_axi_rready = enable && (reload || reload_pending || can_accept_rbeat);

    always_ff @(posedge clk or negedge rstn) begin
        logic do_pop;
        logic do_push;
        logic [15:0] beats_left_n;
        logic [8:0]  beats_outstanding_n;
        logic [31:0] cur_addr_n;
        logic [9:0]  pix_q_count_n;
        logic [PIX_Q_PTR_W-1:0] pix_q_wptr_n;
        logic [PIX_Q_PTR_W-1:0] pix_q_rptr_n;
        logic [8:0]  issue_beats_n;
        logic        can_issue_ar;
        logic        line_complete;
        logic        start_line_now;
        logic        reload_active;

        if (!rstn) begin
            fifo_wr_en         <= 1'b0;
            fifo_wr_data       <= 16'd0;
            axi_error          <= 1'b0;
            fetch_y            <= 16'd0;
            repeat_line        <= 1'b0;
            line_active        <= 1'b0;
            cur_addr           <= 32'd0;
            beats_left         <= 16'd0;
            beats_outstanding  <= 9'd0;
            ar_issue_beats     <= 9'd0;
            reload_pending     <= 1'b0;
            pix_q_wptr         <= 9'd0;
            pix_q_rptr         <= 9'd0;
            pix_q_count        <= 10'd0;

            m_axi_arid         <= 5'd1;
            m_axi_araddr       <= 32'd0;
            m_axi_arlen        <= 8'd0;
            m_axi_arsize       <= 3'b100;
            m_axi_arburst      <= 2'b01;
            m_axi_arlock       <= 1'b0;
            m_axi_arcache      <= 4'b0011;
            m_axi_arprot       <= 3'b000;
            m_axi_arvalid      <= 1'b0;

            rd_ar_txn_count     <= 32'd0;
            rd_beat_count       <= 32'd0;
            rd_wait_cycle_count <= 32'd0;
        end else begin
            fifo_wr_en <= 1'b0;

            if (!enable) begin
                axi_error          <= 1'b0;
                fetch_y            <= 16'd0;
                repeat_line        <= 1'b0;
                line_active        <= 1'b0;
                cur_addr           <= 32'd0;
                beats_left         <= 16'd0;
                beats_outstanding  <= 9'd0;
                ar_issue_beats     <= 9'd0;
                reload_pending     <= 1'b0;
                pix_q_wptr         <= 9'd0;
                pix_q_rptr         <= 9'd0;
                pix_q_count        <= 10'd0;
                m_axi_arvalid      <= 1'b0;
            end else begin
                if (m_axi_arvalid && !m_axi_arready) begin
                    rd_wait_cycle_count <= rd_wait_cycle_count + 32'd1;
                end
                beats_left_n = beats_left;
                beats_outstanding_n = beats_outstanding;
                cur_addr_n = cur_addr;
                pix_q_count_n = pix_q_count;
                pix_q_wptr_n = pix_q_wptr;
                pix_q_rptr_n = pix_q_rptr;
                reload_active = reload || reload_pending;

                if (reload) begin
                    line_active        <= 1'b0;
                    fetch_y            <= 16'd0;
                    cur_addr_n         = 32'd0;
                    beats_left_n       = 16'd0;
                    pix_q_count_n      = 10'd0;
                    pix_q_wptr_n       = '0;
                    pix_q_rptr_n       = '0;
                    reload_pending     <= m_axi_arvalid || (beats_outstanding_n != 9'd0);
                end

                start_line_now = !reload_active &&
                                 !line_active &&
                                 (beats_outstanding_n == 9'd0) &&
                                 (beats_left_n == 16'd0) &&
                                 !m_axi_arvalid &&
                                 line_fetch_ready;

                if (start_line_now) begin
                    line_active       <= 1'b1;
                    cur_addr_n        = addr_line_base;
                    beats_left_n      = line_beats;
                    beats_outstanding_n = 9'd0;
                end

                fifo_free_pixels = PIX_Q_DEPTH - pix_q_count_n;
                max_beats_by_fifo = fifo_free_pixels / PIXELS_PER_BEAT;
                if (beats_left_n[8:0] > max_beats_by_fifo) begin
                    beats_fifo_limited = max_beats_by_fifo;
                end else begin
                    beats_fifo_limited = beats_left_n[8:0];
                end

                if (beats_fifo_limited > MAX_SAFE_BURST) begin
                    beats_capped = MAX_SAFE_BURST[8:0];
                end else begin
                    beats_capped = beats_fifo_limited;
                end

                issue_beats_n = beats_capped;
                can_issue_ar = !reload_active &&
                               line_active &&
                               (beats_outstanding_n == 9'd0) &&
                               !m_axi_arvalid &&
                               (beats_left_n != 16'd0) &&
                               (issue_beats_n != 9'd0);

                if (can_issue_ar) begin
                    ar_issue_beats <= issue_beats_n;
                    m_axi_araddr   <= cur_addr_n;
                    m_axi_arlen    <= issue_beats_n[7:0] - 8'd1;
                    m_axi_arvalid  <= 1'b1;
                end

                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid      <= 1'b0;
                    rd_ar_txn_count    <= rd_ar_txn_count + 32'd1;
                    if (!reload_active) begin
                        beats_left_n       = beats_left_n - ar_issue_beats;
                        cur_addr_n         = cur_addr_n + {19'd0, ar_issue_beats, 4'b0000};
                    end else begin
                        beats_left_n       = 16'd0;
                        cur_addr_n         = 32'd0;
                    end
                    beats_outstanding_n = ar_issue_beats;
                end

                do_pop = !reload_active &&
                         (pix_q_count_n != 10'd0) &&
                         (fifo_level < FIFO_HIGH_WATER);
                if (do_pop) begin
                    fifo_wr_en    <= 1'b1;
                    fifo_wr_data  <= pix_q_mem[pix_q_rptr_n];
                    pix_q_rptr_n  = ptr_add(pix_q_rptr_n, 4'd1);
                    pix_q_count_n = pix_q_count_n - 10'd1;
                end

                do_push = m_axi_rvalid && m_axi_rready;
                if (do_push) begin
                    rd_beat_count <= rd_beat_count + 32'd1;
                    if (!reload_active) begin
                        if (SCALE_2X) begin
                            for (int pix = 0; pix < 8; pix = pix + 1) begin
                                pix_q_mem[ptr_add(pix_q_wptr_n, pix * 2)]     <= m_axi_rdata[16*pix +: 16];
                                pix_q_mem[ptr_add(pix_q_wptr_n, pix * 2 + 1)] <= m_axi_rdata[16*pix +: 16];
                            end
                            pix_q_wptr_n = ptr_add(pix_q_wptr_n, 5'd16);
                        end else begin
                            pix_q_mem[pix_q_wptr_n]                  <= m_axi_rdata[15:0];
                            pix_q_mem[ptr_add(pix_q_wptr_n, 5'd1)]   <= m_axi_rdata[31:16];
                            pix_q_mem[ptr_add(pix_q_wptr_n, 5'd2)]   <= m_axi_rdata[47:32];
                            pix_q_mem[ptr_add(pix_q_wptr_n, 5'd3)]   <= m_axi_rdata[63:48];
                            pix_q_mem[ptr_add(pix_q_wptr_n, 5'd4)]   <= m_axi_rdata[79:64];
                            pix_q_mem[ptr_add(pix_q_wptr_n, 5'd5)]   <= m_axi_rdata[95:80];
                            pix_q_mem[ptr_add(pix_q_wptr_n, 5'd6)]   <= m_axi_rdata[111:96];
                            pix_q_mem[ptr_add(pix_q_wptr_n, 5'd7)]   <= m_axi_rdata[127:112];
                            pix_q_wptr_n = ptr_add(pix_q_wptr_n, 5'd8);
                        end
                        pix_q_count_n = pix_q_count_n + PIXELS_PER_BEAT;
                    end

                    if (beats_outstanding_n != 9'd0) begin
                        beats_outstanding_n = beats_outstanding_n - 9'd1;
                    end
                    if (m_axi_rresp != 2'b00) begin
                        axi_error <= 1'b1;
                    end
                end

                line_complete = line_active &&
                                (beats_left_n == 16'd0) &&
                                (beats_outstanding_n == 9'd0) &&
                                !m_axi_arvalid;
                if (!reload_active && line_complete) begin
                    line_active <= 1'b0;
                    if (SCALE_2X && !repeat_line) begin
                        repeat_line <= 1'b1;
                    end else begin
                        repeat_line <= 1'b0;
                        fetch_y <= next_fetch_y;
                    end
                end

                if (reload_pending &&
                    !m_axi_arvalid &&
                    (beats_outstanding_n == 9'd0)) begin
                    reload_pending <= 1'b0;
                end

                beats_left <= beats_left_n;
                beats_outstanding <= beats_outstanding_n;
                cur_addr <= cur_addr_n;
                pix_q_wptr <= pix_q_wptr_n;
                pix_q_rptr <= pix_q_rptr_n;
                pix_q_count <= pix_q_count_n;
            end
        end
    end

endmodule
