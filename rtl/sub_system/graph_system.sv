`include "config.h"

module graph_system #(
    parameter int H_ACTIVE = `GDU_TIMING_H_ACTIVE,
    parameter int H_FRONT  = `GDU_TIMING_H_FRONT,
    parameter int H_SYNC   = `GDU_TIMING_H_SYNC,
    parameter int H_BACK   = `GDU_TIMING_H_BACK,
    parameter int H_TOTAL  = `GDU_TIMING_H_TOTAL,
    parameter int V_ACTIVE = `GDU_TIMING_V_ACTIVE,
    parameter int V_FRONT  = `GDU_TIMING_V_FRONT,
    parameter int V_SYNC   = `GDU_TIMING_V_SYNC,
    parameter int V_BACK   = `GDU_TIMING_V_BACK,
    parameter int V_TOTAL  = `GDU_TIMING_V_TOTAL,
    parameter bit SIMULATION = 1'b0,
    parameter int SIM_AW = 19,
    parameter bit SIM_USE_FAST_RAM = 1'b0
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        ddr_sys_clk,
    input  logic        ddr_ref_clk,

    input  logic        gru_s_awvalid,
    output logic        gru_s_awready,
    input  logic [31:0] gru_s_awaddr,
    input  logic [4:0]  gru_s_awid,
    input  logic [7:0]  gru_s_awlen,
    input  logic [2:0]  gru_s_awsize,
    input  logic [1:0]  gru_s_awburst,
    input  logic        gru_s_awlock,
    input  logic [3:0]  gru_s_awcache,
    input  logic [2:0]  gru_s_awprot,
    input  logic        gru_s_wvalid,
    output logic        gru_s_wready,
    input  logic [31:0] gru_s_wdata,
    input  logic [3:0]  gru_s_wstrb,
    input  logic        gru_s_wlast,
    output logic        gru_s_bvalid,
    input  logic        gru_s_bready,
    output logic [4:0]  gru_s_bid,
    output logic [1:0]  gru_s_bresp,
    input  logic        gru_s_arvalid,
    output logic        gru_s_arready,
    input  logic [31:0] gru_s_araddr,
    input  logic [4:0]  gru_s_arid,
    input  logic [7:0]  gru_s_arlen,
    input  logic [2:0]  gru_s_arsize,
    input  logic [1:0]  gru_s_arburst,
    input  logic        gru_s_arlock,
    input  logic [3:0]  gru_s_arcache,
    input  logic [2:0]  gru_s_arprot,
    output logic        gru_s_rvalid,
    input  logic        gru_s_rready,
    output logic [31:0] gru_s_rdata,
    output logic [4:0]  gru_s_rid,
    output logic [1:0]  gru_s_rresp,
    output logic        gru_s_rlast,

    input  logic        gdu_s_awvalid,
    output logic        gdu_s_awready,
    input  logic [31:0] gdu_s_awaddr,
    input  logic [4:0]  gdu_s_awid,
    input  logic [7:0]  gdu_s_awlen,
    input  logic [2:0]  gdu_s_awsize,
    input  logic [1:0]  gdu_s_awburst,
    input  logic        gdu_s_awlock,
    input  logic [3:0]  gdu_s_awcache,
    input  logic [2:0]  gdu_s_awprot,
    input  logic        gdu_s_wvalid,
    output logic        gdu_s_wready,
    input  logic [31:0] gdu_s_wdata,
    input  logic [3:0]  gdu_s_wstrb,
    input  logic        gdu_s_wlast,
    output logic        gdu_s_bvalid,
    input  logic        gdu_s_bready,
    output logic [4:0]  gdu_s_bid,
    output logic [1:0]  gdu_s_bresp,
    input  logic        gdu_s_arvalid,
    output logic        gdu_s_arready,
    input  logic [31:0] gdu_s_araddr,
    input  logic [4:0]  gdu_s_arid,
    input  logic [7:0]  gdu_s_arlen,
    input  logic [2:0]  gdu_s_arsize,
    input  logic [1:0]  gdu_s_arburst,
    input  logic        gdu_s_arlock,
    input  logic [3:0]  gdu_s_arcache,
    input  logic [2:0]  gdu_s_arprot,
    output logic        gdu_s_rvalid,
    input  logic        gdu_s_rready,
    output logic [31:0] gdu_s_rdata,
    output logic [4:0]  gdu_s_rid,
    output logic [1:0]  gdu_s_rresp,
    output logic        gdu_s_rlast,

    output logic [4:0]  video_red,
    output logic [5:0]  video_green,
    output logic [4:0]  video_blue,
    output logic        video_hsync,
    output logic        video_vsync,
    output logic        video_de,
    output logic        video_clk,
    output logic [15:0] lcd_rgb,
    output logic        lcd_hsync,
    output logic        lcd_vsync,
    output logic        lcd_de,
    output logic        lcd_pclk,
    output logic        lcd_rst,
    output logic        lcd_bl_ctr,

    output logic        gru_status_axi_error,
    output logic        gru_status_cfg_error,
    output logic        gdu_fifo_underflow_evt,
    output logic        gdu_axi_error_evt,
    output logic        ddr_init_calib_complete,

    inout  wire [31:0]  ddr3_dq,
    inout  wire [3:0]   ddr3_dqs_n,
    inout  wire [3:0]   ddr3_dqs_p,
    output wire [14:0]  ddr3_addr,
    output wire [2:0]   ddr3_ba,
    output wire         ddr3_ras_n,
    output wire         ddr3_cas_n,
    output wire         ddr3_we_n,
    output wire         ddr3_reset_n,
    output wire [0:0]   ddr3_ck_p,
    output wire [0:0]   ddr3_ck_n,
    output wire [0:0]   ddr3_cke,
    output wire [0:0]   ddr3_cs_n,
    output wire [3:0]   ddr3_dm,
    output wire [0:0]   ddr3_odt
);

    logic [4:0]  gru_m_axi_awid;
    logic [31:0] gru_m_axi_awaddr;
    logic [7:0]  gru_m_axi_awlen;
    logic [2:0]  gru_m_axi_awsize;
    logic [1:0]  gru_m_axi_awburst;
    logic        gru_m_axi_awlock;
    logic [3:0]  gru_m_axi_awcache;
    logic [2:0]  gru_m_axi_awprot;
    logic        gru_m_axi_awvalid;
    logic        gru_m_axi_awready;
    logic [127:0] gru_m_axi_wdata;
    logic [15:0]  gru_m_axi_wstrb;
    logic        gru_m_axi_wlast;
    logic        gru_m_axi_wvalid;
    logic        gru_m_axi_wready;
    logic [4:0]  gru_m_axi_bid;
    logic [1:0]  gru_m_axi_bresp;
    logic        gru_m_axi_bvalid;
    logic        gru_m_axi_bready;
    logic [4:0]  gru_m_axi_arid;
    logic [31:0] gru_m_axi_araddr;
    logic [7:0]  gru_m_axi_arlen;
    logic [2:0]  gru_m_axi_arsize;
    logic [1:0]  gru_m_axi_arburst;
    logic        gru_m_axi_arlock;
    logic [3:0]  gru_m_axi_arcache;
    logic [2:0]  gru_m_axi_arprot;
    logic        gru_m_axi_arvalid;
    logic        gru_m_axi_arready;
    logic [4:0]  gru_m_axi_rid;
    logic [127:0] gru_m_axi_rdata;
    logic [1:0]  gru_m_axi_rresp;
    logic        gru_m_axi_rlast;
    logic        gru_m_axi_rvalid;
    logic        gru_m_axi_rready;

    logic [4:0]  gdu_m_axi_arid;
    logic [31:0] gdu_m_axi_araddr;
    logic [7:0]  gdu_m_axi_arlen;
    logic [2:0]  gdu_m_axi_arsize;
    logic [1:0]  gdu_m_axi_arburst;
    logic        gdu_m_axi_arlock;
    logic [3:0]  gdu_m_axi_arcache;
    logic [2:0]  gdu_m_axi_arprot;
    logic        gdu_m_axi_arvalid;
    logic        gdu_m_axi_arready;
    logic [4:0]  gdu_m_axi_rid;
    logic [127:0] gdu_m_axi_rdata;
    logic [1:0]  gdu_m_axi_rresp;
    logic        gdu_m_axi_rlast;
    logic        gdu_m_axi_rvalid;
    logic        gdu_m_axi_rready;
    logic        gdu_fifo_critical;
    logic        gdu_fifo_low;

    // Phase-4: ddr_axi_arbiter_2m1s cumulative counters -> gdu_top perf window.
    logic [31:0] arb_gru_grant_count;
    logic [31:0] arb_gdu_grant_count;
    logic [31:0] arb_gru_wait_cycle_count;
    logic [31:0] arb_gdu_wait_cycle_count;
    logic [31:0] arb_gru_max_wait_cycles;
    logic [31:0] arb_gdu_max_wait_cycles;
    logic [31:0] arb_qos_override_count;
    logic [31:0] arb_critical_override_count;
    logic [31:0] arb_starvation_relief_count;

    logic [4:0]  ddr_axi32_arid;
    logic [31:0] ddr_axi32_araddr;
    logic [7:0]  ddr_axi32_arlen;
    logic [2:0]  ddr_axi32_arsize;
    logic [1:0]  ddr_axi32_arburst;
    logic        ddr_axi32_arlock;
    logic [3:0]  ddr_axi32_arcache;
    logic [2:0]  ddr_axi32_arprot;
    logic        ddr_axi32_arvalid;
    logic        ddr_axi32_arready;
    logic [4:0]  ddr_axi32_rid;
    logic [31:0] ddr_axi32_rdata;
    logic [1:0]  ddr_axi32_rresp;
    logic        ddr_axi32_rlast;
    logic        ddr_axi32_rvalid;
    logic        ddr_axi32_rready;
    logic [4:0]  ddr_axi32_awid;
    logic [31:0] ddr_axi32_awaddr;
    logic [7:0]  ddr_axi32_awlen;
    logic [2:0]  ddr_axi32_awsize;
    logic [1:0]  ddr_axi32_awburst;
    logic        ddr_axi32_awlock;
    logic [3:0]  ddr_axi32_awcache;
    logic [2:0]  ddr_axi32_awprot;
    logic        ddr_axi32_awvalid;
    logic        ddr_axi32_awready;
    logic [31:0] ddr_axi32_wdata;
    logic [3:0]  ddr_axi32_wstrb;
    logic        ddr_axi32_wlast;
    logic        ddr_axi32_wvalid;
    logic        ddr_axi32_wready;
    logic [4:0]  ddr_axi32_bid;
    logic [1:0]  ddr_axi32_bresp;
    logic        ddr_axi32_bvalid;
    logic        ddr_axi32_bready;

    logic [4:0]   ddr_axi128_arid;
    logic [31:0]  ddr_axi128_araddr;
    logic [7:0]   ddr_axi128_arlen;
    logic [2:0]   ddr_axi128_arsize;
    logic [1:0]   ddr_axi128_arburst;
    logic         ddr_axi128_arlock;
    logic [3:0]   ddr_axi128_arcache;
    logic [2:0]   ddr_axi128_arprot;
    logic         ddr_axi128_arvalid;
    logic         ddr_axi128_arready;
    logic [4:0]   ddr_axi128_rid;
    logic [127:0] ddr_axi128_rdata;
    logic [1:0]   ddr_axi128_rresp;
    logic         ddr_axi128_rlast;
    logic         ddr_axi128_rvalid;
    logic         ddr_axi128_rready;
    logic [4:0]   ddr_axi128_awid;
    logic [31:0]  ddr_axi128_awaddr;
    logic [7:0]   ddr_axi128_awlen;
    logic [2:0]   ddr_axi128_awsize;
    logic [1:0]   ddr_axi128_awburst;
    logic         ddr_axi128_awlock;
    logic [3:0]   ddr_axi128_awcache;
    logic [2:0]   ddr_axi128_awprot;
    logic         ddr_axi128_awvalid;
    logic         ddr_axi128_awready;
    logic [127:0] ddr_axi128_wdata;
    logic [15:0]  ddr_axi128_wstrb;
    logic         ddr_axi128_wlast;
    logic         ddr_axi128_wvalid;
    logic         ddr_axi128_wready;
    logic [4:0]   ddr_axi128_bid;
    logic [1:0]   ddr_axi128_bresp;
    logic         ddr_axi128_bvalid;
    logic         ddr_axi128_bready;

    gru_top u_gru_top (
        .s_awvalid (gru_s_awvalid),
        .s_awready (gru_s_awready),
        .s_awaddr  (gru_s_awaddr),
        .s_awid    (gru_s_awid),
        .s_awlen   (gru_s_awlen),
        .s_awsize  (gru_s_awsize),
        .s_awburst (gru_s_awburst),
        .s_awlock  (gru_s_awlock),
        .s_awcache (gru_s_awcache),
        .s_awprot  (gru_s_awprot),
        .s_wvalid  (gru_s_wvalid),
        .s_wready  (gru_s_wready),
        .s_wdata   (gru_s_wdata),
        .s_wstrb   (gru_s_wstrb),
        .s_wlast   (gru_s_wlast),
        .s_bvalid  (gru_s_bvalid),
        .s_bready  (gru_s_bready),
        .s_bid     (gru_s_bid),
        .s_bresp   (gru_s_bresp),
        .s_arvalid (gru_s_arvalid),
        .s_arready (gru_s_arready),
        .s_araddr  (gru_s_araddr),
        .s_arid    (gru_s_arid),
        .s_arlen   (gru_s_arlen),
        .s_arsize  (gru_s_arsize),
        .s_arburst (gru_s_arburst),
        .s_arlock  (gru_s_arlock),
        .s_arcache (gru_s_arcache),
        .s_arprot  (gru_s_arprot),
        .s_rvalid  (gru_s_rvalid),
        .s_rready  (gru_s_rready),
        .s_rdata   (gru_s_rdata),
        .s_rid     (gru_s_rid),
        .s_rresp   (gru_s_rresp),
        .s_rlast   (gru_s_rlast),
        .m_axi_arid    (gru_m_axi_arid),
        .m_axi_araddr  (gru_m_axi_araddr),
        .m_axi_arlen   (gru_m_axi_arlen),
        .m_axi_arsize  (gru_m_axi_arsize),
        .m_axi_arburst (gru_m_axi_arburst),
        .m_axi_arlock  (gru_m_axi_arlock),
        .m_axi_arcache (gru_m_axi_arcache),
        .m_axi_arprot  (gru_m_axi_arprot),
        .m_axi_arvalid (gru_m_axi_arvalid),
        .m_axi_arready (gru_m_axi_arready),
        .m_axi_rid     (gru_m_axi_rid),
        .m_axi_rdata   (gru_m_axi_rdata),
        .m_axi_rresp   (gru_m_axi_rresp),
        .m_axi_rlast   (gru_m_axi_rlast),
        .m_axi_rvalid  (gru_m_axi_rvalid),
        .m_axi_rready  (gru_m_axi_rready),
        .m_axi_awid    (gru_m_axi_awid),
        .m_axi_awaddr  (gru_m_axi_awaddr),
        .m_axi_awlen   (gru_m_axi_awlen),
        .m_axi_awsize  (gru_m_axi_awsize),
        .m_axi_awburst (gru_m_axi_awburst),
        .m_axi_awlock  (gru_m_axi_awlock),
        .m_axi_awcache (gru_m_axi_awcache),
        .m_axi_awprot  (gru_m_axi_awprot),
        .m_axi_awvalid (gru_m_axi_awvalid),
        .m_axi_awready (gru_m_axi_awready),
        .m_axi_wdata   (gru_m_axi_wdata),
        .m_axi_wstrb   (gru_m_axi_wstrb),
        .m_axi_wlast   (gru_m_axi_wlast),
        .m_axi_wvalid  (gru_m_axi_wvalid),
        .m_axi_wready  (gru_m_axi_wready),
        .m_axi_bid     (gru_m_axi_bid),
        .m_axi_bresp   (gru_m_axi_bresp),
        .m_axi_bvalid  (gru_m_axi_bvalid),
        .m_axi_bready  (gru_m_axi_bready),
        .status_axi_error(gru_status_axi_error),
        .status_cfg_error(gru_status_cfg_error),
        .aclk      (aclk),
        .aresetn   (aresetn)
    );

    gdu_top #(
        .H_ACTIVE (H_ACTIVE),
        .H_FRONT  (H_FRONT),
        .H_SYNC   (H_SYNC),
        .H_BACK   (H_BACK),
        .H_TOTAL  (H_TOTAL),
        .V_ACTIVE (V_ACTIVE),
        .V_FRONT  (V_FRONT),
        .V_SYNC   (V_SYNC),
        .V_BACK   (V_BACK),
        .V_TOTAL  (V_TOTAL)
    ) u_gdu_top (
        .s_awvalid (gdu_s_awvalid),
        .s_awready (gdu_s_awready),
        .s_awaddr  (gdu_s_awaddr),
        .s_awid    (gdu_s_awid),
        .s_awlen   (gdu_s_awlen),
        .s_awsize  (gdu_s_awsize),
        .s_awburst (gdu_s_awburst),
        .s_awlock  (gdu_s_awlock),
        .s_awcache (gdu_s_awcache),
        .s_awprot  (gdu_s_awprot),
        .s_wvalid  (gdu_s_wvalid),
        .s_wready  (gdu_s_wready),
        .s_wdata   (gdu_s_wdata),
        .s_wstrb   (gdu_s_wstrb),
        .s_wlast   (gdu_s_wlast),
        .s_bvalid  (gdu_s_bvalid),
        .s_bready  (gdu_s_bready),
        .s_bid     (gdu_s_bid),
        .s_bresp   (gdu_s_bresp),
        .s_arvalid (gdu_s_arvalid),
        .s_arready (gdu_s_arready),
        .s_araddr  (gdu_s_araddr),
        .s_arid    (gdu_s_arid),
        .s_arlen   (gdu_s_arlen),
        .s_arsize  (gdu_s_arsize),
        .s_arburst (gdu_s_arburst),
        .s_arlock  (gdu_s_arlock),
        .s_arcache (gdu_s_arcache),
        .s_arprot  (gdu_s_arprot),
        .s_rvalid  (gdu_s_rvalid),
        .s_rready  (gdu_s_rready),
        .s_rdata   (gdu_s_rdata),
        .s_rid     (gdu_s_rid),
        .s_rresp   (gdu_s_rresp),
        .s_rlast   (gdu_s_rlast),
        .m_axi_arid    (gdu_m_axi_arid),
        .m_axi_araddr  (gdu_m_axi_araddr),
        .m_axi_arlen   (gdu_m_axi_arlen),
        .m_axi_arsize  (gdu_m_axi_arsize),
        .m_axi_arburst (gdu_m_axi_arburst),
        .m_axi_arlock  (gdu_m_axi_arlock),
        .m_axi_arcache (gdu_m_axi_arcache),
        .m_axi_arprot  (gdu_m_axi_arprot),
        .m_axi_arvalid (gdu_m_axi_arvalid),
        .m_axi_arready (gdu_m_axi_arready),
        .m_axi_rid     (gdu_m_axi_rid),
        .m_axi_rdata   (gdu_m_axi_rdata),
        .m_axi_rresp   (gdu_m_axi_rresp),
        .m_axi_rlast   (gdu_m_axi_rlast),
        .m_axi_rvalid  (gdu_m_axi_rvalid),
        .m_axi_rready  (gdu_m_axi_rready),
        .ddr_init_calib_complete(ddr_init_calib_complete),
        .video_red     (video_red),
        .video_green   (video_green),
        .video_blue    (video_blue),
        .video_hsync   (video_hsync),
        .video_vsync   (video_vsync),
        .video_de      (video_de),
        .video_clk     (video_clk),
        .lcd_rgb       (lcd_rgb),
        .lcd_hsync     (lcd_hsync),
        .lcd_vsync     (lcd_vsync),
        .lcd_de        (lcd_de),
        .lcd_pclk      (lcd_pclk),
        .lcd_rst       (lcd_rst),
        .lcd_bl_ctr    (lcd_bl_ctr),
        .fifo_underflow_evt(gdu_fifo_underflow_evt),
        .axi_error_evt (gdu_axi_error_evt),
        .gdu_fifo_critical(gdu_fifo_critical),
        .gdu_fifo_low  (gdu_fifo_low),
        .arb_gru_grant_count        (arb_gru_grant_count),
        .arb_gdu_grant_count        (arb_gdu_grant_count),
        .arb_gru_wait_cycle_count   (arb_gru_wait_cycle_count),
        .arb_gdu_wait_cycle_count   (arb_gdu_wait_cycle_count),
        .arb_gru_max_wait_cycles    (arb_gru_max_wait_cycles),
        .arb_gdu_max_wait_cycles    (arb_gdu_max_wait_cycles),
        .arb_qos_override_count     (arb_qos_override_count),
        .arb_critical_override_count(arb_critical_override_count),
        .arb_starvation_relief_count(arb_starvation_relief_count),
        .aclk          (aclk),
        .aresetn       (aresetn)
    );

    ddr_axi_arbiter_2m1s u_ddr_axi_arbiter_2m1s (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .gdu_fifo_critical(gdu_fifo_critical),
        .gdu_fifo_low  (gdu_fifo_low),
        .m0_axi_arid   (gru_m_axi_arid),
        .m0_axi_araddr (gru_m_axi_araddr),
        .m0_axi_arlen  (gru_m_axi_arlen),
        .m0_axi_arsize (gru_m_axi_arsize),
        .m0_axi_arburst(gru_m_axi_arburst),
        .m0_axi_arlock (gru_m_axi_arlock),
        .m0_axi_arcache(gru_m_axi_arcache),
        .m0_axi_arprot (gru_m_axi_arprot),
        .m0_axi_arvalid(gru_m_axi_arvalid),
        .m0_axi_arready(gru_m_axi_arready),
        .m0_axi_rid    (gru_m_axi_rid),
        .m0_axi_rdata  (gru_m_axi_rdata),
        .m0_axi_rresp  (gru_m_axi_rresp),
        .m0_axi_rlast  (gru_m_axi_rlast),
        .m0_axi_rvalid (gru_m_axi_rvalid),
        .m0_axi_rready (gru_m_axi_rready),
        .m0_axi_awid   (gru_m_axi_awid),
        .m0_axi_awaddr (gru_m_axi_awaddr),
        .m0_axi_awlen  (gru_m_axi_awlen),
        .m0_axi_awsize (gru_m_axi_awsize),
        .m0_axi_awburst(gru_m_axi_awburst),
        .m0_axi_awlock (gru_m_axi_awlock),
        .m0_axi_awcache(gru_m_axi_awcache),
        .m0_axi_awprot (gru_m_axi_awprot),
        .m0_axi_awvalid(gru_m_axi_awvalid),
        .m0_axi_awready(gru_m_axi_awready),
        .m0_axi_wdata  (gru_m_axi_wdata),
        .m0_axi_wstrb  (gru_m_axi_wstrb),
        .m0_axi_wlast  (gru_m_axi_wlast),
        .m0_axi_wvalid (gru_m_axi_wvalid),
        .m0_axi_wready (gru_m_axi_wready),
        .m0_axi_bid    (gru_m_axi_bid),
        .m0_axi_bresp  (gru_m_axi_bresp),
        .m0_axi_bvalid (gru_m_axi_bvalid),
        .m0_axi_bready (gru_m_axi_bready),
        .m1_axi_arid   (gdu_m_axi_arid),
        .m1_axi_araddr (gdu_m_axi_araddr),
        .m1_axi_arlen  (gdu_m_axi_arlen),
        .m1_axi_arsize (gdu_m_axi_arsize),
        .m1_axi_arburst(gdu_m_axi_arburst),
        .m1_axi_arlock (gdu_m_axi_arlock),
        .m1_axi_arcache(gdu_m_axi_arcache),
        .m1_axi_arprot (gdu_m_axi_arprot),
        .m1_axi_arvalid(gdu_m_axi_arvalid),
        .m1_axi_arready(gdu_m_axi_arready),
        .m1_axi_rid    (gdu_m_axi_rid),
        .m1_axi_rdata  (gdu_m_axi_rdata),
        .m1_axi_rresp  (gdu_m_axi_rresp),
        .m1_axi_rlast  (gdu_m_axi_rlast),
        .m1_axi_rvalid (gdu_m_axi_rvalid),
        .m1_axi_rready (gdu_m_axi_rready),
        .s0_axi_arid   (ddr_axi128_arid),
        .s0_axi_araddr (ddr_axi128_araddr),
        .s0_axi_arlen  (ddr_axi128_arlen),
        .s0_axi_arsize (ddr_axi128_arsize),
        .s0_axi_arburst(ddr_axi128_arburst),
        .s0_axi_arlock (ddr_axi128_arlock),
        .s0_axi_arcache(ddr_axi128_arcache),
        .s0_axi_arprot (ddr_axi128_arprot),
        .s0_axi_arvalid(ddr_axi128_arvalid),
        .s0_axi_arready(ddr_axi128_arready),
        .s0_axi_rid    (ddr_axi128_rid),
        .s0_axi_rdata  (ddr_axi128_rdata),
        .s0_axi_rresp  (ddr_axi128_rresp),
        .s0_axi_rlast  (ddr_axi128_rlast),
        .s0_axi_rvalid (ddr_axi128_rvalid),
        .s0_axi_rready (ddr_axi128_rready),
        .s0_axi_awid   (ddr_axi128_awid),
        .s0_axi_awaddr (ddr_axi128_awaddr),
        .s0_axi_awlen  (ddr_axi128_awlen),
        .s0_axi_awsize (ddr_axi128_awsize),
        .s0_axi_awburst(ddr_axi128_awburst),
        .s0_axi_awlock (ddr_axi128_awlock),
        .s0_axi_awcache(ddr_axi128_awcache),
        .s0_axi_awprot (ddr_axi128_awprot),
        .s0_axi_awvalid(ddr_axi128_awvalid),
        .s0_axi_awready(ddr_axi128_awready),
        .s0_axi_wdata  (ddr_axi128_wdata),
        .s0_axi_wstrb  (ddr_axi128_wstrb),
        .s0_axi_wlast  (ddr_axi128_wlast),
        .s0_axi_wvalid (ddr_axi128_wvalid),
        .s0_axi_wready (ddr_axi128_wready),
        .s0_axi_bid    (ddr_axi128_bid),
        .s0_axi_bresp  (ddr_axi128_bresp),
        .s0_axi_bvalid (ddr_axi128_bvalid),
        .s0_axi_bready (ddr_axi128_bready),
        .gru_read_grant_count      (arb_gru_grant_count),
        .gdu_read_grant_count      (arb_gdu_grant_count),
        .gru_wait_cycle_count      (arb_gru_wait_cycle_count),
        .gdu_wait_cycle_count      (arb_gdu_wait_cycle_count),
        .gru_max_wait_cycles       (arb_gru_max_wait_cycles),
        .gdu_max_wait_cycles       (arb_gdu_max_wait_cycles),
        .gdu_qos_override_count    (arb_qos_override_count),
        .gdu_critical_override_count(arb_critical_override_count),
        .gru_starvation_relief_count(arb_starvation_relief_count)
    );

    ddr_ctrl_top #(
        .SIMULATION      (SIMULATION),
        .SIM_AW          (SIM_AW),
        .SIM_USE_FAST_RAM(SIM_USE_FAST_RAM)
    ) u_ddr_ctrl_top (
        .sys_clk             (aclk),
        .sys_resetn          (aresetn),
        .ddr_sys_clk         (ddr_sys_clk),
        .ddr_ref_clk         (ddr_ref_clk),
        .s_axi_arid          (ddr_axi128_arid),
        .s_axi_araddr        (ddr_axi128_araddr),
        .s_axi_arlen         (ddr_axi128_arlen),
        .s_axi_arsize        (ddr_axi128_arsize),
        .s_axi_arburst       (ddr_axi128_arburst),
        .s_axi_arlock        (ddr_axi128_arlock),
        .s_axi_arcache       (ddr_axi128_arcache),
        .s_axi_arprot        (ddr_axi128_arprot),
        .s_axi_arvalid       (ddr_axi128_arvalid),
        .s_axi_arready       (ddr_axi128_arready),
        .s_axi_rid           (ddr_axi128_rid),
        .s_axi_rdata         (ddr_axi128_rdata),
        .s_axi_rresp         (ddr_axi128_rresp),
        .s_axi_rlast         (ddr_axi128_rlast),
        .s_axi_rvalid        (ddr_axi128_rvalid),
        .s_axi_rready        (ddr_axi128_rready),
        .s_axi_awid          (ddr_axi128_awid),
        .s_axi_awaddr        (ddr_axi128_awaddr),
        .s_axi_awlen         (ddr_axi128_awlen),
        .s_axi_awsize        (ddr_axi128_awsize),
        .s_axi_awburst       (ddr_axi128_awburst),
        .s_axi_awlock        (ddr_axi128_awlock),
        .s_axi_awcache       (ddr_axi128_awcache),
        .s_axi_awprot        (ddr_axi128_awprot),
        .s_axi_awvalid       (ddr_axi128_awvalid),
        .s_axi_awready       (ddr_axi128_awready),
        .s_axi_wdata         (ddr_axi128_wdata),
        .s_axi_wstrb         (ddr_axi128_wstrb),
        .s_axi_wlast         (ddr_axi128_wlast),
        .s_axi_wvalid        (ddr_axi128_wvalid),
        .s_axi_wready        (ddr_axi128_wready),
        .s_axi_bid           (ddr_axi128_bid),
        .s_axi_bresp         (ddr_axi128_bresp),
        .s_axi_bvalid        (ddr_axi128_bvalid),
        .s_axi_bready        (ddr_axi128_bready),
        .init_calib_complete (ddr_init_calib_complete),
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),
        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_cke            (ddr3_cke),
        .ddr3_cs_n           (ddr3_cs_n),
        .ddr3_dm             (ddr3_dm),
        .ddr3_odt            (ddr3_odt)
    );

endmodule

