`timescale 1ns / 1ps

module axi_reg_write_monitor #(
    parameter integer ADDR_W = 32,
    parameter integer DATA_W = 32
) (
    input  logic              aclk,
    input  logic              aresetn,
    input  logic              s_awvalid,
    input  logic              s_awready,
    input  logic [ADDR_W-1:0] s_awaddr,
    input  logic              s_wvalid,
    input  logic              s_wready,
    input  logic              s_wlast,
    input  logic [DATA_W-1:0] s_wdata,
    output logic              write_valid,
    output logic [ADDR_W-1:0] write_addr,
    output logic [DATA_W-1:0] write_data
);

    logic              aw_pending;
    logic [ADDR_W-1:0] aw_addr_shadow;

    wire aw_enter = s_awvalid && s_awready;
    wire w_enter  = s_wvalid && s_wready && s_wlast;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_pending     <= 1'b0;
            aw_addr_shadow <= '0;
            write_valid    <= 1'b0;
            write_addr     <= '0;
            write_data     <= '0;
        end else begin
            write_valid <= 1'b0;

            if (aw_enter) begin
                aw_pending     <= 1'b1;
                aw_addr_shadow <= s_awaddr;
            end

            if (w_enter && (aw_pending || aw_enter)) begin
                write_valid <= 1'b1;
                write_addr  <= aw_enter ? s_awaddr : aw_addr_shadow;
                write_data  <= s_wdata;
                aw_pending  <= 1'b0;
            end
        end
    end

endmodule
