`timescale 1ns / 1ps

/**
 * Simple DDR3 Model for Fast Simulation
 * - Quick initialization (no calibration delays)
 * - Basic DDR3 command support (ACTIVATE, READ, WRITE)
 * - 64MB memory (for 32-bit data width)
 */
module simple_ddr #(
    parameter integer DQ_WIDTH   = 32,
    parameter integer DQS_WIDTH  = 4,
    parameter integer DM_WIDTH   = 4,
    parameter integer ROW_WIDTH  = 14,
    parameter integer CS_WIDTH   = 1,
    parameter integer ODT_WIDTH  = 1
) (
    input  wire                     sim_resetn,
    input  wire                     phy_init_done,
    inout  wire [DQ_WIDTH-1:0]      ddr3_dq,
    inout  wire [DQS_WIDTH-1:0]     ddr3_dqs_n,
    inout  wire [DQS_WIDTH-1:0]     ddr3_dqs_p,
    input  wire [14:0]              ddr3_addr,
    input  wire [2:0]               ddr3_ba,
    input  wire                     ddr3_ras_n,
    input  wire                     ddr3_cas_n,
    input  wire                     ddr3_we_n,
    input  wire                     ddr3_reset_n,
    input  wire [0:0]               ddr3_ck_p,
    input  wire [0:0]               ddr3_ck_n,
    input  wire [0:0]               ddr3_cke,
    input  wire [0:0]               ddr3_cs_n,
    input  wire [DM_WIDTH-1:0]      ddr3_dm,
    input  wire [ODT_WIDTH-1:0]     ddr3_odt
);

  // DDR3 command encoding
  localparam CMD_NOP       = 3'b111;
  localparam CMD_ACTIVATE  = 3'b011;
  localparam CMD_WRITE     = 3'b100;
  localparam CMD_READ      = 3'b101;
  localparam CMD_PRECHARGE = 3'b010;
  localparam CMD_REFRESH   = 3'b001;
  localparam CMD_LOAD_MODE = 3'b000;

  // Memory: 64MB = 16M words of 32-bit
  // Address is 14-bit row + 2-bit bank + 10-bit col = 26-bit total
  // Simplified: use 24-bit address space for 16M words
  localparam MEM_SIZE = 1 << 24;
  reg [DQ_WIDTH-1:0] memory [0:MEM_SIZE-1];

  // State tracking
  reg [ROW_WIDTH-1:0] active_row [3:0];  // Per bank
  reg [DQ_WIDTH-1:0] write_data_pipeline;
  reg [DQ_WIDTH-1:0] read_data;
  wire [2:0] cmd = {ddr3_ras_n, ddr3_cas_n, ddr3_we_n};
  
  // Convert DDR3 address to linear address
  function automatic [23:0] get_linear_addr(
      input [14:0] addr,
      input [2:0] ba,
      input [9:0] col
  );
    // Simple mapping: {ba[1:0], addr[13:0], col[9:0]}
    get_linear_addr = {ba[1:0], addr[13:0], col[9:0]};
  endfunction

  // Clock domain (using ck_p for modeling)
  always @(posedge ddr3_ck_p) begin
    if (!ddr3_cs_n && ddr3_cke) begin
      case (cmd)
        CMD_ACTIVATE: begin
          // Store row address for subsequent READ/WRITE
          active_row[ddr3_ba] <= ddr3_addr[ROW_WIDTH-1:0];
        end
        CMD_WRITE: begin
          // Queue write data (real DDR3 has DQS strobe timing)
          write_data_pipeline <= ddr3_dq;
        end
      endcase
    end
  end

  // Write to memory (after data valid)
  always @(posedge ddr3_ck_p) begin : write_mem_proc
    logic [23:0] addr;
    if (!ddr3_cs_n && ddr3_cke && cmd == CMD_WRITE) begin
      // Simple write-through (no strobe timing)
      addr = get_linear_addr(active_row[ddr3_ba], ddr3_ba, ddr3_addr[9:0]);
      if (addr < MEM_SIZE) begin
        memory[addr] <= write_data_pipeline;
      end
    end
  end

  // Read from memory and drive DQ/DQS
  reg [DQ_WIDTH-1:0] ddr3_dq_reg;
  reg [DQS_WIDTH-1:0] ddr3_dqs_p_reg;
  reg [DQS_WIDTH-1:0] ddr3_dqs_n_reg;
  reg read_active;

  always @(posedge ddr3_ck_p) begin : read_mem_proc
    logic [23:0] addr;
    if (!ddr3_cs_n && ddr3_cke && cmd == CMD_READ) begin
      read_active <= 1'b1;
      addr = get_linear_addr(active_row[ddr3_ba], ddr3_ba, ddr3_addr[9:0]);
      if (addr < MEM_SIZE) begin
        read_data <= memory[addr];
      end
    end else begin
      read_active <= 1'b0;
    end
  end

  // Data output on DQ/DQS (2-cycle latency typical)
  always @(posedge ddr3_ck_p) begin
    if (read_active) begin
      ddr3_dq_reg <= read_data;
      ddr3_dqs_p_reg <= 4'hF;  // All DQS active
      ddr3_dqs_n_reg <= 4'h0;
    end else begin
      ddr3_dq_reg <= {DQ_WIDTH{1'bz}};
      ddr3_dqs_p_reg <= {DQS_WIDTH{1'bz}};
      ddr3_dqs_n_reg <= {DQS_WIDTH{1'bz}};
    end
  end

  assign ddr3_dq = ddr3_dq_reg;
  assign ddr3_dqs_p = ddr3_dqs_p_reg;
  assign ddr3_dqs_n = ddr3_dqs_n_reg;

endmodule
