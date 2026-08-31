// AXI4 (single-beat) wrapper for the sketch_book MMIO register bank.
// The system crossbar already decodes the 0x1f10_0000 window.  Bursts are
// deliberately rejected with SLVERR rather than being silently truncated.
module sketch_book_axi (
    input  logic        clk,
    input  logic        resetn,
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
    output logic        mmio_valid,
    output logic        mmio_we,
    output logic [31:0] mmio_addr,
    output logic [31:0] mmio_wdata,
    input  logic [31:0] mmio_rdata,
    input  logic        mmio_ready
);
    logic        wr_addr_valid, wr_error, rd_error;
    logic [31:0] wr_addr;
    logic [4:0]  wr_id, rd_id;

    assign s_awready = !wr_addr_valid && !s_bvalid && !s_rvalid;
    assign s_wready  = wr_addr_valid && !s_bvalid;
    assign s_arready = !wr_addr_valid && !s_bvalid && !s_rvalid;
    assign mmio_valid = (wr_addr_valid && s_wvalid && !wr_error) ||
                        (s_arvalid && s_arready && !((s_arlen != 0) || (s_arsize != 3'd2) || (s_arburst != 2'b01)));
    assign mmio_we = wr_addr_valid && s_wvalid && !wr_error;
    assign mmio_addr = mmio_we ? wr_addr : s_araddr;
    assign mmio_wdata = s_wdata;
    assign s_bid = wr_id;
    assign s_rid = rd_id;
    assign s_rlast = 1'b1;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_addr_valid <= 1'b0;
            wr_error <= 1'b0;
            rd_error <= 1'b0;
            wr_addr <= '0;
            wr_id <= '0;
            rd_id <= '0;
            s_bvalid <= 1'b0;
            s_bresp <= 2'b00;
            s_rvalid <= 1'b0;
            s_rresp <= 2'b00;
            s_rdata <= '0;
        end else begin
            if (s_awvalid && s_awready) begin
                wr_addr_valid <= 1'b1;
                wr_addr <= s_awaddr;
                wr_id <= s_awid;
                wr_error <= (s_awlen != 0) || (s_awsize != 3'd2) || (s_awburst != 2'b01);
            end
            if (wr_addr_valid && s_wvalid && s_wready && (wr_error || mmio_ready)) begin
                wr_addr_valid <= 1'b0;
                s_bvalid <= 1'b1;
                s_bresp <= (wr_error || !s_wlast || (s_wstrb != 4'hf)) ? 2'b10 : 2'b00;
            end
            if (s_bvalid && s_bready)
                s_bvalid <= 1'b0;

            if (s_arvalid && s_arready) begin
                rd_id <= s_arid;
                rd_error <= (s_arlen != 0) || (s_arsize != 3'd2) || (s_arburst != 2'b01);
                if ((s_arlen != 0) || (s_arsize != 3'd2) || (s_arburst != 2'b01) || mmio_ready) begin
                    s_rvalid <= 1'b1;
                    s_rresp <= ((s_arlen != 0) || (s_arsize != 3'd2) || (s_arburst != 2'b01)) ? 2'b10 : 2'b00;
                    s_rdata <= mmio_rdata;
                end
            end
            if (s_rvalid && s_rready)
                s_rvalid <= 1'b0;
        end
    end
endmodule
