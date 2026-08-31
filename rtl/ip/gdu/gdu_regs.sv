module gdu_regs #(
    parameter logic [31:0] DEFAULT_FB_BASE = 32'd0,
    parameter logic [31:0] DEFAULT_STRIDE = 32'd0,
    parameter logic [15:0] DEFAULT_WIDTH = 16'd0,
    parameter logic [15:0] DEFAULT_HEIGHT = 16'd0,
    parameter logic [1:0]  DEFAULT_PIXEL_FORMAT = 2'd1
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

    input  logic        fifo_underflow,
    input  logic        present_done,
    input  logic        axi_error,
    input  logic        swap_done,

    output logic        gdu_enable,
    output logic [31:0] fb_base,
    output logic [31:0] stride,
    output logic [15:0] width,
    output logic [15:0] height,
    output logic [1:0]  pixel_format,
    output logic        swap_pending,

    // Phase-4 cumulative perf counters (read-only MMIO window): fb_axi_reader
    // (3) + ddr_axi_arbiter_2m1s (9), routed in via gdu_top.
    input  logic [31:0] perf_rd_ar_txn,
    input  logic [31:0] perf_rd_beat,
    input  logic [31:0] perf_rd_wait,
    input  logic [31:0] perf_arb_gru_grant,
    input  logic [31:0] perf_arb_gdu_grant,
    input  logic [31:0] perf_arb_gru_wait,
    input  logic [31:0] perf_arb_gdu_wait,
    input  logic [31:0] perf_arb_gru_max_wait,
    input  logic [31:0] perf_arb_gdu_max_wait,
    input  logic [31:0] perf_arb_qos_override,
    input  logic [31:0] perf_arb_critical_override,
    input  logic [31:0] perf_arb_starvation_relief,

    input  logic        aclk,
    input  logic        aresetn
);

    logic busy;
    logic write_phase;
    logic req_is_read;
    logic [4:0]  req_id;
    logic [31:0] req_addr;
    logic [7:0]  req_len;
    logic [2:0]  req_size;
    logic [1:0]  req_burst;
    logic        req_lock;
    logic [3:0]  req_cache;
    logic [2:0]  req_prot;

    logic status_underflow;
    logic status_present_done;
    logic status_axi_error;
    logic status_swap_done;

    wire ar_enter = s_arvalid & s_arready;
    wire aw_enter = s_awvalid & s_awready;
    wire w_enter  = s_wvalid  & s_wready  & s_wlast;
    wire r_retire = s_rvalid  & s_rready  & s_rlast;
    wire b_retire = s_bvalid  & s_bready;

    assign s_arready = ~busy & (~req_is_read | ~s_awvalid);
    assign s_awready = ~busy & ( req_is_read | ~s_arvalid);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            busy      <= 1'b0;
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
            req_id      <= 5'd0;
            req_addr    <= 32'd0;
            req_len     <= 8'd0;
            req_size    <= 3'd0;
            req_burst   <= 2'd0;
            req_lock    <= 1'b0;
            req_cache   <= 4'd0;
            req_prot    <= 3'd0;
        end else if (ar_enter | aw_enter) begin
            req_is_read <= ar_enter;
            req_id      <= ar_enter ? s_arid    : s_awid;
            req_addr    <= ar_enter ? s_araddr  : s_awaddr;
            req_len     <= ar_enter ? s_arlen   : s_awlen;
            req_size    <= ar_enter ? s_arsize  : s_awsize;
            req_burst   <= ar_enter ? s_arburst : s_awburst;
            req_lock    <= ar_enter ? s_arlock  : s_awlock;
            req_cache   <= ar_enter ? s_arcache : s_awcache;
            req_prot    <= ar_enter ? s_arprot  : s_awprot;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            write_phase <= 1'b0;
            s_wready    <= 1'b0;
        end else begin
            if (aw_enter) begin
                write_phase <= 1'b1;
                s_wready    <= 1'b1;
            end else if (ar_enter) begin
                write_phase <= 1'b0;
                s_wready    <= 1'b0;
            end else if (w_enter) begin
                s_wready    <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_rvalid <= 1'b0;
            s_rlast  <= 1'b0;
            s_rdata  <= 32'd0;
        end else begin
            if (busy & ~write_phase & ~r_retire) begin
                s_rvalid <= 1'b1;
                s_rlast  <= 1'b1;
                case (req_addr[7:0])
                    8'h00: s_rdata <= {31'd0, gdu_enable};
                    8'h04: s_rdata <= {27'd0, swap_pending, status_swap_done, status_axi_error, status_present_done, status_underflow};
                    8'h08: s_rdata <= fb_base;
                    8'h0c: s_rdata <= stride;
                    8'h10: s_rdata <= {height, width};
                    8'h14: s_rdata <= {30'd0, pixel_format};
                    8'h18: s_rdata <= {31'd0, swap_pending};
                    // Phase-4 perf counter window (read-only, cumulative).
                    8'h20: s_rdata <= perf_rd_ar_txn;
                    8'h24: s_rdata <= perf_rd_beat;
                    8'h28: s_rdata <= perf_rd_wait;
                    8'h2c: s_rdata <= perf_arb_gru_grant;
                    8'h30: s_rdata <= perf_arb_gdu_grant;
                    8'h34: s_rdata <= perf_arb_gru_wait;
                    8'h38: s_rdata <= perf_arb_gdu_wait;
                    8'h3c: s_rdata <= perf_arb_gru_max_wait;
                    8'h40: s_rdata <= perf_arb_gdu_max_wait;
                    8'h44: s_rdata <= perf_arb_qos_override;
                    8'h48: s_rdata <= perf_arb_critical_override;
                    8'h4c: s_rdata <= perf_arb_starvation_relief;
                    default: s_rdata <= 32'd0;
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

    assign s_rid   = req_id;
    assign s_bid   = req_id;
    assign s_rresp = 2'b00;
    assign s_bresp = 2'b00;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            gdu_enable <= 1'b0;
            fb_base    <= DEFAULT_FB_BASE;
            stride     <= DEFAULT_STRIDE;
            width      <= DEFAULT_WIDTH;
            height     <= DEFAULT_HEIGHT;
            pixel_format <= DEFAULT_PIXEL_FORMAT;
            status_underflow   <= 1'b0;
            status_present_done <= 1'b0;
            status_axi_error   <= 1'b0;
            status_swap_done   <= 1'b0;
            swap_pending       <= 1'b0;
        end else begin
            if (fifo_underflow) status_underflow <= 1'b1;
            if (present_done)   status_present_done <= 1'b1;
            if (axi_error)      status_axi_error <= 1'b1;
            if (swap_done) begin
                status_swap_done <= 1'b1;
                swap_pending <= 1'b0;
            end

            if (w_enter) begin
                case (req_addr[7:0])
                    8'h00: begin
                        gdu_enable <= s_wdata[0];
                        if (!s_wdata[0]) begin
                            status_underflow <= 1'b0;
                            status_present_done <= 1'b0;
                            status_axi_error <= 1'b0;
                            status_swap_done <= 1'b0;
                            swap_pending <= 1'b0;
                        end
                    end
                    8'h08: fb_base <= s_wdata;
                    8'h0c: stride  <= s_wdata;
                    8'h10: begin
                        width  <= s_wdata[15:0];
                        height <= s_wdata[31:16];
                    end
                    8'h14: pixel_format <= s_wdata[1:0];
                    8'h18: begin
                        if (s_wdata[0]) begin
                            swap_pending <= 1'b1;
                            status_underflow <= 1'b0;
                            status_axi_error <= 1'b0;
                            status_swap_done <= 1'b0;
                            status_present_done <= 1'b0;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
