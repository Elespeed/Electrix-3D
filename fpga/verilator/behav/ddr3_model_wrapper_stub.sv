// Behavioural substitute for sim/ddr/ddr3_model_wrapper (task §7.3).
//
// WHY THIS EXISTS
//   The real wrapper instantiates the Micron ddr3_model + WireDelay (wiredly.v),
//   which uses tristate/strength constructs this 2-state simulator cannot
//   elaborate ("Unsupported tristate construct: ASSIGNDLY/COND"). Those
//   constructs are legal for a 4-state simulator (ModelSim = golden reference).
//
// WHY IT IS SAFE (functionally inert)
//   Under SIM_USE_FAST_RAM (set for every simulator build of this TB),
//   ddr_ctrl_top's gen_sim branch ties EVERY ddr3_* command pin to idle
//   (ras_n/cas_n/we_n/cs_n=1, cke=0, addr/ba=0) and drives ddr3_dq/dqs to 'z'.
//   The real DDR3 model therefore never sees a valid command and never drives
//   the bus — it is inert. The actual framebuffer store is the axi_wrap_ram_sp
//   behind ddr_ctrl_top.gen_sim.u_ddr_sim_ram, and the GRU/GDU contention is
//   arbitrated by ddr_axi_arbiter_2m1s in front of it. None of that touches the
//   DDR3 pins. So a no-op wrapper is semantically identical to the real one in
//   this mode: contention, AXI behaviour and framebuffer consistency are all
//   preserved. This stub does NOT make the AXI slave "always-ready / zero
//   latency" (forbidden by §7.3) — that slave is axi_wrap_ram_sp, untouched.
//
//   Cross-check against ModelSim (which uses the real model) is the proof:
//   both must reach the same PASS/FAIL, checkpoints and framebuffer compare.
//
// PORT-FAITHFUL: same name/width/direction as the real wrapper so the TB's
// ddr3_model_wrapper instantiation connects unchanged.
`timescale 1ns / 1ps
module ddr3_model_wrapper #(
    parameter integer DQ_WIDTH   = 32,
    parameter integer DQS_WIDTH  = 4,
    parameter integer DM_WIDTH   = 4,
    parameter integer ROW_WIDTH  = 14,
    parameter integer CS_WIDTH   = 1,
    parameter integer ODT_WIDTH  = 1,
    parameter        CA_MIRROR   = "OFF",
    parameter real   TPROP_DQS      = 0.00,
    parameter real   TPROP_DQS_RD   = 0.00,
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
    // Intentionally empty: the DDR3 pins are inert in SIM_USE_FAST_RAM mode.
    // Tie the unused inputs so lint does not flag them; the inouts are left
    // undriven (resolving to the 'z' driven by ddr_ctrl_top.gen_sim).
    wire _unused = &{sim_resetn, phy_init_done, ddr3_addr, ddr3_ba,
                     ddr3_ras_n, ddr3_cas_n, ddr3_we_n, ddr3_reset_n,
                     ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_cs_n,
                     ddr3_dm, ddr3_odt, ddr3_dq, ddr3_dqs_n, ddr3_dqs_p,
                     1'b0};
endmodule
