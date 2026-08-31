module scene_sk_top #(
 parameter int MAX_VERTICES=128, parameter int MAX_TRIANGLES=192, parameter logic [31:0] MODEL_BASE=32'h0040_0000
) (
 input logic clk,input logic resetn,
 input logic s_awvalid,output logic s_awready,input logic [31:0] s_awaddr,input logic [4:0] s_awid,input logic [7:0] s_awlen,input logic [2:0] s_awsize,input logic [1:0] s_awburst,input logic s_awlock,input logic [3:0] s_awcache,input logic [2:0] s_awprot,input logic s_wvalid,output logic s_wready,input logic [31:0] s_wdata,input logic [3:0] s_wstrb,input logic s_wlast,output logic s_bvalid,input logic s_bready,output logic [4:0] s_bid,output logic [1:0] s_bresp,input logic s_arvalid,output logic s_arready,input logic [31:0] s_araddr,input logic [4:0] s_arid,input logic [7:0] s_arlen,input logic [2:0] s_arsize,input logic [1:0] s_arburst,input logic s_arlock,input logic [3:0] s_arcache,input logic [2:0] s_arprot,output logic s_rvalid,input logic s_rready,output logic [31:0] s_rdata,output logic [4:0] s_rid,output logic [1:0] s_rresp,output logic s_rlast,
 output logic [4:0] m_axi_arid,output logic [31:0] m_axi_araddr,output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize,output logic [1:0] m_axi_arburst,output logic m_axi_arlock,output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot,output logic m_axi_arvalid,input logic m_axi_arready,input logic [4:0] m_axi_rid,input logic [31:0] m_axi_rdata,input logic [1:0] m_axi_rresp,input logic m_axi_rlast,input logic m_axi_rvalid,output logic m_axi_rready,
 output logic dvi_clk,output logic dvi_hs,output logic dvi_vs,output logic dvi_de,output logic [7:0] dvi_d
);
 logic mmio_valid,mmio_we,mmio_ready,irq_done,err_active_write; logic [31:0] mmio_addr,mmio_wdata,mmio_rdata;
 scene_ctrl_top #(.MAX_VERTICES(MAX_VERTICES),.MAX_TRIANGLES(MAX_TRIANGLES),.MODEL_BASE(MODEL_BASE)) u_scene(.*);
 sketch_book_top u_sketch(.clk,.resetn,.mmio_valid,.mmio_we,.mmio_addr,.mmio_wdata,.mmio_rdata,.mmio_ready,.dvi_clk,.dvi_hs,.dvi_vs,.dvi_de,.dvi_d,.irq_done,.err_active_write);
endmodule
