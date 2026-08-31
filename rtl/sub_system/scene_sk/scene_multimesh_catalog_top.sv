// S3PK catalog selector for the standalone Scene/SketchBook system.  It owns
// the AXI read port only while parsing the package header and selected entry;
// the existing command renderer owns it for model loading and drawing.
module scene_multimesh_catalog_top #(
    parameter logic [31:0] PACKAGE_BASE = 32'h0040_0000,
    parameter logic [31:0] PACKAGE_SIZE = 32'd4096
) (
    input logic clk, input logic resetn,
    input logic catalog_load, input logic [3:0] model_select,
    output logic catalog_busy, output logic catalog_valid, output logic catalog_error,
    output logic [7:0] catalog_error_code, output logic [3:0] selected_model,
    output logic [31:0] selected_model_base, output logic [31:0] selected_model_size,
    input logic cmd_valid, input logic [127:0] cmd_data, output logic cmd_ready,
    input logic frame_start, output logic [4:0] cmd_level, output logic cmd_full,
    output logic busy, output logic frame_done, output logic error, output logic [7:0] error_code,
    output logic model_valid, output logic [3:0] mesh_count,
    output logic [4:0] m_axi_arid, output logic [31:0] m_axi_araddr, output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize, output logic [1:0] m_axi_arburst, output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache, output logic [2:0] m_axi_arprot, output logic m_axi_arvalid,
    input logic m_axi_arready, input logic [4:0] m_axi_rid, input logic [31:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp, input logic m_axi_rlast, input logic m_axi_rvalid, output logic m_axi_rready,
    output logic dvi_clk, output logic dvi_hs, output logic dvi_vs, output logic dvi_de, output logic [7:0] dvi_d
);
    localparam logic [31:0] S3PK_MAGIC = 32'h5333_504b;
    localparam logic [7:0] SK3D_V4 = 8'd4;
    typedef enum logic [3:0] {C_IDLE, C_HDR_REQ, C_HDR_WAIT, C_ENT_REQ, C_ENT_WAIT, C_START, C_WAIT, C_FAIL} cstate_t;
    cstate_t cstate;
    logic reader_start, reader_busy, reader_valid, reader_error;
    logic [31:0] reader_addr, reader_data, header_words [0:3], entry_words [0:3];
    logic [2:0] word_index; logic [3:0] active_select, pending_select; logic catalog_pending;
    logic child_load_start;
    logic [4:0] c_arid; logic [31:0] c_araddr; logic [7:0] c_arlen; logic [2:0] c_arsize; logic [1:0] c_arburst; logic c_arlock; logic [3:0] c_arcache; logic [2:0] c_arprot; logic c_arvalid, c_arready, c_rlast, c_rvalid, c_rready; logic [4:0] c_rid; logic [31:0] c_rdata; logic [1:0] c_rresp;
    logic [4:0] e_arid; logic [31:0] e_araddr; logic [7:0] e_arlen; logic [2:0] e_arsize; logic [1:0] e_arburst; logic e_arlock; logic [3:0] e_arcache; logic [2:0] e_arprot; logic e_arvalid, e_arready, e_rlast, e_rvalid, e_rready; logic [4:0] e_rid; logic [31:0] e_rdata; logic [1:0] e_rresp;
    wire catalog_owns_axi = (cstate != C_IDLE) && (cstate != C_WAIT) && (cstate != C_FAIL);

    scene_ctrl_model_fetcher u_catalog_reader(.clk,.resetn,.rd_start(reader_start),.rd_addr(reader_addr),.rd_busy(reader_busy),.rd_valid(reader_valid),.rd_data(reader_data),.rd_error(reader_error),.m_axi_arid(c_arid),.m_axi_araddr(c_araddr),.m_axi_arlen(c_arlen),.m_axi_arsize(c_arsize),.m_axi_arburst(c_arburst),.m_axi_arlock(c_arlock),.m_axi_arcache(c_arcache),.m_axi_arprot(c_arprot),.m_axi_arvalid(c_arvalid),.m_axi_arready(c_arready),.m_axi_rid(c_rid),.m_axi_rdata(c_rdata),.m_axi_rresp(c_rresp),.m_axi_rlast(c_rlast),.m_axi_rvalid(c_rvalid),.m_axi_rready(c_rready));
    scene_multimesh_cmd_top u_scene(.clk,.resetn,.load_start(child_load_start),.model_base(selected_model_base),.model_size(selected_model_size),.cmd_valid,.cmd_data,.cmd_ready,.frame_start,.cmd_level,.cmd_full,.busy,.frame_done,.error,.error_code,.model_valid,.mesh_count,.m_axi_arid(e_arid),.m_axi_araddr(e_araddr),.m_axi_arlen(e_arlen),.m_axi_arsize(e_arsize),.m_axi_arburst(e_arburst),.m_axi_arlock(e_arlock),.m_axi_arcache(e_arcache),.m_axi_arprot(e_arprot),.m_axi_arvalid(e_arvalid),.m_axi_arready(e_arready),.m_axi_rid(e_rid),.m_axi_rdata(e_rdata),.m_axi_rresp(e_rresp),.m_axi_rlast(e_rlast),.m_axi_rvalid(e_rvalid),.m_axi_rready(e_rready),.dvi_clk,.dvi_hs,.dvi_vs,.dvi_de,.dvi_d);
    always_comb begin
        m_axi_arid = catalog_owns_axi ? c_arid : e_arid; m_axi_araddr = catalog_owns_axi ? c_araddr : e_araddr; m_axi_arlen = catalog_owns_axi ? c_arlen : e_arlen; m_axi_arsize = catalog_owns_axi ? c_arsize : e_arsize; m_axi_arburst = catalog_owns_axi ? c_arburst : e_arburst; m_axi_arlock = catalog_owns_axi ? c_arlock : e_arlock; m_axi_arcache = catalog_owns_axi ? c_arcache : e_arcache; m_axi_arprot = catalog_owns_axi ? c_arprot : e_arprot; m_axi_arvalid = catalog_owns_axi ? c_arvalid : e_arvalid; m_axi_rready = catalog_owns_axi ? c_rready : e_rready;
        c_arready = catalog_owns_axi ? m_axi_arready : 1'b0; c_rid = m_axi_rid; c_rdata = m_axi_rdata; c_rresp = m_axi_rresp; c_rlast = m_axi_rlast; c_rvalid = catalog_owns_axi ? m_axi_rvalid : 1'b0;
        e_arready = catalog_owns_axi ? 1'b0 : m_axi_arready; e_rid = m_axi_rid; e_rdata = m_axi_rdata; e_rresp = m_axi_rresp; e_rlast = m_axi_rlast; e_rvalid = catalog_owns_axi ? 1'b0 : m_axi_rvalid;
        reader_start = (cstate == C_HDR_REQ) || (cstate == C_ENT_REQ);
        reader_addr = (cstate == C_HDR_REQ) ? PACKAGE_BASE + ({29'd0,word_index} << 2) : PACKAGE_BASE + 32'd16 + (({28'd0,active_select}) << 5) + (({29'd0,word_index}) << 2);
        catalog_busy = (cstate != C_IDLE) && (cstate != C_FAIL); child_load_start = (cstate == C_START);
    end
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin cstate<=C_IDLE; word_index<=0; active_select<=0; pending_select<=0; catalog_pending<=0; catalog_valid<=0; catalog_error<=0; catalog_error_code<=0; selected_model<=0; selected_model_base<=0; selected_model_size<=0; end
        else case (cstate)
            C_IDLE: begin
                if (catalog_load && busy) begin pending_select<=model_select; catalog_pending<=1; end
                else if ((catalog_load && !busy) || (catalog_pending && !busy)) begin
                    active_select <= catalog_load ? model_select : pending_select;
                    catalog_pending<=0; catalog_valid<=0; catalog_error<=0; catalog_error_code<=0; word_index<=0; cstate<=C_HDR_REQ;
                end
            end
            C_HDR_REQ: if (reader_busy) cstate<=C_HDR_WAIT;
            C_HDR_WAIT: if (reader_valid) begin if (reader_error) begin catalog_error<=1; catalog_error_code<=1; cstate<=C_FAIL; end else begin header_words[word_index]<=reader_data; if (word_index==3) begin word_index<=0; cstate<=C_ENT_REQ; end else begin word_index<=word_index+1'b1; cstate<=C_HDR_REQ; end end end
            C_ENT_REQ: if (reader_busy) cstate<=C_ENT_WAIT;
            C_ENT_WAIT: if (reader_valid) begin if (reader_error) begin catalog_error<=1; catalog_error_code<=1; cstate<=C_FAIL; end else begin entry_words[word_index]<=reader_data; if (word_index==3) begin
                if (header_words[0] != S3PK_MAGIC || header_words[1][15:0] != 16'd1 || active_select >= header_words[1][19:16] || header_words[2] != (({28'd0,header_words[1][19:16]}) << 5) || header_words[3] < (32'd16 + header_words[2]) || header_words[3] > PACKAGE_SIZE || entry_words[2] == 0 || entry_words[0][3:0] != active_select || entry_words[0][15:8] != SK3D_V4 || entry_words[1] < header_words[3] || entry_words[1] + entry_words[2] > PACKAGE_SIZE) begin catalog_error<=1; catalog_error_code<=2; cstate<=C_FAIL; end
                else begin selected_model<=active_select; selected_model_base<=PACKAGE_BASE+entry_words[1]; selected_model_size<=entry_words[2]; catalog_valid<=1; cstate<=C_START; end
            end else begin word_index<=word_index+1'b1; cstate<=C_ENT_REQ; end end end
            C_START: cstate<=C_WAIT;
            C_WAIT: if (model_valid) cstate<=C_IDLE;
            default: cstate<=C_FAIL;
        endcase
    end
endmodule
