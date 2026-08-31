// Combines the CPU's narrow-DDR adapter with the existing GRU DDR master.
// Only one transaction per channel is forwarded at a time, which matches the
// single-outstanding-transaction contract of ddr_axi_arbiter_2m1s.  GDU stays
// on m1 of that arbiter, retaining its FIFO-low/critical QoS policy.
module ddr_axi_cpu_gru_mux (
    input  logic aclk, input logic aresetn,
    input  logic [4:0] m0_arid, input logic [31:0] m0_araddr, input logic [7:0] m0_arlen, input logic [2:0] m0_arsize, input logic [1:0] m0_arburst, input logic m0_arlock, input logic [3:0] m0_arcache, input logic [2:0] m0_arprot, input logic m0_arvalid, output logic m0_arready, output logic [4:0] m0_rid, output logic [127:0] m0_rdata, output logic [1:0] m0_rresp, output logic m0_rlast, output logic m0_rvalid, input logic m0_rready,
    input  logic [4:0] m0_awid, input logic [31:0] m0_awaddr, input logic [7:0] m0_awlen, input logic [2:0] m0_awsize, input logic [1:0] m0_awburst, input logic m0_awlock, input logic [3:0] m0_awcache, input logic [2:0] m0_awprot, input logic m0_awvalid, output logic m0_awready, input logic [127:0] m0_wdata, input logic [15:0] m0_wstrb, input logic m0_wlast, input logic m0_wvalid, output logic m0_wready, output logic [4:0] m0_bid, output logic [1:0] m0_bresp, output logic m0_bvalid, input logic m0_bready,
    input  logic [4:0] m1_arid, input logic [31:0] m1_araddr, input logic [7:0] m1_arlen, input logic [2:0] m1_arsize, input logic [1:0] m1_arburst, input logic m1_arlock, input logic [3:0] m1_arcache, input logic [2:0] m1_arprot, input logic m1_arvalid, output logic m1_arready, output logic [4:0] m1_rid, output logic [127:0] m1_rdata, output logic [1:0] m1_rresp, output logic m1_rlast, output logic m1_rvalid, input logic m1_rready,
    input  logic [4:0] m1_awid, input logic [31:0] m1_awaddr, input logic [7:0] m1_awlen, input logic [2:0] m1_awsize, input logic [1:0] m1_awburst, input logic m1_awlock, input logic [3:0] m1_awcache, input logic [2:0] m1_awprot, input logic m1_awvalid, output logic m1_awready, input logic [127:0] m1_wdata, input logic [15:0] m1_wstrb, input logic m1_wlast, input logic m1_wvalid, output logic m1_wready, output logic [4:0] m1_bid, output logic [1:0] m1_bresp, output logic m1_bvalid, input logic m1_bready,
    output logic [4:0] s_arid, output logic [31:0] s_araddr, output logic [7:0] s_arlen, output logic [2:0] s_arsize, output logic [1:0] s_arburst, output logic s_arlock, output logic [3:0] s_arcache, output logic [2:0] s_arprot, output logic s_arvalid, input logic s_arready, input logic [4:0] s_rid, input logic [127:0] s_rdata, input logic [1:0] s_rresp, input logic s_rlast, input logic s_rvalid, output logic s_rready,
    output logic [4:0] s_awid, output logic [31:0] s_awaddr, output logic [7:0] s_awlen, output logic [2:0] s_awsize, output logic [1:0] s_awburst, output logic s_awlock, output logic [3:0] s_awcache, output logic [2:0] s_awprot, output logic s_awvalid, input logic s_awready, output logic [127:0] s_wdata, output logic [15:0] s_wstrb, output logic s_wlast, output logic s_wvalid, input logic s_wready, input logic [4:0] s_bid, input logic [1:0] s_bresp, input logic s_bvalid, output logic s_bready
);
    logic read_busy, read_sel_m1, write_busy, write_sel_m1;
    logic prefer_m1;
    wire choose_m1_read = m1_arvalid && (!m0_arvalid || prefer_m1);
    wire choose_m1_write = m1_awvalid && (!m0_awvalid || prefer_m1);
    wire active_write_sel_m1 = write_busy ? write_sel_m1 : choose_m1_write;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            read_busy <= 1'b0; read_sel_m1 <= 1'b0;
            write_busy <= 1'b0; write_sel_m1 <= 1'b0; prefer_m1 <= 1'b1;
        end else begin
            if (!read_busy && s_arvalid && s_arready) begin
                read_busy <= 1'b1; read_sel_m1 <= choose_m1_read; prefer_m1 <= ~choose_m1_read;
            end else if (read_busy && s_rvalid && s_rready && s_rlast) begin
                read_busy <= 1'b0;
            end
            if (!write_busy && s_awvalid && s_awready) begin
                write_busy <= 1'b1; write_sel_m1 <= choose_m1_write; prefer_m1 <= ~choose_m1_write;
            end else if (write_busy && s_bvalid && s_bready) begin
                write_busy <= 1'b0;
            end
        end
    end

    always_comb begin
        s_arid=m0_arid; s_araddr=m0_araddr; s_arlen=m0_arlen; s_arsize=m0_arsize; s_arburst=m0_arburst; s_arlock=m0_arlock; s_arcache=m0_arcache; s_arprot=m0_arprot;
        if (choose_m1_read) begin s_arid=m1_arid; s_araddr=m1_araddr; s_arlen=m1_arlen; s_arsize=m1_arsize; s_arburst=m1_arburst; s_arlock=m1_arlock; s_arcache=m1_arcache; s_arprot=m1_arprot; end
        s_arvalid = !read_busy && (m0_arvalid || m1_arvalid);
        m0_arready = !read_busy && !choose_m1_read && s_arready;
        m1_arready = !read_busy &&  choose_m1_read && s_arready;
        m0_rid=s_rid; m0_rdata=s_rdata; m0_rresp=s_rresp; m0_rlast=s_rlast; m0_rvalid=read_busy && !read_sel_m1 && s_rvalid;
        m1_rid=s_rid; m1_rdata=s_rdata; m1_rresp=s_rresp; m1_rlast=s_rlast; m1_rvalid=read_busy &&  read_sel_m1 && s_rvalid;
        s_rready = read_sel_m1 ? m1_rready : m0_rready;

        s_awid=m0_awid; s_awaddr=m0_awaddr; s_awlen=m0_awlen; s_awsize=m0_awsize; s_awburst=m0_awburst; s_awlock=m0_awlock; s_awcache=m0_awcache; s_awprot=m0_awprot;
        s_wdata=m0_wdata; s_wstrb=m0_wstrb; s_wlast=m0_wlast;
        if (active_write_sel_m1) begin
            s_awid=m1_awid; s_awaddr=m1_awaddr; s_awlen=m1_awlen; s_awsize=m1_awsize; s_awburst=m1_awburst; s_awlock=m1_awlock; s_awcache=m1_awcache; s_awprot=m1_awprot;
            s_wdata=m1_wdata; s_wstrb=m1_wstrb; s_wlast=m1_wlast;
        end
        s_awvalid = !write_busy && (m0_awvalid || m1_awvalid);
        s_wvalid  = active_write_sel_m1 ? m1_wvalid : m0_wvalid;
        m0_awready = !write_busy && !choose_m1_write && s_awready;
        m1_awready = !write_busy &&  choose_m1_write && s_awready;
        m0_wready  = !active_write_sel_m1 && s_wready;
        m1_wready  =  active_write_sel_m1 && s_wready;
        m0_bid=s_bid; m0_bresp=s_bresp; m0_bvalid=write_busy && !write_sel_m1 && s_bvalid;
        m1_bid=s_bid; m1_bresp=s_bresp; m1_bvalid=write_busy &&  write_sel_m1 && s_bvalid;
        s_bready = write_sel_m1 ? m1_bready : m0_bready;
    end
endmodule
