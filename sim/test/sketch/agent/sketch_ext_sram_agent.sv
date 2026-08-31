// Reusable read-only external SRAM endpoint for SketchBook scene masters.
module sketch_ext_sram_agent #(
    parameter string INIT_FILE="",
    parameter int AW=18
) (
    input logic clk, input logic resetn,
    input logic [4:0] s_arid, input logic [31:0] s_araddr, input logic [7:0] s_arlen,
    input logic [2:0] s_arsize, input logic [1:0] s_arburst, input logic s_arlock,
    input logic [3:0] s_arcache, input logic [2:0] s_arprot, input logic s_arvalid, output logic s_arready,
    output logic [4:0] s_rid, output logic [31:0] s_rdata, output logic [1:0] s_rresp,
    output logic s_rlast, output logic s_rvalid, input logic s_rready
);
    logic req,we; logic [31:0] addr,data_o,data_i; logic [3:0] be;
    wire [19:0] ram_addr=addr[21:2]; wire [3:0] ram_be_n=we ? ~be : 4'b0000;
    wire ram_ce_n=~req, ram_oe_n=we, ram_we_n=~we; wire [31:0] ram_data;
    axi2sram_sp_external #(.AXI_ID_WIDTH(5),.AXI_ADDR_WIDTH(32),.AXI_DATA_WIDTH(32)) u_bridge(
      .clk,.resetn,.s_araddr,.s_arburst,.s_arcache,.s_arid,.s_arlen,.s_arlock,.s_arprot,.s_arready,.s_arsize,.s_arvalid,
      .s_awaddr(32'd0),.s_awburst(2'd0),.s_awcache(4'd0),.s_awid(5'd0),.s_awlen(8'd0),.s_awlock(1'b0),.s_awprot(3'd0),.s_awready(),.s_awsize(3'd2),.s_awvalid(1'b0),
      .s_bid(),.s_bready(1'b1),.s_bresp(),.s_bvalid(),.s_rdata,.s_rid,.s_rlast,.s_rready,.s_rresp,.s_rvalid,
      .s_wdata(32'd0),.s_wlast(1'b1),.s_wready(),.s_wstrb(4'd0),.s_wvalid(1'b0),.req_o(req),.we_o(we),.addr_o(addr),.be_o(be),.data_o(data_o),.data_i(data_i)
    );
    assign ram_data = (req && we) ? data_o : 32'hzzzz_zzzz;
    assign data_i=ram_data;
    sram_sp #(.AW(AW),.Init_File(INIT_FILE)) u_sram(.ram_addr,.ram_be_n,.ram_ce_n,.ram_oe_n,.ram_we_n,.ram_data);
endmodule
