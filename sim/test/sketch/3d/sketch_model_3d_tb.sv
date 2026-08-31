`timescale 1ns/1ps
module sketch_model_3d_tb #(
`ifdef MODELSIM_BUILD
    parameter string INIT_FILE = "../../../assets/3d/generated/cat1/legacy_v3/cat1.s3d.mif",
`else
    parameter string INIT_FILE = "../../assets/3d/generated/cat1/legacy_v3/cat1.s3d.mif",
`endif
    parameter [8*64-1:0] TESTCASE = "sketch_model_3d_tb"
);
    logic clk, resetn, start, busy, error;
    logic [31:0] frame_count;
    logic [4:0] arid, rid;
    logic [31:0] araddr, rdata;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst, rresp;
    logic arlock, arvalid, arready, rlast, rvalid, rready;
    logic [3:0] arcache;
    logic [2:0] arprot;
    logic dvi_clk, dvi_hs, dvi_vs, dvi_de;
    logic [7:0] dvi_d;
    logic mon_err, ref_err;
    logic [31:0] clears, tris, presents;

    always #10 clk = ~clk;

    initial begin
        clk = 0;
        resetn = 0;
        start = 0;
        #200 resetn = 1;
        #40 start = 1;
        #20 start = 0;
    end

    sketch_model_demo_top dut(
        .*,
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready), .m_axi_rid(rid), .m_axi_rdata(rdata),
        .m_axi_rresp(rresp), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    sketch_ext_sram_agent #(.INIT_FILE(INIT_FILE)) mem(
        .clk, .resetn, .s_arid(arid), .s_araddr(araddr), .s_arlen(arlen), .s_arsize(arsize),
        .s_arburst(arburst), .s_arlock(arlock), .s_arcache(arcache), .s_arprot(arprot),
        .s_arvalid(arvalid), .s_arready(arready), .s_rid(rid), .s_rdata(rdata),
        .s_rresp(rresp), .s_rlast(rlast), .s_rvalid(rvalid), .s_rready(rready)
    );

    sketch_cmd_monitor cmdmon(
        .clk, .resetn, .valid(dut.mmio_valid), .we(dut.mmio_we), .ready(dut.mmio_ready),
        .addr(dut.mmio_addr), .wdata(dut.mmio_wdata), .error(mon_err),
        .clear_count(clears), .tri_count(tris), .present_count(presents)
    );

    model_scene_ref_agent refmon(
        .clk, .resetn, .valid(dut.mmio_valid), .we(dut.mmio_we), .ready(dut.mmio_ready),
        .addr(dut.mmio_addr), .wdata(dut.mmio_wdata), .error(ref_err)
    );

    dvi_monitor_800x600 #(
        .FRAME_DUMP_LIMIT(0), .TESTCASE(TESTCASE), .OUTPUT_ROOT("../../../sim/frame_output")
    ) dvi(
        .video_clk(dvi_clk), .resetn,
        .video_red({dvi_d[7:5], dvi_d[7:6]}),
        .video_green({dvi_d[4:2], dvi_d[4:2]}),
        .video_blue({dvi_d[1:0], dvi_d[1:0], dvi_d[1]}),
        .video_hsync(dvi_hs), .video_vsync(dvi_vs), .video_de(dvi_de)
    );

    initial begin
        wait (frame_count >= 16);
        if (error || mon_err || ref_err) $fatal(1, "[model] core=%b protocol=%b ref=%b", error, mon_err, ref_err);
        if (clears < 16 || presents < 16 || tris == 0) $fatal(1, "[model] insufficient commands c=%0d t=%0d p=%0d", clears, tris, presents);
        $display("[SKETCH_MODEL] PASS frames=%0d clear=%0d triangles=%0d presents=%0d", frame_count, clears, tris, presents);
        #100;
        $finish;
    end

    initial begin
        #900_000_000;
        $fatal(1, "[model] timeout frames=%0d", frame_count);
    end
endmodule
