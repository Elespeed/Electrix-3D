// Scene-owned ExtRAM fetch stage.  It intentionally preserves the one
// outstanding AXI read contract of the original reader while giving the Scene
// pipeline an independently named, reusable fetch boundary.
module scene_ctrl_model_fetcher (
    input logic clk, input logic resetn, input logic rd_start, input logic [31:0] rd_addr,
    output logic rd_busy, output logic rd_valid, output logic [31:0] rd_data, output logic rd_error,
    output logic [4:0] m_axi_arid, output logic [31:0] m_axi_araddr, output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize, output logic [1:0] m_axi_arburst, output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache, output logic [2:0] m_axi_arprot, output logic m_axi_arvalid,
    input logic m_axi_arready, input logic [4:0] m_axi_rid, input logic [31:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp, input logic m_axi_rlast, input logic m_axi_rvalid, output logic m_axi_rready
);
    model_scene_axi_reader u_axi_reader (.*);
endmodule
