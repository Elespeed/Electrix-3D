`timescale 1ns/1ps

// One-outstanding, read-only AXI4 master used by the generic SketchBook model demo.
// The core asks for one 32-bit word at a time, keeping the transport logic
// isolated from the fixed-function transform / sort pipeline.
module model_scene_axi_reader (
    input logic clk, input logic resetn,
    input logic rd_start, input logic [31:0] rd_addr,
    output logic rd_busy, output logic rd_valid, output logic [31:0] rd_data,
    output logic rd_error,
    output logic [4:0] m_axi_arid, output logic [31:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen, output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst, output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache, output logic [2:0] m_axi_arprot,
    output logic m_axi_arvalid, input logic m_axi_arready,
    input logic [4:0] m_axi_rid, input logic [31:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp, input logic m_axi_rlast, input logic m_axi_rvalid,
    output logic m_axi_rready
);
    // Register the request before exposing it to the shared AXI/SRAM fabric.
    // Besides making the AXI address stable for the complete handshake cycle,
    // this prevents Scene header fields (for example format_version) from
    // forming a long combinational path through the crossbar to ExtRAM pins.
    typedef enum logic [1:0] {IDLE, SEND_AR, WAIT_R} st_t;
    st_t st;
    logic [31:0] addr_q;

    always_comb begin
        m_axi_arid = 5'd3;
        m_axi_araddr = addr_q;
        m_axi_arlen = 0;
        m_axi_arsize = 3'd2;
        m_axi_arburst = 2'b01;
        m_axi_arlock = 0;
        m_axi_arcache = 0;
        m_axi_arprot = 0;
        m_axi_arvalid = (st == SEND_AR);
        m_axi_rready = (st == WAIT_R);
        rd_busy = (st != IDLE);
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            st <= IDLE;
            addr_q <= '0;
            rd_data <= '0;
            rd_error <= 0;
        end else begin
            if (st == IDLE && rd_start) begin
                addr_q <= rd_addr;
                st <= SEND_AR;
            end else if (st == SEND_AR && m_axi_arready) begin
                st <= WAIT_R;
            end else if (st == WAIT_R && m_axi_rvalid) begin
                rd_data <= m_axi_rdata;
                rd_error <= |m_axi_rresp || !m_axi_rlast;
                st <= IDLE;
            end
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) rd_valid <= 0;
        else rd_valid <= (st == WAIT_R && m_axi_rvalid);
    end
endmodule
