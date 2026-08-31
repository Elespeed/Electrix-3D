`timescale 1ns / 1ps
`timescale 1ns / 1ps

module ddr3_model_wrapper #(
    parameter integer DQ_WIDTH   = 32,
    parameter integer DQS_WIDTH  = 4,
    parameter integer DM_WIDTH   = 4,
    parameter integer ROW_WIDTH  = 14,
    parameter integer CS_WIDTH   = 1,
    parameter integer ODT_WIDTH  = 1,
    parameter        CA_MIRROR   = "OFF",
    parameter real   TPROP_DQS   = 0.00,
    parameter real   TPROP_DQS_RD = 0.00,
    parameter real   TPROP_PCB_CTRL = 0.00,
    parameter real   TPROP_PCB_DATA = 0.00,
    parameter real   TPROP_PCB_DATA_RD = 0.00
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

  localparam integer MEMORY_WIDTH = 16;
  localparam integer NUM_COMP = DQ_WIDTH / MEMORY_WIDTH;

  wire [ROW_WIDTH-1:0] ddr3_addr_fpga;
  assign ddr3_addr_fpga = ddr3_addr[ROW_WIDTH-1:0];

  reg [ROW_WIDTH-1:0]  ddr3_addr_sdram [0:1];
  reg [2:0]            ddr3_ba_sdram [0:1];
  reg                  ddr3_ras_n_sdram;
  reg                  ddr3_cas_n_sdram;
  reg                  ddr3_we_n_sdram;
  reg [0:0]            ddr3_cke_sdram;
  reg [0:0]            ddr3_ck_p_sdram;
  reg [0:0]            ddr3_ck_n_sdram;
  reg [CS_WIDTH-1:0]   ddr3_cs_n_sdram_tmp;
  reg [DM_WIDTH-1:0]   ddr3_dm_sdram_tmp;
  reg [ODT_WIDTH-1:0]  ddr3_odt_sdram_tmp;

  wire [CS_WIDTH-1:0]  ddr3_cs_n_sdram;
  wire [DM_WIDTH-1:0]  ddr3_dm_sdram;
  wire [ODT_WIDTH-1:0] ddr3_odt_sdram;
  wire [DQ_WIDTH-1:0]  ddr3_dq_sdram;
  wire [DQS_WIDTH-1:0] ddr3_dqs_p_sdram;
  wire [DQS_WIDTH-1:0] ddr3_dqs_n_sdram;

  always @(*) begin
    ddr3_ck_p_sdram <= #(TPROP_PCB_CTRL) ddr3_ck_p;
    ddr3_ck_n_sdram <= #(TPROP_PCB_CTRL) ddr3_ck_n;
    ddr3_addr_sdram[0] <= #(TPROP_PCB_CTRL) ddr3_addr_fpga;
    ddr3_addr_sdram[1] <= #(TPROP_PCB_CTRL) (CA_MIRROR == "ON") ?
                          {ddr3_addr_fpga[ROW_WIDTH-1:9],
                           ddr3_addr_fpga[7], ddr3_addr_fpga[8],
                           ddr3_addr_fpga[5], ddr3_addr_fpga[6],
                           ddr3_addr_fpga[3], ddr3_addr_fpga[4],
                           ddr3_addr_fpga[2:0]} :
                          ddr3_addr_fpga;
    ddr3_ba_sdram[0] <= #(TPROP_PCB_CTRL) ddr3_ba;
    ddr3_ba_sdram[1] <= #(TPROP_PCB_CTRL) (CA_MIRROR == "ON") ?
                        {ddr3_ba[2], ddr3_ba[0], ddr3_ba[1]} :
                        ddr3_ba;
    ddr3_ras_n_sdram <= #(TPROP_PCB_CTRL) ddr3_ras_n;
    ddr3_cas_n_sdram <= #(TPROP_PCB_CTRL) ddr3_cas_n;
    ddr3_we_n_sdram  <= #(TPROP_PCB_CTRL) ddr3_we_n;
    ddr3_cke_sdram   <= #(TPROP_PCB_CTRL) ddr3_cke;
  end

  always @(*) begin
    ddr3_cs_n_sdram_tmp <= #(TPROP_PCB_CTRL) ddr3_cs_n;
    ddr3_dm_sdram_tmp   <= #(TPROP_PCB_DATA) ddr3_dm;
    ddr3_odt_sdram_tmp  <= #(TPROP_PCB_CTRL) ddr3_odt;
  end

  assign ddr3_cs_n_sdram = ddr3_cs_n_sdram_tmp;
  assign ddr3_dm_sdram   = ddr3_dm_sdram_tmp;
  assign ddr3_odt_sdram  = ddr3_odt_sdram_tmp;

  genvar dqwd;
  generate
    for (dqwd = 0; dqwd < DQ_WIDTH; dqwd = dqwd + 1) begin : gen_dq_delay
      WireDelay #(
          .Delay_g   (TPROP_PCB_DATA),
          .Delay_rd  (TPROP_PCB_DATA_RD),
          .ERR_INSERT("OFF")
      ) u_delay_dq (
          .A            (ddr3_dq[dqwd]),
          .B            (ddr3_dq_sdram[dqwd]),
          .reset        (sim_resetn),
          .phy_init_done(phy_init_done)
      );
    end
  endgenerate

  genvar dqswd;
  generate
    for (dqswd = 0; dqswd < DQS_WIDTH; dqswd = dqswd + 1) begin : gen_dqs_delay
      WireDelay #(
          .Delay_g   (TPROP_DQS),
          .Delay_rd  (TPROP_DQS_RD),
          .ERR_INSERT("OFF")
      ) u_delay_dqs_p (
          .A            (ddr3_dqs_p[dqswd]),
          .B            (ddr3_dqs_p_sdram[dqswd]),
          .reset        (sim_resetn),
          .phy_init_done(phy_init_done)
      );

      WireDelay #(
          .Delay_g   (TPROP_DQS),
          .Delay_rd  (TPROP_DQS_RD),
          .ERR_INSERT("OFF")
      ) u_delay_dqs_n (
          .A            (ddr3_dqs_n[dqswd]),
          .B            (ddr3_dqs_n_sdram[dqswd]),
          .reset        (sim_resetn),
          .phy_init_done(phy_init_done)
      );
    end
  endgenerate

  genvar r, i;
  generate
    for (r = 0; r < CS_WIDTH; r = r + 1) begin : mem_rnk
      if (DQ_WIDTH / 16) begin : mem
        for (i = 0; i < NUM_COMP; i = i + 1) begin : gen_mem
          ddr3_model u_comp_ddr3 (
              .rst_n  (ddr3_reset_n),
              .ck     (ddr3_ck_p_sdram),
              .ck_n   (ddr3_ck_n_sdram),
              .cke    (ddr3_cke_sdram[r]),
              .cs_n   (ddr3_cs_n_sdram[r]),
              .ras_n  (ddr3_ras_n_sdram),
              .cas_n  (ddr3_cas_n_sdram),
              .we_n   (ddr3_we_n_sdram),
              .dm_tdqs(ddr3_dm_sdram[(2*(i+1)-1):(2*i)]),
              .ba     (ddr3_ba_sdram[r]),
              .addr   (ddr3_addr_sdram[r]),
              .dq     (ddr3_dq_sdram[16*(i+1)-1:16*(i)]),
              .dqs    (ddr3_dqs_p_sdram[(2*(i+1)-1):(2*i)]),
              .dqs_n  (ddr3_dqs_n_sdram[(2*(i+1)-1):(2*i)]),
              .tdqs_n (),
              .odt    (ddr3_odt_sdram[r])
          );
        end
      end
      if (DQ_WIDTH % 16) begin : gen_mem_extrabits
        ddr3_model u_comp_ddr3 (
            .rst_n  (ddr3_reset_n),
            .ck     (ddr3_ck_p_sdram),
            .ck_n   (ddr3_ck_n_sdram),
            .cke    (ddr3_cke_sdram[r]),
            .cs_n   (ddr3_cs_n_sdram[r]),
            .ras_n  (ddr3_ras_n_sdram),
            .cas_n  (ddr3_cas_n_sdram),
            .we_n   (ddr3_we_n_sdram),
            .dm_tdqs({ddr3_dm_sdram[DM_WIDTH-1], ddr3_dm_sdram[DM_WIDTH-1]}),
            .ba     (ddr3_ba_sdram[r]),
            .addr   (ddr3_addr_sdram[r]),
            .dq     ({ddr3_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)],
                      ddr3_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)]}),
            .dqs    ({ddr3_dqs_p_sdram[DQS_WIDTH-1], ddr3_dqs_p_sdram[DQS_WIDTH-1]}),
            .dqs_n  ({ddr3_dqs_n_sdram[DQS_WIDTH-1], ddr3_dqs_n_sdram[DQS_WIDTH-1]}),
            .tdqs_n (),
            .odt    (ddr3_odt_sdram[r])
        );
      end
    end
  endgenerate

endmodule
