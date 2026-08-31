`include "config.h"

module graph_system_spi_lcd #(
    parameter bit SIMULATION = 1'b0,
    parameter int SIM_AW = 19,
    parameter bit SIM_USE_FAST_RAM = 1'b0
) (
    input  logic        aclk,
    input  logic        aresetn,
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

    input  logic        lcd_s_awvalid,
    output logic        lcd_s_awready,
    input  logic [31:0] lcd_s_awaddr,
    input  logic [4:0]  lcd_s_awid,
    input  logic [7:0]  lcd_s_awlen,
    input  logic [2:0]  lcd_s_awsize,
    input  logic [1:0]  lcd_s_awburst,
    input  logic        lcd_s_awlock,
    input  logic [3:0]  lcd_s_awcache,
    input  logic [2:0]  lcd_s_awprot,
    input  logic        lcd_s_wvalid,
    output logic        lcd_s_wready,
    input  logic [31:0] lcd_s_wdata,
    input  logic [3:0]  lcd_s_wstrb,
    input  logic        lcd_s_wlast,
    output logic        lcd_s_bvalid,
    input  logic        lcd_s_bready,
    output logic [4:0]  lcd_s_bid,
    output logic [1:0]  lcd_s_bresp,
    input  logic        lcd_s_arvalid,
    output logic        lcd_s_arready,
    input  logic [31:0] lcd_s_araddr,
    input  logic [4:0]  lcd_s_arid,
    input  logic [7:0]  lcd_s_arlen,
    input  logic [2:0]  lcd_s_arsize,
    input  logic [1:0]  lcd_s_arburst,
    input  logic        lcd_s_arlock,
    input  logic [3:0]  lcd_s_arcache,
    input  logic [2:0]  lcd_s_arprot,
    output logic        lcd_s_rvalid,
    input  logic        lcd_s_rready,
    output logic [31:0] lcd_s_rdata,
    output logic [4:0]  lcd_s_rid,
    output logic [1:0]  lcd_s_rresp,
    output logic        lcd_s_rlast,

    input  logic        tft_sdo,
    output logic        tft_scl,
    output logic        tft_sdi,
    output logic        tft_cs,
    output logic        tft_rs,

    output logic        gru_status_axi_error,
    output logic        gru_status_cfg_error,
    output logic        lcd_refresh_busy,
    output logic        lcd_refresh_done_evt,
    output logic        lcd_axi_error_evt,
    output logic        lcd_spi_error_evt,
    output logic        lcd_cfg_error_evt,
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

    logic [4:0]   gru_m_axi_awid;
    logic [31:0]  gru_m_axi_awaddr;
    logic [7:0]   gru_m_axi_awlen;
    logic [2:0]   gru_m_axi_awsize;
    logic [1:0]   gru_m_axi_awburst;
    logic         gru_m_axi_awlock;
    logic [3:0]   gru_m_axi_awcache;
    logic [2:0]   gru_m_axi_awprot;
    logic         gru_m_axi_awvalid;
    logic         gru_m_axi_awready;
    logic [127:0] gru_m_axi_wdata;
    logic [15:0]  gru_m_axi_wstrb;
    logic         gru_m_axi_wlast;
    logic         gru_m_axi_wvalid;
    logic         gru_m_axi_wready;
    logic [4:0]   gru_m_axi_bid;
    logic [1:0]   gru_m_axi_bresp;
    logic         gru_m_axi_bvalid;
    logic         gru_m_axi_bready;
    logic [4:0]   gru_m_axi_arid;
    logic [31:0]  gru_m_axi_araddr;
    logic [7:0]   gru_m_axi_arlen;
    logic [2:0]   gru_m_axi_arsize;
    logic [1:0]   gru_m_axi_arburst;
    logic         gru_m_axi_arlock;
    logic [3:0]   gru_m_axi_arcache;
    logic [2:0]   gru_m_axi_arprot;
    logic         gru_m_axi_arvalid;
    logic         gru_m_axi_arready;
    logic [4:0]   gru_m_axi_rid;
    logic [127:0] gru_m_axi_rdata;
    logic [1:0]   gru_m_axi_rresp;
    logic         gru_m_axi_rlast;
    logic         gru_m_axi_rvalid;
    logic         gru_m_axi_rready;

    logic [4:0]   lcd_m_axi_arid;
    logic [31:0]  lcd_m_axi_araddr;
    logic [7:0]   lcd_m_axi_arlen;
    logic [2:0]   lcd_m_axi_arsize;
    logic [1:0]   lcd_m_axi_arburst;
    logic         lcd_m_axi_arlock;
    logic [3:0]   lcd_m_axi_arcache;
    logic [2:0]   lcd_m_axi_arprot;
    logic         lcd_m_axi_arvalid;
    logic         lcd_m_axi_arready;
    logic [4:0]   lcd_m_axi_rid;
    logic [127:0] lcd_m_axi_rdata;
    logic [1:0]   lcd_m_axi_rresp;
    logic         lcd_m_axi_rlast;
    logic         lcd_m_axi_rvalid;
    logic         lcd_m_axi_rready;

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

    logic [31:0] unused_arb_gru_grant;
    logic [31:0] unused_arb_gdu_grant;
    logic [31:0] unused_arb_gru_wait;
    logic [31:0] unused_arb_gdu_wait;
    logic [31:0] unused_arb_gru_max_wait;
    logic [31:0] unused_arb_gdu_max_wait;
    logic [31:0] unused_arb_qos;
    logic [31:0] unused_arb_critical;
    logic [31:0] unused_arb_starve;

    gru_top u_gru_top (
        .s_awvalid(gru_s_awvalid), .s_awready(gru_s_awready), .s_awaddr(gru_s_awaddr),
        .s_awid(gru_s_awid), .s_awlen(gru_s_awlen), .s_awsize(gru_s_awsize),
        .s_awburst(gru_s_awburst), .s_awlock(gru_s_awlock), .s_awcache(gru_s_awcache),
        .s_awprot(gru_s_awprot), .s_wvalid(gru_s_wvalid), .s_wready(gru_s_wready),
        .s_wdata(gru_s_wdata), .s_wstrb(gru_s_wstrb), .s_wlast(gru_s_wlast),
        .s_bvalid(gru_s_bvalid), .s_bready(gru_s_bready), .s_bid(gru_s_bid),
        .s_bresp(gru_s_bresp), .s_arvalid(gru_s_arvalid), .s_arready(gru_s_arready),
        .s_araddr(gru_s_araddr), .s_arid(gru_s_arid), .s_arlen(gru_s_arlen),
        .s_arsize(gru_s_arsize), .s_arburst(gru_s_arburst), .s_arlock(gru_s_arlock),
        .s_arcache(gru_s_arcache), .s_arprot(gru_s_arprot), .s_rvalid(gru_s_rvalid),
        .s_rready(gru_s_rready), .s_rdata(gru_s_rdata), .s_rid(gru_s_rid),
        .s_rresp(gru_s_rresp), .s_rlast(gru_s_rlast),
        .m_axi_arid(gru_m_axi_arid), .m_axi_araddr(gru_m_axi_araddr),
        .m_axi_arlen(gru_m_axi_arlen), .m_axi_arsize(gru_m_axi_arsize),
        .m_axi_arburst(gru_m_axi_arburst), .m_axi_arlock(gru_m_axi_arlock),
        .m_axi_arcache(gru_m_axi_arcache), .m_axi_arprot(gru_m_axi_arprot),
        .m_axi_arvalid(gru_m_axi_arvalid), .m_axi_arready(gru_m_axi_arready),
        .m_axi_rid(gru_m_axi_rid), .m_axi_rdata(gru_m_axi_rdata),
        .m_axi_rresp(gru_m_axi_rresp), .m_axi_rlast(gru_m_axi_rlast),
        .m_axi_rvalid(gru_m_axi_rvalid), .m_axi_rready(gru_m_axi_rready),
        .m_axi_awid(gru_m_axi_awid), .m_axi_awaddr(gru_m_axi_awaddr),
        .m_axi_awlen(gru_m_axi_awlen), .m_axi_awsize(gru_m_axi_awsize),
        .m_axi_awburst(gru_m_axi_awburst), .m_axi_awlock(gru_m_axi_awlock),
        .m_axi_awcache(gru_m_axi_awcache), .m_axi_awprot(gru_m_axi_awprot),
        .m_axi_awvalid(gru_m_axi_awvalid), .m_axi_awready(gru_m_axi_awready),
        .m_axi_wdata(gru_m_axi_wdata), .m_axi_wstrb(gru_m_axi_wstrb),
        .m_axi_wlast(gru_m_axi_wlast), .m_axi_wvalid(gru_m_axi_wvalid),
        .m_axi_wready(gru_m_axi_wready), .m_axi_bid(gru_m_axi_bid),
        .m_axi_bresp(gru_m_axi_bresp), .m_axi_bvalid(gru_m_axi_bvalid),
        .m_axi_bready(gru_m_axi_bready),
        .status_axi_error(gru_status_axi_error),
        .status_cfg_error(gru_status_cfg_error),
        .aclk(aclk),
        .aresetn(aresetn)
    );

    lcd_refresh_top u_lcd_refresh_top (
        .s_awvalid(lcd_s_awvalid), .s_awready(lcd_s_awready), .s_awaddr(lcd_s_awaddr),
        .s_awid(lcd_s_awid), .s_awlen(lcd_s_awlen), .s_awsize(lcd_s_awsize),
        .s_awburst(lcd_s_awburst), .s_awlock(lcd_s_awlock), .s_awcache(lcd_s_awcache),
        .s_awprot(lcd_s_awprot), .s_wvalid(lcd_s_wvalid), .s_wready(lcd_s_wready),
        .s_wdata(lcd_s_wdata), .s_wstrb(lcd_s_wstrb), .s_wlast(lcd_s_wlast),
        .s_bvalid(lcd_s_bvalid), .s_bready(lcd_s_bready), .s_bid(lcd_s_bid),
        .s_bresp(lcd_s_bresp), .s_arvalid(lcd_s_arvalid), .s_arready(lcd_s_arready),
        .s_araddr(lcd_s_araddr), .s_arid(lcd_s_arid), .s_arlen(lcd_s_arlen),
        .s_arsize(lcd_s_arsize), .s_arburst(lcd_s_arburst), .s_arlock(lcd_s_arlock),
        .s_arcache(lcd_s_arcache), .s_arprot(lcd_s_arprot), .s_rvalid(lcd_s_rvalid),
        .s_rready(lcd_s_rready), .s_rdata(lcd_s_rdata), .s_rid(lcd_s_rid),
        .s_rresp(lcd_s_rresp), .s_rlast(lcd_s_rlast),
        .m_axi_arid(lcd_m_axi_arid), .m_axi_araddr(lcd_m_axi_araddr),
        .m_axi_arlen(lcd_m_axi_arlen), .m_axi_arsize(lcd_m_axi_arsize),
        .m_axi_arburst(lcd_m_axi_arburst), .m_axi_arlock(lcd_m_axi_arlock),
        .m_axi_arcache(lcd_m_axi_arcache), .m_axi_arprot(lcd_m_axi_arprot),
        .m_axi_arvalid(lcd_m_axi_arvalid), .m_axi_arready(lcd_m_axi_arready),
        .m_axi_rid(lcd_m_axi_rid), .m_axi_rdata(lcd_m_axi_rdata),
        .m_axi_rresp(lcd_m_axi_rresp), .m_axi_rlast(lcd_m_axi_rlast),
        .m_axi_rvalid(lcd_m_axi_rvalid), .m_axi_rready(lcd_m_axi_rready),
        .ddr_init_calib_complete(ddr_init_calib_complete),
        .tft_sdo(tft_sdo), .tft_scl(tft_scl), .tft_sdi(tft_sdi),
        .tft_cs(tft_cs), .tft_rs(tft_rs),
        .refresh_busy(lcd_refresh_busy),
        .refresh_done_evt(lcd_refresh_done_evt),
        .axi_error_evt(lcd_axi_error_evt),
        .spi_error_evt(lcd_spi_error_evt),
        .cfg_error_evt(lcd_cfg_error_evt),
        .aclk(aclk),
        .aresetn(aresetn)
    );

    ddr_axi_arbiter_2m1s u_ddr_axi_arbiter_2m1s (
        .aclk(aclk),
        .aresetn(aresetn),
        .gdu_fifo_critical(1'b0),
        .gdu_fifo_low(1'b0),
        .m0_axi_arid(gru_m_axi_arid), .m0_axi_araddr(gru_m_axi_araddr),
        .m0_axi_arlen(gru_m_axi_arlen), .m0_axi_arsize(gru_m_axi_arsize),
        .m0_axi_arburst(gru_m_axi_arburst), .m0_axi_arlock(gru_m_axi_arlock),
        .m0_axi_arcache(gru_m_axi_arcache), .m0_axi_arprot(gru_m_axi_arprot),
        .m0_axi_arvalid(gru_m_axi_arvalid), .m0_axi_arready(gru_m_axi_arready),
        .m0_axi_rid(gru_m_axi_rid), .m0_axi_rdata(gru_m_axi_rdata),
        .m0_axi_rresp(gru_m_axi_rresp), .m0_axi_rlast(gru_m_axi_rlast),
        .m0_axi_rvalid(gru_m_axi_rvalid), .m0_axi_rready(gru_m_axi_rready),
        .m0_axi_awid(gru_m_axi_awid), .m0_axi_awaddr(gru_m_axi_awaddr),
        .m0_axi_awlen(gru_m_axi_awlen), .m0_axi_awsize(gru_m_axi_awsize),
        .m0_axi_awburst(gru_m_axi_awburst), .m0_axi_awlock(gru_m_axi_awlock),
        .m0_axi_awcache(gru_m_axi_awcache), .m0_axi_awprot(gru_m_axi_awprot),
        .m0_axi_awvalid(gru_m_axi_awvalid), .m0_axi_awready(gru_m_axi_awready),
        .m0_axi_wdata(gru_m_axi_wdata), .m0_axi_wstrb(gru_m_axi_wstrb),
        .m0_axi_wlast(gru_m_axi_wlast), .m0_axi_wvalid(gru_m_axi_wvalid),
        .m0_axi_wready(gru_m_axi_wready), .m0_axi_bid(gru_m_axi_bid),
        .m0_axi_bresp(gru_m_axi_bresp), .m0_axi_bvalid(gru_m_axi_bvalid),
        .m0_axi_bready(gru_m_axi_bready),
        .m1_axi_arid(lcd_m_axi_arid), .m1_axi_araddr(lcd_m_axi_araddr),
        .m1_axi_arlen(lcd_m_axi_arlen), .m1_axi_arsize(lcd_m_axi_arsize),
        .m1_axi_arburst(lcd_m_axi_arburst), .m1_axi_arlock(lcd_m_axi_arlock),
        .m1_axi_arcache(lcd_m_axi_arcache), .m1_axi_arprot(lcd_m_axi_arprot),
        .m1_axi_arvalid(lcd_m_axi_arvalid), .m1_axi_arready(lcd_m_axi_arready),
        .m1_axi_rid(lcd_m_axi_rid), .m1_axi_rdata(lcd_m_axi_rdata),
        .m1_axi_rresp(lcd_m_axi_rresp), .m1_axi_rlast(lcd_m_axi_rlast),
        .m1_axi_rvalid(lcd_m_axi_rvalid), .m1_axi_rready(lcd_m_axi_rready),
        .s0_axi_arid(ddr_axi128_arid), .s0_axi_araddr(ddr_axi128_araddr),
        .s0_axi_arlen(ddr_axi128_arlen), .s0_axi_arsize(ddr_axi128_arsize),
        .s0_axi_arburst(ddr_axi128_arburst), .s0_axi_arlock(ddr_axi128_arlock),
        .s0_axi_arcache(ddr_axi128_arcache), .s0_axi_arprot(ddr_axi128_arprot),
        .s0_axi_arvalid(ddr_axi128_arvalid), .s0_axi_arready(ddr_axi128_arready),
        .s0_axi_rid(ddr_axi128_rid), .s0_axi_rdata(ddr_axi128_rdata),
        .s0_axi_rresp(ddr_axi128_rresp), .s0_axi_rlast(ddr_axi128_rlast),
        .s0_axi_rvalid(ddr_axi128_rvalid), .s0_axi_rready(ddr_axi128_rready),
        .s0_axi_awid(ddr_axi128_awid), .s0_axi_awaddr(ddr_axi128_awaddr),
        .s0_axi_awlen(ddr_axi128_awlen), .s0_axi_awsize(ddr_axi128_awsize),
        .s0_axi_awburst(ddr_axi128_awburst), .s0_axi_awlock(ddr_axi128_awlock),
        .s0_axi_awcache(ddr_axi128_awcache), .s0_axi_awprot(ddr_axi128_awprot),
        .s0_axi_awvalid(ddr_axi128_awvalid), .s0_axi_awready(ddr_axi128_awready),
        .s0_axi_wdata(ddr_axi128_wdata), .s0_axi_wstrb(ddr_axi128_wstrb),
        .s0_axi_wlast(ddr_axi128_wlast), .s0_axi_wvalid(ddr_axi128_wvalid),
        .s0_axi_wready(ddr_axi128_wready), .s0_axi_bid(ddr_axi128_bid),
        .s0_axi_bresp(ddr_axi128_bresp), .s0_axi_bvalid(ddr_axi128_bvalid),
        .s0_axi_bready(ddr_axi128_bready),
        .gru_read_grant_count(unused_arb_gru_grant),
        .gdu_read_grant_count(unused_arb_gdu_grant),
        .gru_wait_cycle_count(unused_arb_gru_wait),
        .gdu_wait_cycle_count(unused_arb_gdu_wait),
        .gru_max_wait_cycles(unused_arb_gru_max_wait),
        .gdu_max_wait_cycles(unused_arb_gdu_max_wait),
        .gdu_qos_override_count(unused_arb_qos),
        .gdu_critical_override_count(unused_arb_critical),
        .gru_starvation_relief_count(unused_arb_starve)
    );

    ddr_ctrl_top #(
        .SIMULATION(SIMULATION),
        .SIM_AW(SIM_AW),
        .SIM_USE_FAST_RAM(SIM_USE_FAST_RAM)
    ) u_ddr_ctrl_top (
        .sys_clk(aclk),
        .sys_resetn(aresetn),
        .ddr_sys_clk(aclk),
        .ddr_ref_clk(ddr_ref_clk),
        .s_axi_arid(ddr_axi128_arid), .s_axi_araddr(ddr_axi128_araddr),
        .s_axi_arlen(ddr_axi128_arlen), .s_axi_arsize(ddr_axi128_arsize),
        .s_axi_arburst(ddr_axi128_arburst), .s_axi_arlock(ddr_axi128_arlock),
        .s_axi_arcache(ddr_axi128_arcache), .s_axi_arprot(ddr_axi128_arprot),
        .s_axi_arvalid(ddr_axi128_arvalid), .s_axi_arready(ddr_axi128_arready),
        .s_axi_rid(ddr_axi128_rid), .s_axi_rdata(ddr_axi128_rdata),
        .s_axi_rresp(ddr_axi128_rresp), .s_axi_rlast(ddr_axi128_rlast),
        .s_axi_rvalid(ddr_axi128_rvalid), .s_axi_rready(ddr_axi128_rready),
        .s_axi_awid(ddr_axi128_awid), .s_axi_awaddr(ddr_axi128_awaddr),
        .s_axi_awlen(ddr_axi128_awlen), .s_axi_awsize(ddr_axi128_awsize),
        .s_axi_awburst(ddr_axi128_awburst), .s_axi_awlock(ddr_axi128_awlock),
        .s_axi_awcache(ddr_axi128_awcache), .s_axi_awprot(ddr_axi128_awprot),
        .s_axi_awvalid(ddr_axi128_awvalid), .s_axi_awready(ddr_axi128_awready),
        .s_axi_wdata(ddr_axi128_wdata), .s_axi_wstrb(ddr_axi128_wstrb),
        .s_axi_wlast(ddr_axi128_wlast), .s_axi_wvalid(ddr_axi128_wvalid),
        .s_axi_wready(ddr_axi128_wready), .s_axi_bid(ddr_axi128_bid),
        .s_axi_bresp(ddr_axi128_bresp), .s_axi_bvalid(ddr_axi128_bvalid),
        .s_axi_bready(ddr_axi128_bready),
        .init_calib_complete(ddr_init_calib_complete),
        .ddr3_dq(ddr3_dq), .ddr3_dqs_n(ddr3_dqs_n), .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_addr(ddr3_addr), .ddr3_ba(ddr3_ba), .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n), .ddr3_we_n(ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n), .ddr3_ck_p(ddr3_ck_p),
        .ddr3_ck_n(ddr3_ck_n), .ddr3_cke(ddr3_cke), .ddr3_cs_n(ddr3_cs_n),
        .ddr3_dm(ddr3_dm), .ddr3_odt(ddr3_odt)
    );

endmodule
