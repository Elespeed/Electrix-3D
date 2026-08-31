module ddr_ctrl_top #(
    parameter SIMULATION = 1'b0,
    parameter SIM_AW = 19,
    parameter SIM_USE_FAST_RAM = 1'b0
) (
    input  wire        sys_clk,
    input  wire        sys_resetn,
    input  wire        ddr_sys_clk,
    input  wire        ddr_ref_clk,

    // AXI slave (SoC side, 5-bit ID)
    input  wire [4:0]  s_axi_arid,
    input  wire [31:0] s_axi_araddr,
    input  wire [7:0]  s_axi_arlen,
    input  wire [2:0]  s_axi_arsize,
    input  wire [1:0]  s_axi_arburst,
    input  wire        s_axi_arlock,
    input  wire [3:0]  s_axi_arcache,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [4:0]  s_axi_rid,
    output wire [127:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rlast,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    input  wire [4:0]  s_axi_awid,
    input  wire [31:0] s_axi_awaddr,
    input  wire [7:0]  s_axi_awlen,
    input  wire [2:0]  s_axi_awsize,
    input  wire [1:0]  s_axi_awburst,
    input  wire        s_axi_awlock,
    input  wire [3:0]  s_axi_awcache,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [127:0] s_axi_wdata,
    input  wire [15:0]  s_axi_wstrb,
    input  wire        s_axi_wlast,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [4:0]  s_axi_bid,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    output wire        init_calib_complete,

    // DDR PHY pins
    inout  wire [31:0] ddr3_dq,
    inout  wire [3:0]  ddr3_dqs_n,
    inout  wire [3:0]  ddr3_dqs_p,
    output wire [14:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,
    output wire [3:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt
);

// Sticky indicator for future DMA multi-master migration:
// if ID[4] is ever used, low-4bit truncation is no longer safe.
(* keep = "true" *) reg id_highbit_violation;
always @(posedge sys_clk or negedge sys_resetn) begin
    if (!sys_resetn) begin
        id_highbit_violation <= 1'b0;
    end else begin
        if ((s_axi_awvalid && s_axi_awready && s_axi_awid[4]) ||
            (s_axi_arvalid && s_axi_arready && s_axi_arid[4])) begin
            id_highbit_violation <= 1'b1;
        end
    end
end

generate
if (SIMULATION && SIM_USE_FAST_RAM) begin : gen_sim
    assign init_calib_complete = sys_resetn;

    assign ddr3_addr    = 15'd0;
    assign ddr3_ba      = 3'd0;
    assign ddr3_ras_n   = 1'b1;
    assign ddr3_cas_n   = 1'b1;
    assign ddr3_we_n    = 1'b1;
    assign ddr3_reset_n = 1'b1;
    assign ddr3_ck_p    = 1'b0;
    assign ddr3_ck_n    = 1'b0;
    assign ddr3_cke     = 1'b0;
    assign ddr3_cs_n    = 1'b1;
    assign ddr3_dm      = 4'd0;
    assign ddr3_odt     = 1'b0;
    assign ddr3_dq      = {32{1'bz}};
    assign ddr3_dqs_n   = {4{1'bz}};
    assign ddr3_dqs_p   = {4{1'bz}};

    axi_wrap_ram_sp #(
        .AW        (SIM_AW),
        .DATA_WIDTH(128),
        .Init_File ("none")
    ) u_ddr_sim_ram (
        .aclk       (sys_clk),
        .aresetn    (sys_resetn),
        .axi_arid   (s_axi_arid),
        .axi_araddr (s_axi_araddr),
        .axi_arlen  (s_axi_arlen),
        .axi_arsize (s_axi_arsize),
        .axi_arburst(s_axi_arburst),
        .axi_arlock ({1'b0, s_axi_arlock}),
        .axi_arcache(s_axi_arcache),
        .axi_arprot (s_axi_arprot),
        .axi_arvalid(s_axi_arvalid),
        .axi_arready(s_axi_arready),
        .axi_rid    (s_axi_rid),
        .axi_rdata  (s_axi_rdata),
        .axi_rresp  (s_axi_rresp),
        .axi_rlast  (s_axi_rlast),
        .axi_rvalid (s_axi_rvalid),
        .axi_rready (s_axi_rready),
        .axi_awid   (s_axi_awid),
        .axi_awaddr (s_axi_awaddr),
        .axi_awlen  (s_axi_awlen),
        .axi_awsize (s_axi_awsize),
        .axi_awburst(s_axi_awburst),
        .axi_awlock ({1'b0, s_axi_awlock}),
        .axi_awcache(s_axi_awcache),
        .axi_awprot (s_axi_awprot),
        .axi_awvalid(s_axi_awvalid),
        .axi_awready(s_axi_awready),
        .axi_wdata  (s_axi_wdata),
        .axi_wstrb  (s_axi_wstrb),
        .axi_wlast  (s_axi_wlast),
        .axi_wvalid (s_axi_wvalid),
        .axi_wready (s_axi_wready),
        .axi_bid    (s_axi_bid),
        .axi_bresp  (s_axi_bresp),
        .axi_bvalid (s_axi_bvalid),
        .axi_bready (s_axi_bready)
    );
end else begin : gen_mig
    wire        mig_ui_clk;
    wire        mig_ui_clk_sync_rst;
    wire        mig_mmcm_locked;
    wire        mig_init_calib_complete;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg mig_init_calib_complete_meta;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg mig_init_calib_complete_sys;
    wire [13:0] mig_ddr3_addr;
    wire [11:0] mig_device_temp;

    // CDC (SoC-side ports)
    wire        cdc_in_awready;
    wire        cdc_in_wready;
    wire [4:0]  cdc_in_bid;
    wire [1:0]  cdc_in_bresp;
    wire        cdc_in_bvalid;
    wire        cdc_in_arready;
    wire [4:0]   cdc_in_rid;
    wire [127:0] cdc_in_rdata;
    wire [1:0]  cdc_in_rresp;
    wire        cdc_in_rlast;
    wire        cdc_in_rvalid;

    // CDC (MIG-side ports)
    wire [4:0]  cdc_out_awid;
    wire [31:0] cdc_out_awaddr;
    wire [7:0]  cdc_out_awlen;
    wire [2:0]  cdc_out_awsize;
    wire [1:0]  cdc_out_awburst;
    wire [0:0]  cdc_out_awlock;
    wire [3:0]  cdc_out_awcache;
    wire [2:0]  cdc_out_awprot;
    wire        cdc_out_awvalid;
    wire        cdc_out_awready;
    wire [127:0] cdc_out_wdata;
    wire [15:0]  cdc_out_wstrb;
    wire        cdc_out_wlast;
    wire        cdc_out_wvalid;
    wire        cdc_out_wready;
    wire [4:0]  cdc_out_bid;
    wire [1:0]  cdc_out_bresp;
    wire        cdc_out_bvalid;
    wire        cdc_out_bready;
    wire [4:0]  cdc_out_arid;
    wire [31:0] cdc_out_araddr;
    wire [7:0]  cdc_out_arlen;
    wire [2:0]  cdc_out_arsize;
    wire [1:0]  cdc_out_arburst;
    wire [0:0]  cdc_out_arlock;
    wire [3:0]  cdc_out_arcache;
    wire [2:0]  cdc_out_arprot;
    wire        cdc_out_arvalid;
    wire        cdc_out_arready;
    wire [4:0]   cdc_out_rid;
    wire [127:0] cdc_out_rdata;
    wire [1:0]  cdc_out_rresp;
    wire        cdc_out_rlast;
    wire        cdc_out_rvalid;
    wire        cdc_out_rready;

    wire [3:0]  mig_awid;
    wire [28:0] mig_awaddr;
    wire [7:0]  mig_awlen;
    wire [2:0]  mig_awsize;
    wire [1:0]  mig_awburst;
    wire [0:0]  mig_awlock;
    wire [3:0]  mig_awcache;
    wire [2:0]  mig_awprot;
    wire        mig_awvalid;
    wire        mig_awready;
    wire [127:0] mig_wdata;
    wire [15:0]  mig_wstrb;
    wire        mig_wlast;
    wire        mig_wvalid;
    wire        mig_wready;
    wire [3:0]  mig_bid;
    wire [1:0]  mig_bresp;
    wire        mig_bvalid;
    wire        mig_bready;
    wire [3:0]  mig_arid;
    wire [28:0] mig_araddr;
    wire [7:0]  mig_arlen;
    wire [2:0]  mig_arsize;
    wire [1:0]  mig_arburst;
    wire [0:0]  mig_arlock;
    wire [3:0]  mig_arcache;
    wire [2:0]  mig_arprot;
    wire        mig_arvalid;
    wire        mig_arready;
    wire [3:0]   mig_rid;
    wire [127:0] mig_rdata;
    wire [1:0]  mig_rresp;
    wire        mig_rlast;
    wire        mig_rvalid;
    wire        mig_rready;

    wire mig_axi_resetn = sys_resetn & mig_mmcm_locked & (~mig_ui_clk_sync_rst);

    // MIG calibration-complete is generated in the MIG UI clock domain.
    // Re-synchronize it before using it in the SoC sys_clk domain.
    always @(posedge sys_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            mig_init_calib_complete_meta <= 1'b0;
            mig_init_calib_complete_sys  <= 1'b0;
        end else begin
            mig_init_calib_complete_meta <= mig_init_calib_complete;
            mig_init_calib_complete_sys  <= mig_init_calib_complete_meta;
        end
    end

    // Access is blocked until MIG calibration is complete.
    assign s_axi_awready = mig_init_calib_complete_sys ? cdc_in_awready : 1'b0;
    assign s_axi_wready  = mig_init_calib_complete_sys ? cdc_in_wready  : 1'b0;
    assign s_axi_arready = mig_init_calib_complete_sys ? cdc_in_arready : 1'b0;
    assign s_axi_bvalid  = cdc_in_bvalid;
    assign s_axi_bid     = cdc_in_bid;
    assign s_axi_bresp   = cdc_in_bresp;
    assign s_axi_rvalid  = cdc_in_rvalid;
    assign s_axi_rid     = cdc_in_rid;
    assign s_axi_rdata   = cdc_in_rdata;
    assign s_axi_rresp   = cdc_in_rresp;
    assign s_axi_rlast   = cdc_in_rlast;
    assign init_calib_complete = mig_init_calib_complete_sys;
    assign ddr3_addr = {1'b0, mig_ddr3_addr};

    Axi_CDC u_ddr_axi_cdc (
        .axiInClk       (sys_clk),
        .axiInRstn      (sys_resetn),
        .axiOutClk      (mig_ui_clk),
        .axiOutRstn     (mig_axi_resetn),
        .axiIn_awvalid  (s_axi_awvalid & mig_init_calib_complete_sys),
        .axiIn_awready  (cdc_in_awready),
        .axiIn_awaddr   (s_axi_awaddr),
        .axiIn_awid     (s_axi_awid),
        .axiIn_awlen    (s_axi_awlen),
        .axiIn_awsize   (s_axi_awsize),
        .axiIn_awburst  (s_axi_awburst),
        .axiIn_awlock   (s_axi_awlock),
        .axiIn_awcache  (s_axi_awcache),
        .axiIn_awprot   (s_axi_awprot),
        .axiIn_wvalid   (s_axi_wvalid & mig_init_calib_complete_sys),
        .axiIn_wready   (cdc_in_wready),
        .axiIn_wdata    (s_axi_wdata),
        .axiIn_wstrb    (s_axi_wstrb),
        .axiIn_wlast    (s_axi_wlast),
        .axiIn_bvalid   (cdc_in_bvalid),
        .axiIn_bready   (s_axi_bready),
        .axiIn_bid      (cdc_in_bid),
        .axiIn_bresp    (cdc_in_bresp),
        .axiIn_arvalid  (s_axi_arvalid & mig_init_calib_complete_sys),
        .axiIn_arready  (cdc_in_arready),
        .axiIn_araddr   (s_axi_araddr),
        .axiIn_arid     (s_axi_arid),
        .axiIn_arlen    (s_axi_arlen),
        .axiIn_arsize   (s_axi_arsize),
        .axiIn_arburst  (s_axi_arburst),
        .axiIn_arlock   (s_axi_arlock),
        .axiIn_arcache  (s_axi_arcache),
        .axiIn_arprot   (s_axi_arprot),
        .axiIn_rvalid   (cdc_in_rvalid),
        .axiIn_rready   (s_axi_rready),
        .axiIn_rdata    (cdc_in_rdata),
        .axiIn_rid      (cdc_in_rid),
        .axiIn_rresp    (cdc_in_rresp),
        .axiIn_rlast    (cdc_in_rlast),
        .axiOut_awvalid (cdc_out_awvalid),
        .axiOut_awready (cdc_out_awready),
        .axiOut_awaddr  (cdc_out_awaddr),
        .axiOut_awid    (cdc_out_awid),
        .axiOut_awlen   (cdc_out_awlen),
        .axiOut_awsize  (cdc_out_awsize),
        .axiOut_awburst (cdc_out_awburst),
        .axiOut_awlock  (cdc_out_awlock),
        .axiOut_awcache (cdc_out_awcache),
        .axiOut_awprot  (cdc_out_awprot),
        .axiOut_wvalid  (cdc_out_wvalid),
        .axiOut_wready  (cdc_out_wready),
        .axiOut_wdata   (cdc_out_wdata),
        .axiOut_wstrb   (cdc_out_wstrb),
        .axiOut_wlast   (cdc_out_wlast),
        .axiOut_bvalid  (cdc_out_bvalid),
        .axiOut_bready  (cdc_out_bready),
        .axiOut_bid     (cdc_out_bid),
        .axiOut_bresp   (cdc_out_bresp),
        .axiOut_arvalid (cdc_out_arvalid),
        .axiOut_arready (cdc_out_arready),
        .axiOut_araddr  (cdc_out_araddr),
        .axiOut_arid    (cdc_out_arid),
        .axiOut_arlen   (cdc_out_arlen),
        .axiOut_arsize  (cdc_out_arsize),
        .axiOut_arburst (cdc_out_arburst),
        .axiOut_arlock  (cdc_out_arlock),
        .axiOut_arcache (cdc_out_arcache),
        .axiOut_arprot  (cdc_out_arprot),
        .axiOut_rvalid  (cdc_out_rvalid),
        .axiOut_rready  (cdc_out_rready),
        .axiOut_rdata   (cdc_out_rdata),
        .axiOut_rid     (cdc_out_rid),
        .axiOut_rresp   (cdc_out_rresp),
        .axiOut_rlast   (cdc_out_rlast)
    );

    // 5-bit to 4-bit request ID adaptation.
    assign mig_awid       = cdc_out_awid[3:0];
    assign mig_awaddr     = cdc_out_awaddr[28:0];
    assign mig_awlen      = cdc_out_awlen;
    assign mig_awsize     = cdc_out_awsize;
    assign mig_awburst    = cdc_out_awburst;
    assign mig_awlock     = cdc_out_awlock;
    assign mig_awcache    = cdc_out_awcache;
    assign mig_awprot     = cdc_out_awprot;
    assign mig_awvalid    = cdc_out_awvalid;
    assign cdc_out_awready = mig_awready;
    assign mig_wdata      = cdc_out_wdata;
    assign mig_wstrb      = cdc_out_wstrb;
    assign mig_wlast      = cdc_out_wlast;
    assign mig_wvalid     = cdc_out_wvalid;
    assign cdc_out_wready = mig_wready;
    assign cdc_out_bid    = {1'b0, mig_bid};
    assign cdc_out_bresp  = mig_bresp;
    assign cdc_out_bvalid = mig_bvalid;
    assign mig_bready     = cdc_out_bready;
    assign mig_arid       = cdc_out_arid[3:0];
    assign mig_araddr     = cdc_out_araddr[28:0];
    assign mig_arlen      = cdc_out_arlen;
    assign mig_arsize     = cdc_out_arsize;
    assign mig_arburst    = cdc_out_arburst;
    assign mig_arlock     = cdc_out_arlock;
    assign mig_arcache    = cdc_out_arcache;
    assign mig_arprot     = cdc_out_arprot;
    assign mig_arvalid    = cdc_out_arvalid;
    assign cdc_out_arready = mig_arready;
    assign cdc_out_rid    = {1'b0, mig_rid};
    assign cdc_out_rdata  = mig_rdata;
    assign cdc_out_rresp  = mig_rresp;
    assign cdc_out_rlast  = mig_rlast;
    assign cdc_out_rvalid = mig_rvalid;
    assign mig_rready     = cdc_out_rready;

    mig_r u_mig (
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .ddr3_addr           (mig_ddr3_addr),
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
        .ddr3_odt            (ddr3_odt),
        .sys_clk_i           (ddr_sys_clk),
        .clk_ref_i           (ddr_ref_clk),
        .ui_clk              (mig_ui_clk),
        .ui_clk_sync_rst     (mig_ui_clk_sync_rst),
        .mmcm_locked         (mig_mmcm_locked),
        .aresetn             (sys_resetn),
        .sys_rst             (sys_resetn),
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),
        .init_calib_complete (mig_init_calib_complete),
        .device_temp         (mig_device_temp),
        .s_axi_awid          (mig_awid),
        .s_axi_awaddr        (mig_awaddr),
        .s_axi_awlen         (mig_awlen),
        .s_axi_awsize        (mig_awsize),
        .s_axi_awburst       (mig_awburst),
        .s_axi_awlock        (mig_awlock),
        .s_axi_awcache       (mig_awcache),
        .s_axi_awprot        (mig_awprot),
        .s_axi_awqos         (4'd0),
        .s_axi_awvalid       (mig_awvalid),
        .s_axi_awready       (mig_awready),
        .s_axi_wdata         (mig_wdata),
        .s_axi_wstrb         (mig_wstrb),
        .s_axi_wlast         (mig_wlast),
        .s_axi_wvalid        (mig_wvalid),
        .s_axi_wready        (mig_wready),
        .s_axi_bid           (mig_bid),
        .s_axi_bresp         (mig_bresp),
        .s_axi_bvalid        (mig_bvalid),
        .s_axi_bready        (mig_bready),
        .s_axi_arid          (mig_arid),
        .s_axi_araddr        (mig_araddr),
        .s_axi_arlen         (mig_arlen),
        .s_axi_arsize        (mig_arsize),
        .s_axi_arburst       (mig_arburst),
        .s_axi_arlock        (mig_arlock),
        .s_axi_arcache       (mig_arcache),
        .s_axi_arprot        (mig_arprot),
        .s_axi_arqos         (4'd0),
        .s_axi_arvalid       (mig_arvalid),
        .s_axi_arready       (mig_arready),
        .s_axi_rid           (mig_rid),
        .s_axi_rdata         (mig_rdata),
        .s_axi_rresp         (mig_rresp),
        .s_axi_rlast         (mig_rlast),
        .s_axi_rvalid        (mig_rvalid),
        .s_axi_rready        (mig_rready)
    );
end
endgenerate

endmodule
