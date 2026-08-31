`timescale 1ns/1ps

// Minimal control test for the home-page ownership handoff:
// Scene owns SketchBook while it emits CLEAR/TRIANGLE/PRESENT.  A UI cursor
// update aborts Scene immediately after its viewport-local CLEAR, then submits
// one CPU-side patch plus PRESENT.  This intentionally verifies the narrower
// command-ordering contract first: commands already accepted by SketchBook
// retire before the CPU patch.  A separate page-coherency test will model the
// stale UI content held by the second framebuffer page.
module scene_sk_ui_abort_tb;
`ifdef MODELSIM_BUILD
    localparam string INIT_FILE = "../../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`else
    localparam string INIT_FILE = "../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`endif
    localparam logic [7:0] COLOR_PANEL = 8'h12;
    localparam logic [7:0] COLOR_YELLOW = 8'hfc;

    logic clk = 0, resetn = 0;
    always #10 clk = ~clk;

    logic s_awvalid, s_awready, s_wvalid, s_wready, s_wlast, s_bvalid, s_bready = 1;
    logic s_arvalid, s_arready, s_rvalid, s_rready = 1, s_rlast;
    logic [31:0] s_awaddr, s_wdata, s_araddr, s_rdata;
    logic [3:0] s_wstrb;
    logic [4:0] s_awid, s_bid, s_arid, s_rid;
    logic [7:0] s_awlen, s_arlen;
    logic [2:0] s_awsize, s_arsize;
    logic [1:0] s_awburst, s_arburst, s_bresp, s_rresp;
    logic s_awlock, s_arlock;
    logic [3:0] s_awcache, s_arcache;
    logic [2:0] s_awprot, s_arprot;

    logic [4:0] m_axi_arid, m_axi_rid;
    logic [31:0] m_axi_araddr, m_axi_rdata;
    logic [7:0] m_axi_arlen;
    logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst, m_axi_rresp;
    logic m_axi_arlock, m_axi_arvalid, m_axi_arready, m_axi_rlast, m_axi_rvalid, m_axi_rready;
    logic [3:0] m_axi_arcache;
    logic [2:0] m_axi_arprot;

    logic scene_valid, scene_we, scene_ready;
    logic [31:0] scene_addr, scene_wdata, scene_rdata;
    logic cpu_valid, cpu_we, cpu_ready;
    logic [31:0] cpu_addr, cpu_wdata, cpu_rdata;
    logic sketch_valid, sketch_we, sketch_ready;
    logic [31:0] sketch_addr, sketch_wdata, sketch_rdata;
    logic dvi_clk, dvi_hs, dvi_vs, dvi_de;
    logic [7:0] dvi_d;
    logic irq_done, err_active_write;
    logic mon_error;
    logic [31:0] clears, fills, tris, presents;
    integer fills_before_abort;
    integer fid;

    task automatic scene_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            s_awaddr <= addr; s_awid <= 0; s_awlen <= 0; s_awsize <= 3'd2; s_awburst <= 2'b01;
            s_awlock <= 0; s_awcache <= 0; s_awprot <= 0; s_awvalid <= 1;
            while (!s_awready) @(posedge clk);
            @(posedge clk); s_awvalid <= 0; s_wdata <= data; s_wstrb <= 4'hf; s_wlast <= 1; s_wvalid <= 1;
            while (!s_wready) @(posedge clk);
            @(posedge clk); s_wvalid <= 0;
            while (!s_bvalid) @(posedge clk);
            if (s_bresp != 0) $fatal(1, "scene register write response");
        end
    endtask

    task automatic cpu_write(input logic [11:0] addr, input logic [31:0] data);
        begin
            // Drive away from the sampling edge; otherwise a zero-latency
            // MMIO-ready response can race the testbench deassertion.
            @(negedge clk);
            cpu_addr = {20'd0, addr}; cpu_wdata = data; cpu_we = 1; cpu_valid = 1;
            do @(posedge clk); while (!cpu_ready);
            @(negedge clk);
            cpu_valid = 0;
        end
    endtask

    task automatic cpu_fill_rect(input logic [15:0] x, input logic [15:0] y,
                                 input logic [15:0] width, input logic [15:0] height,
                                 input logic [7:0] color);
        begin
            cpu_write(12'h008, {19'd0, color, 5'd2});
            cpu_write(12'h00c, {y, x});
            cpu_write(12'h010, {height, width});
            cpu_write(12'h014, 0);
            cpu_write(12'h018, 1);
        end
    endtask

    task automatic cpu_present;
        begin
            cpu_write(12'h008, 5'd6);
            cpu_write(12'h00c, 0);
            cpu_write(12'h010, 0);
            cpu_write(12'h014, 0);
            cpu_write(12'h018, 1);
        end
    endtask

    task automatic wait_pixel(input integer x, input integer y,
                              input integer r, input integer g, input integer b,
                              input [8*48-1:0] label);
        integer index, waited;
        begin
            index = y * 800 + x;
            fid = dvi.captured_frame_id;
            for (waited = 0; waited < 12; waited = waited + 1) begin
                wait (dvi.captured_frame_id > fid);
                fid = dvi.captured_frame_id;
                if (dvi.captured_frame_r[index] == r && dvi.captured_frame_g[index] == g &&
                    dvi.captured_frame_b[index] == b) return;
            end
            $fatal(1, "%0s did not appear", label);
        end
    endtask

    scene_ctrl_top scene(.*,
        .mmio_valid(scene_valid), .mmio_we(scene_we), .mmio_addr(scene_addr), .mmio_wdata(scene_wdata),
        .mmio_rdata(scene_rdata), .mmio_ready(scene_ready));
    sketch_mmio_arbiter arb(
        .scene_busy(scene.busy),
        .cpu_valid, .cpu_we, .cpu_addr, .cpu_wdata, .cpu_rdata, .cpu_ready,
        .scene_valid, .scene_we, .scene_addr, .scene_wdata, .scene_rdata, .scene_ready,
        .sk_valid(sketch_valid), .sk_we(sketch_we), .sk_addr(sketch_addr), .sk_wdata(sketch_wdata),
        .sk_rdata(sketch_rdata), .sk_ready(sketch_ready));
    sketch_book_top sketch(
        .clk, .resetn, .mmio_valid(sketch_valid), .mmio_we(sketch_we), .mmio_addr(sketch_addr),
        .mmio_wdata(sketch_wdata), .mmio_rdata(sketch_rdata), .mmio_ready(sketch_ready),
        .dvi_clk, .dvi_hs, .dvi_vs, .dvi_de, .dvi_d, .irq_done, .err_active_write);
    sketch_ext_sram_agent #(.INIT_FILE(INIT_FILE)) mem(.*,
        .s_arid(m_axi_arid), .s_araddr(m_axi_araddr), .s_arlen(m_axi_arlen), .s_arsize(m_axi_arsize),
        .s_arburst(m_axi_arburst), .s_arlock(m_axi_arlock), .s_arcache(m_axi_arcache), .s_arprot(m_axi_arprot),
        .s_arvalid(m_axi_arvalid), .s_arready(m_axi_arready), .s_rid(m_axi_rid), .s_rdata(m_axi_rdata),
        .s_rresp(m_axi_rresp), .s_rlast(m_axi_rlast), .s_rvalid(m_axi_rvalid), .s_rready(m_axi_rready));
    sketch_cmd_monitor cm(.clk, .resetn, .valid(sketch_valid), .we(sketch_we), .ready(sketch_ready),
        .addr(sketch_addr), .wdata(sketch_wdata), .error(mon_error), .clear_count(clears),
        .fill_count(fills), .tri_count(tris), .present_count(presents));
    dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0), .TESTCASE("scene_sk_ui_abort_tb"),
        .OUTPUT_ROOT("../../../sim/frame_output")) dvi(
        .video_clk(dvi_clk), .resetn, .video_red({dvi_d[7:5], dvi_d[7:6]}),
        .video_green({dvi_d[4:2], dvi_d[4:2]}), .video_blue({dvi_d[1:0], dvi_d[1:0], dvi_d[1]}),
        .video_hsync(dvi_hs), .video_vsync(dvi_vs), .video_de(dvi_de));

    initial begin
        s_awvalid = 0; s_wvalid = 0; s_arvalid = 0; s_awaddr = 0; s_wdata = 0; s_wstrb = 0; s_wlast = 0;
        cpu_valid = 0; cpu_we = 1; cpu_addr = 0; cpu_wdata = 0;
        #200 resetn = 1;
        scene_write(32'h00c, 32'd1536);
        scene_write(32'h02c, {16'd72, 16'd200});
        scene_write(32'h030, {16'd174, 16'd168});
        scene_write(32'h034, 32'h3);
        scene_write(32'h01c, {16'd159, 16'd284});
        scene_write(32'h024, 32'h1f); // local clear + auto-present + animation
        scene_write(32'h028, COLOR_PANEL);
        scene_write(32'h000, 32'h2);
        wait (scene.model_valid);
        scene_write(32'h000, 32'h4);
        wait (scene.frame_count >= 2);

        // Stop at the first local-clear command of the next frame, before the
        // corresponding triangles/PRESENT are all issued.
        fills_before_abort = fills;
        wait (fills > fills_before_abort);
        scene_write(32'h000, 32'h8);
        wait (!scene.busy);

        // Same class of delta as update_home_cursor(): one small UI patch and
        // one PRESENT.  It runs behind the Scene command already in the FIFO.
        cpu_fill_rect(16'd22, 16'd126, 16'd8, 16'd8, COLOR_YELLOW);
        cpu_present();
        wait_pixel(44, 252, 255, 255, 0, "CPU cursor patch");
        wait_pixel(568, 318, 181, 219, 173, "queued Blade triangle retires before UI present");
        // sketch_cmd_monitor encodes the Scene-only stream contract and will
        // intentionally flag the injected CPU command.  Active-page writes,
        // however, remain a real ownership violation.
        if (err_active_write) $fatal(1, "SketchBook active-page write");
        $display("[SCENE_SK_UI_ABORT] PASS: queued Scene frame + CPU cursor patch compose correctly");
        $finish;
    end

    initial begin
        #900_000_000;
        $fatal(1, "scene-sk UI abort timeout");
    end
endmodule
