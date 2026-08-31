module ddr_axi_arbiter_2m1s (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        gdu_fifo_critical,
    input  logic        gdu_fifo_low,

    input  logic [4:0]  m0_axi_arid,
    input  logic [31:0] m0_axi_araddr,
    input  logic [7:0]  m0_axi_arlen,
    input  logic [2:0]  m0_axi_arsize,
    input  logic [1:0]  m0_axi_arburst,
    input  logic        m0_axi_arlock,
    input  logic [3:0]  m0_axi_arcache,
    input  logic [2:0]  m0_axi_arprot,
    input  logic        m0_axi_arvalid,
    output logic        m0_axi_arready,
    output logic [4:0]  m0_axi_rid,
    output logic [127:0] m0_axi_rdata,
    output logic [1:0]  m0_axi_rresp,
    output logic        m0_axi_rlast,
    output logic        m0_axi_rvalid,
    input  logic        m0_axi_rready,

    input  logic [4:0]  m0_axi_awid,
    input  logic [31:0] m0_axi_awaddr,
    input  logic [7:0]  m0_axi_awlen,
    input  logic [2:0]  m0_axi_awsize,
    input  logic [1:0]  m0_axi_awburst,
    input  logic        m0_axi_awlock,
    input  logic [3:0]  m0_axi_awcache,
    input  logic [2:0]  m0_axi_awprot,
    input  logic        m0_axi_awvalid,
    output logic        m0_axi_awready,
    input  logic [127:0] m0_axi_wdata,
    input  logic [15:0]  m0_axi_wstrb,
    input  logic        m0_axi_wlast,
    input  logic        m0_axi_wvalid,
    output logic        m0_axi_wready,
    output logic [4:0]  m0_axi_bid,
    output logic [1:0]  m0_axi_bresp,
    output logic        m0_axi_bvalid,
    input  logic        m0_axi_bready,

    input  logic [4:0]  m1_axi_arid,
    input  logic [31:0] m1_axi_araddr,
    input  logic [7:0]  m1_axi_arlen,
    input  logic [2:0]  m1_axi_arsize,
    input  logic [1:0]  m1_axi_arburst,
    input  logic        m1_axi_arlock,
    input  logic [3:0]  m1_axi_arcache,
    input  logic [2:0]  m1_axi_arprot,
    input  logic        m1_axi_arvalid,
    output logic        m1_axi_arready,
    output logic [4:0]  m1_axi_rid,
    output logic [127:0] m1_axi_rdata,
    output logic [1:0]  m1_axi_rresp,
    output logic        m1_axi_rlast,
    output logic        m1_axi_rvalid,
    input  logic        m1_axi_rready,

    output logic [4:0]  s0_axi_arid,
    output logic [31:0] s0_axi_araddr,
    output logic [7:0]  s0_axi_arlen,
    output logic [2:0]  s0_axi_arsize,
    output logic [1:0]  s0_axi_arburst,
    output logic        s0_axi_arlock,
    output logic [3:0]  s0_axi_arcache,
    output logic [2:0]  s0_axi_arprot,
    output logic        s0_axi_arvalid,
    input  logic        s0_axi_arready,
    input  logic [4:0]  s0_axi_rid,
    input  logic [127:0] s0_axi_rdata,
    input  logic [1:0]  s0_axi_rresp,
    input  logic        s0_axi_rlast,
    input  logic        s0_axi_rvalid,
    output logic        s0_axi_rready,

    output logic [4:0]  s0_axi_awid,
    output logic [31:0] s0_axi_awaddr,
    output logic [7:0]  s0_axi_awlen,
    output logic [2:0]  s0_axi_awsize,
    output logic [1:0]  s0_axi_awburst,
    output logic        s0_axi_awlock,
    output logic [3:0]  s0_axi_awcache,
    output logic [2:0]  s0_axi_awprot,
    output logic        s0_axi_awvalid,
    input  logic        s0_axi_awready,
    output logic [127:0] s0_axi_wdata,
    output logic [15:0]  s0_axi_wstrb,
    output logic        s0_axi_wlast,
    output logic        s0_axi_wvalid,
    input  logic        s0_axi_wready,
    input  logic [4:0]  s0_axi_bid,
    input  logic [1:0]  s0_axi_bresp,
    input  logic        s0_axi_bvalid,
    output logic        s0_axi_bready,

    // -------------------------------------------------------------------------
    // Phase-4 cumulative performance counters (reset only on `!aresetn`).
    // Exposed via the GDU perf MMIO window so software / 3D demos can monitor
    // GRU↔GDU DDR read-arbitration behaviour without a waveform or testbench.
    // (gru/gdu_wait_streak below are internal scratch for max_wait, not exposed.)
    // -------------------------------------------------------------------------
    output logic [31:0] gru_read_grant_count,
    output logic [31:0] gdu_read_grant_count,
    output logic [31:0] gru_wait_cycle_count,
    output logic [31:0] gdu_wait_cycle_count,
    output logic [31:0] gru_max_wait_cycles,
    output logic [31:0] gdu_max_wait_cycles,
    output logic [31:0] gdu_qos_override_count,
    output logic [31:0] gdu_critical_override_count,
    output logic [31:0] gru_starvation_relief_count
);

    logic read_busy;
    logic read_sel_m1;
    logic prefer_m1;
    logic [2:0] gdu_consecutive_grants;

    // Cumulative perf counters (declared as output ports above) plus two
    // internal streak accumulators that feed gru/gdu_max_wait_cycles.
    logic [31:0] gru_wait_streak;
    logic [31:0] gdu_wait_streak;

    localparam logic [2:0] MAX_GDU_CONSECUTIVE_GRANTS = 3'd4;

    wire rr_choose_m1 = m1_axi_arvalid & (~m0_axi_arvalid | prefer_m1);
    wire rr_choose_m0 = m0_axi_arvalid & (~m1_axi_arvalid | ~prefer_m1);
    wire low_water_relief = gdu_fifo_low && !gdu_fifo_critical &&
                            m0_axi_arvalid && m1_axi_arvalid &&
                            (gdu_consecutive_grants >= MAX_GDU_CONSECUTIVE_GRANTS);
    wire choose_m1 = gdu_fifo_critical ? m1_axi_arvalid :
                     gdu_fifo_low      ? (m1_axi_arvalid && !low_water_relief) || (!m0_axi_arvalid && m1_axi_arvalid) :
                                         rr_choose_m1;
    wire choose_m0 = gdu_fifo_critical ? (~m1_axi_arvalid && m0_axi_arvalid) :
                     gdu_fifo_low      ? m0_axi_arvalid && (!m1_axi_arvalid || low_water_relief) :
                                         rr_choose_m0;
    wire ar_fire   = s0_axi_arvalid & s0_axi_arready;
    wire r_last_fire = s0_axi_rvalid & s0_axi_rready & s0_axi_rlast;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            read_busy   <= 1'b0;
            read_sel_m1 <= 1'b0;
            prefer_m1   <= 1'b1;
            gdu_consecutive_grants <= 3'd0;
        end else begin
            if (~read_busy && ar_fire) begin
                read_busy   <= 1'b1;
                read_sel_m1 <= choose_m1;
                if (!gdu_fifo_low) begin
                    prefer_m1 <= ~choose_m1;
                end
                if (choose_m1) begin
                    if (gdu_consecutive_grants < MAX_GDU_CONSECUTIVE_GRANTS) begin
                        gdu_consecutive_grants <= gdu_consecutive_grants + 1'b1;
                    end
                end else begin
                    gdu_consecutive_grants <= 3'd0;
                end
            end else if (read_busy && r_last_fire) begin
                read_busy <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            gru_read_grant_count <= 32'd0;
            gdu_read_grant_count <= 32'd0;
            gru_wait_cycle_count <= 32'd0;
            gdu_wait_cycle_count <= 32'd0;
            gru_max_wait_cycles  <= 32'd0;
            gdu_max_wait_cycles  <= 32'd0;
            gru_wait_streak      <= 32'd0;
            gdu_wait_streak      <= 32'd0;
            gdu_qos_override_count <= 32'd0;
            gdu_critical_override_count <= 32'd0;
            gru_starvation_relief_count <= 32'd0;
        end else begin
            if (m0_axi_arvalid && !m0_axi_arready) begin
                gru_wait_cycle_count <= gru_wait_cycle_count + 1'b1;
                gru_wait_streak <= gru_wait_streak + 1'b1;
            end else begin
                if (gru_wait_streak > gru_max_wait_cycles) begin
                    gru_max_wait_cycles <= gru_wait_streak;
                end
                gru_wait_streak <= 32'd0;
            end

            if (m1_axi_arvalid && !m1_axi_arready) begin
                gdu_wait_cycle_count <= gdu_wait_cycle_count + 1'b1;
                gdu_wait_streak <= gdu_wait_streak + 1'b1;
            end else begin
                if (gdu_wait_streak > gdu_max_wait_cycles) begin
                    gdu_max_wait_cycles <= gdu_wait_streak;
                end
                gdu_wait_streak <= 32'd0;
            end

            if (m0_axi_arvalid && m0_axi_arready) begin
                gru_read_grant_count <= gru_read_grant_count + 1'b1;
            end
            if (m1_axi_arvalid && m1_axi_arready) begin
                gdu_read_grant_count <= gdu_read_grant_count + 1'b1;
            end
            if (ar_fire && gdu_fifo_low && !gdu_fifo_critical && choose_m1 && m0_axi_arvalid) begin
                gdu_qos_override_count <= gdu_qos_override_count + 1'b1;
            end
            if (ar_fire && gdu_fifo_critical && choose_m1 && m0_axi_arvalid) begin
                gdu_critical_override_count <= gdu_critical_override_count + 1'b1;
            end
            if (ar_fire && low_water_relief && choose_m0) begin
                gru_starvation_relief_count <= gru_starvation_relief_count + 1'b1;
            end
        end
    end

    assign s0_axi_arvalid = ~read_busy & (choose_m1 | choose_m0);
    assign s0_axi_arid    = choose_m1 ? m1_axi_arid    : m0_axi_arid;
    assign s0_axi_araddr  = choose_m1 ? m1_axi_araddr  : m0_axi_araddr;
    assign s0_axi_arlen   = choose_m1 ? m1_axi_arlen   : m0_axi_arlen;
    assign s0_axi_arsize  = choose_m1 ? m1_axi_arsize  : m0_axi_arsize;
    assign s0_axi_arburst = choose_m1 ? m1_axi_arburst : m0_axi_arburst;
    assign s0_axi_arlock  = choose_m1 ? m1_axi_arlock  : m0_axi_arlock;
    assign s0_axi_arcache = choose_m1 ? m1_axi_arcache : m0_axi_arcache;
    assign s0_axi_arprot  = choose_m1 ? m1_axi_arprot  : m0_axi_arprot;

    assign m1_axi_arready = ~read_busy & choose_m1 & s0_axi_arready;
    assign m0_axi_arready = ~read_busy & ~choose_m1 & choose_m0 & s0_axi_arready;

    assign m1_axi_rvalid = read_busy &  read_sel_m1 & s0_axi_rvalid;
    assign m0_axi_rvalid = read_busy & ~read_sel_m1 & s0_axi_rvalid;
    assign m1_axi_rid    = s0_axi_rid;
    assign m0_axi_rid    = s0_axi_rid;
    assign m1_axi_rdata  = s0_axi_rdata;
    assign m0_axi_rdata  = s0_axi_rdata;
    assign m1_axi_rresp  = s0_axi_rresp;
    assign m0_axi_rresp  = s0_axi_rresp;
    assign m1_axi_rlast  = s0_axi_rlast;
    assign m0_axi_rlast  = s0_axi_rlast;
    assign s0_axi_rready = read_sel_m1 ? m1_axi_rready : m0_axi_rready;

    assign s0_axi_awid    = m0_axi_awid;
    assign s0_axi_awaddr  = m0_axi_awaddr;
    assign s0_axi_awlen   = m0_axi_awlen;
    assign s0_axi_awsize  = m0_axi_awsize;
    assign s0_axi_awburst = m0_axi_awburst;
    assign s0_axi_awlock  = m0_axi_awlock;
    assign s0_axi_awcache = m0_axi_awcache;
    assign s0_axi_awprot  = m0_axi_awprot;
    assign s0_axi_awvalid = m0_axi_awvalid;
    assign m0_axi_awready = s0_axi_awready;

    assign s0_axi_wdata  = m0_axi_wdata;
    assign s0_axi_wstrb  = m0_axi_wstrb;
    assign s0_axi_wlast  = m0_axi_wlast;
    assign s0_axi_wvalid = m0_axi_wvalid;
    assign m0_axi_wready = s0_axi_wready;

    assign m0_axi_bid    = s0_axi_bid;
    assign m0_axi_bresp  = s0_axi_bresp;
    assign m0_axi_bvalid = s0_axi_bvalid;
    assign s0_axi_bready = m0_axi_bready;

endmodule
