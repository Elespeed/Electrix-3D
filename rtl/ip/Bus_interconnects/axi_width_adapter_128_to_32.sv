// Converts one 128-bit AXI master into a 32-bit AXI master.
//
// The graphics engines keep their cache-line-oriented 128-bit internal
// interface, while the physical ExtRAM is a 32-bit asynchronous SRAM.  This
// adapter makes that boundary explicit: every wide beat is transferred as four
// ordered 32-bit beats and read data is reassembled before it is returned.
module axi_width_adapter_128_to_32 (
    input  logic         aclk,
    input  logic         aresetn,

    input  logic [4:0]   s_axi_arid,
    input  logic [31:0]  s_axi_araddr,
    input  logic [7:0]   s_axi_arlen,
    input  logic [2:0]   s_axi_arsize,
    input  logic [1:0]   s_axi_arburst,
    input  logic         s_axi_arlock,
    input  logic [3:0]   s_axi_arcache,
    input  logic [2:0]   s_axi_arprot,
    input  logic         s_axi_arvalid,
    output logic         s_axi_arready,
    output logic [4:0]   s_axi_rid,
    output logic [127:0] s_axi_rdata,
    output logic [1:0]   s_axi_rresp,
    output logic         s_axi_rlast,
    output logic         s_axi_rvalid,
    input  logic         s_axi_rready,

    input  logic [4:0]   s_axi_awid,
    input  logic [31:0]  s_axi_awaddr,
    input  logic [7:0]   s_axi_awlen,
    input  logic [2:0]   s_axi_awsize,
    input  logic [1:0]   s_axi_awburst,
    input  logic         s_axi_awlock,
    input  logic [3:0]   s_axi_awcache,
    input  logic [2:0]   s_axi_awprot,
    input  logic         s_axi_awvalid,
    output logic         s_axi_awready,
    input  logic [127:0] s_axi_wdata,
    input  logic [15:0]  s_axi_wstrb,
    input  logic         s_axi_wlast,
    input  logic         s_axi_wvalid,
    output logic         s_axi_wready,
    output logic [4:0]   s_axi_bid,
    output logic [1:0]   s_axi_bresp,
    output logic         s_axi_bvalid,
    input  logic         s_axi_bready,

    output logic [4:0]   m_axi_arid,
    output logic [31:0]  m_axi_araddr,
    output logic [7:0]   m_axi_arlen,
    output logic [2:0]   m_axi_arsize,
    output logic [1:0]   m_axi_arburst,
    output logic         m_axi_arlock,
    output logic [3:0]   m_axi_arcache,
    output logic [2:0]   m_axi_arprot,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,
    input  logic [4:0]   m_axi_rid,
    input  logic [31:0]  m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rlast,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,

    output logic [4:0]   m_axi_awid,
    output logic [31:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic [2:0]   m_axi_awsize,
    output logic [1:0]   m_axi_awburst,
    output logic         m_axi_awlock,
    output logic [3:0]   m_axi_awcache,
    output logic [2:0]   m_axi_awprot,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,
    output logic [31:0]  m_axi_wdata,
    output logic [3:0]   m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,
    input  logic [4:0]   m_axi_bid,
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready
);
    typedef enum logic [1:0] {R_IDLE, R_ADDR, R_COLLECT, R_RESP} rstate_t;
    typedef enum logic [2:0] {W_IDLE, W_ADDR, W_DATA, W_SEND, W_RESP} wstate_t;
    rstate_t rstate;
    wstate_t wstate;

    logic [4:0] r_id;
    logic [31:0] r_addr;
    logic [7:0] r_len;
    logic [1:0] r_burst;
    logic r_lock;
    logic [3:0] r_cache;
    logic [2:0] r_prot;
    logic [8:0] r_wide_left;
    logic [1:0] r_word_idx;
    logic [127:0] r_data;
    logic [1:0] r_resp;
    logic [4:0] w_id;
    logic [31:0] w_addr;
    logic [7:0] w_len;
    logic [1:0] w_burst;
    logic w_lock;
    logic [3:0] w_cache;
    logic [2:0] w_prot;
    logic [127:0] w_data;
    logic [15:0] w_strb;
    logic w_last;
    logic [1:0] w_word_idx;

    // Wide graphics bursts are intentionally capped to 63 beats by the
    // engines, hence the multiplied narrow burst always fits AXI LEN.
    assign s_axi_arready = (rstate == R_IDLE);
    assign m_axi_arid    = r_id;
    assign m_axi_araddr  = r_addr;
    assign m_axi_arlen   = ({1'b0, r_len} + 9'd1) * 4 - 9'd1;
    assign m_axi_arsize  = 3'd2;
    assign m_axi_arburst = r_burst;
    assign m_axi_arlock  = r_lock;
    assign m_axi_arcache = r_cache;
    assign m_axi_arprot  = r_prot;
    assign m_axi_arvalid = (rstate == R_ADDR);
    assign m_axi_rready  = (rstate == R_COLLECT);
    assign s_axi_rid     = r_id;
    assign s_axi_rdata   = r_data;
    assign s_axi_rresp   = r_resp;
    assign s_axi_rvalid  = (rstate == R_RESP);
    assign s_axi_rlast   = (rstate == R_RESP) && (r_wide_left == 9'd1);

    assign s_axi_awready = (wstate == W_IDLE);
    assign m_axi_awid    = w_id;
    assign m_axi_awaddr  = w_addr;
    assign m_axi_awlen   = ({1'b0, w_len} + 9'd1) * 4 - 9'd1;
    assign m_axi_awsize  = 3'd2;
    assign m_axi_awburst = w_burst;
    assign m_axi_awlock  = w_lock;
    assign m_axi_awcache = w_cache;
    assign m_axi_awprot  = w_prot;
    assign m_axi_awvalid = (wstate == W_ADDR);
    assign s_axi_wready  = (wstate == W_DATA);
    assign m_axi_wdata   = w_data[32*w_word_idx +: 32];
    assign m_axi_wstrb   = w_strb[4*w_word_idx +: 4];
    assign m_axi_wvalid  = (wstate == W_SEND);
    assign m_axi_wlast   = (wstate == W_SEND) && w_last && (w_word_idx == 2'd3);
    assign m_axi_bready  = (wstate == W_RESP) && s_axi_bready;
    assign s_axi_bid     = m_axi_bid;
    assign s_axi_bresp   = m_axi_bresp;
    assign s_axi_bvalid  = (wstate == W_RESP) && m_axi_bvalid;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate <= R_IDLE; r_id <= '0; r_addr <= '0; r_len <= '0;
            r_burst <= '0; r_lock <= 1'b0; r_cache <= '0; r_prot <= '0; r_wide_left <= '0;
            r_word_idx <= '0; r_data <= '0; r_resp <= '0;
            wstate <= W_IDLE; w_id <= '0; w_addr <= '0; w_len <= '0;
            w_burst <= '0; w_lock <= 1'b0; w_cache <= '0; w_prot <= '0;
            w_data <= '0; w_strb <= '0;
            w_last <= 1'b0; w_word_idx <= '0;
        end else begin
            case (rstate)
                R_IDLE: if (s_axi_arvalid) begin
                    r_id <= s_axi_arid;
                    r_addr <= s_axi_araddr;
                    r_len <= s_axi_arlen;
                    r_burst <= s_axi_arburst;
                    r_lock <= s_axi_arlock;
                    r_cache <= s_axi_arcache;
                    r_prot <= s_axi_arprot;
                    r_wide_left <= {1'b0, s_axi_arlen} + 9'd1;
                    r_word_idx <= 2'd0;
                    r_resp <= 2'b00;
                    rstate <= R_ADDR;
                end
                R_ADDR: if (m_axi_arready) rstate <= R_COLLECT;
                R_COLLECT: if (m_axi_rvalid) begin
                    r_data[32*r_word_idx +: 32] <= m_axi_rdata;
                    r_resp <= r_resp | m_axi_rresp;
                    if (r_word_idx == 2'd3) begin
                        r_word_idx <= 2'd0;
                        rstate <= R_RESP;
                    end else r_word_idx <= r_word_idx + 2'd1;
                end
                R_RESP: if (s_axi_rready) begin
                    r_wide_left <= r_wide_left - 9'd1;
                    r_resp <= 2'b00;
                    rstate <= (r_wide_left == 9'd1) ? R_IDLE : R_COLLECT;
                end
                default: rstate <= R_IDLE;
            endcase
            case (wstate)
                W_IDLE: if (s_axi_awvalid) begin
                    w_id <= s_axi_awid;
                    w_addr <= s_axi_awaddr;
                    w_len <= s_axi_awlen;
                    w_burst <= s_axi_awburst;
                    w_lock <= s_axi_awlock;
                    w_cache <= s_axi_awcache;
                    w_prot <= s_axi_awprot;
                    wstate <= W_ADDR;
                end
                W_ADDR: if (m_axi_awready) wstate <= W_DATA;
                W_DATA: if (s_axi_wvalid) begin
                    w_data <= s_axi_wdata;
                    w_strb <= s_axi_wstrb;
                    w_last <= s_axi_wlast;
                    w_word_idx <= 2'd0;
                    wstate <= W_SEND;
                end
                W_SEND: if (m_axi_wready) begin
                    if (w_word_idx == 2'd3) begin
                        wstate <= w_last ? W_RESP : W_DATA;
                    end else w_word_idx <= w_word_idx + 2'd1;
                end
                W_RESP: if (m_axi_bvalid && s_axi_bready) wstate <= W_IDLE;
                default: wstate <= W_IDLE;
            endcase
        end
    end
endmodule
