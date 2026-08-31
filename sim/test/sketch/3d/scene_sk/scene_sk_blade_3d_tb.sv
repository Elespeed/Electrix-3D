`timescale 1ns/1ps
module scene_sk_blade_3d_tb;
`ifdef MODELSIM_BUILD
 localparam string INIT_FILE="../../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`else
 localparam string INIT_FILE="../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`endif
 logic clk=0,resetn=0; always #10 clk=~clk;
 logic awvalid,awready,wvalid,wready,wlast,bvalid,bready=1,arvalid,arready,rvalid,rready=1,rlast;
 logic [31:0] awaddr,wdata,araddr,rdata; logic [3:0] wstrb; logic [4:0] awid,bid,arid,rid; logic [7:0] awlen,arlen; logic [2:0] awsize,arsize; logic [1:0] awburst,arburst,bresp,rresp; logic awlock,arlock; logic [3:0] awcache,arcache; logic [2:0] awprot,arprot;
 logic [4:0] marid,mrid; logic [31:0] maraddr,mrdata; logic [7:0] marlen; logic [2:0] marsize; logic [1:0] marburst,mrresp; logic marlock; logic [3:0] marcache; logic [2:0] marprot; logic marvalid,marready,mrlast,mrvalid,mrready;
 logic dvi_clk,dvi_hs,dvi_vs,dvi_de; logic [7:0] dvi_d; logic mon_err,ref_err,sequence_done; logic [31:0] clears,fills,tris,presents; integer ext_reads, reads_before_rerender, clears_before_local;
 always @(posedge clk) if (marvalid && marready) ext_reads++;
 task automatic write_reg(input [31:0] addr,input [31:0] data); begin
   @(posedge clk); awaddr<=addr; awid<=0; awlen<=0; awsize<=3'd2; awburst<=2'b01; awlock<=0; awcache<=0; awprot<=0; awvalid<=1;
   while(!awready) @(posedge clk); @(posedge clk); awvalid<=0; wdata<=data; wstrb<=4'hf; wlast<=1; wvalid<=1;
   while(!wready) @(posedge clk); @(posedge clk); wvalid<=0; while(!bvalid) @(posedge clk); if(bresp!=0)$fatal(1,"scene write response");
 end endtask
 initial begin
   awvalid=0;wvalid=0;arvalid=0;awaddr=0;wdata=0;wstrb=0;wlast=0;sequence_done=0;ext_reads=0;
   #200 resetn=1;
   // A too-small fenced region must fail before any SketchBook command is sent.
   write_reg(32'h00c,32'd1); write_reg(32'h000,32'h2); wait(dut.u_scene.error);
   if (dut.u_scene.error_code != 8'd1 || clears != 0 || presents != 0) $fatal(1,"scene MODEL_SIZE validation");
   write_reg(32'h000,32'h10); repeat (2) @(posedge clk);
   if (dut.u_scene.error || dut.u_scene.model_valid) $fatal(1,"scene soft reset");
   // A valid load populates the cache only; it must not implicitly render.
   write_reg(32'h00c,32'd1536); write_reg(32'h024,32'h0f); write_reg(32'h000,32'h2);
   wait(dut.u_scene.model_valid);
   if (dut.u_scene.model_vertex_count == 0 || dut.u_scene.model_triangle_count == 0 || clears != 0 || presents != 0) $fatal(1,"scene load-only contract");
   write_reg(32'h000,32'h4); wait(dut.u_scene.render_done);
   reads_before_rerender = ext_reads;
   // Render from the populated model cache.  A second render must not issue
   // any ExtRAM AXI reads.
   write_reg(32'h000,32'h4); wait(!dut.u_scene.render_done); wait(dut.u_scene.render_done);
   if (ext_reads != reads_before_rerender) $fatal(1,"scene cached re-render reread ExtRAM: %0d -> %0d", reads_before_rerender, ext_reads);
   // A viewport replaces full-frame CLEAR with a panel-local FILL_RECT and
   // constrains the triangle output to that panel.
   clears_before_local = clears;
   write_reg(32'h02c,{16'd72,16'd200}); write_reg(32'h030,{16'd174,16'd168}); write_reg(32'h034,32'h3);
   write_reg(32'h01c,{16'd159,16'd284}); write_reg(32'h024,32'h0f); write_reg(32'h000,32'h4);
   wait(!dut.u_scene.render_done); wait(dut.u_scene.render_done);
   if (clears != clears_before_local || fills == 0) $fatal(1,"scene viewport clear=%0d/%0d fills=%0d", clears, clears_before_local, fills);
   sequence_done = 1;
 end
 scene_sk_top dut(.*,.s_awvalid(awvalid),.s_awready(awready),.s_awaddr(awaddr),.s_awid(awid),.s_awlen(awlen),.s_awsize(awsize),.s_awburst(awburst),.s_awlock(awlock),.s_awcache(awcache),.s_awprot(awprot),.s_wvalid(wvalid),.s_wready(wready),.s_wdata(wdata),.s_wstrb(wstrb),.s_wlast(wlast),.s_bvalid(bvalid),.s_bready(bready),.s_bid(bid),.s_bresp(bresp),.s_arvalid(arvalid),.s_arready(arready),.s_araddr(araddr),.s_arid(arid),.s_arlen(arlen),.s_arsize(arsize),.s_arburst(arburst),.s_arlock(arlock),.s_arcache(arcache),.s_arprot(arprot),.s_rvalid(rvalid),.s_rready(rready),.s_rdata(rdata),.s_rid(rid),.s_rresp(rresp),.s_rlast(rlast),.m_axi_arid(marid),.m_axi_araddr(maraddr),.m_axi_arlen(marlen),.m_axi_arsize(marsize),.m_axi_arburst(marburst),.m_axi_arlock(marlock),.m_axi_arcache(marcache),.m_axi_arprot(marprot),.m_axi_arvalid(marvalid),.m_axi_arready(marready),.m_axi_rid(mrid),.m_axi_rdata(mrdata),.m_axi_rresp(mrresp),.m_axi_rlast(mrlast),.m_axi_rvalid(mrvalid),.m_axi_rready(mrready));
 sketch_ext_sram_agent #(.INIT_FILE(INIT_FILE)) mem(.clk,.resetn,.s_arid(marid),.s_araddr(maraddr),.s_arlen(marlen),.s_arsize(marsize),.s_arburst(marburst),.s_arlock(marlock),.s_arcache(marcache),.s_arprot(marprot),.s_arvalid(marvalid),.s_arready(marready),.s_rid(mrid),.s_rdata(mrdata),.s_rresp(mrresp),.s_rlast(mrlast),.s_rvalid(mrvalid),.s_rready(mrready));
 sketch_cmd_monitor cm(.clk,.resetn,.valid(dut.mmio_valid),.we(dut.mmio_we),.ready(dut.mmio_ready),.addr(dut.mmio_addr),.wdata(dut.mmio_wdata),.error(mon_err),.clear_count(clears),.fill_count(fills),.tri_count(tris),.present_count(presents));
 model_scene_ref_agent rm(.clk,.resetn,.valid(dut.mmio_valid),.we(dut.mmio_we),.ready(dut.mmio_ready),.addr(dut.mmio_addr),.wdata(dut.mmio_wdata),.error(ref_err));
 dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0),.TESTCASE("scene_sk_blade_3d_tb"),.OUTPUT_ROOT("../../../sim/frame_output")) dvi(
   .video_clk(dvi_clk),.resetn,.video_red({dvi_d[7:5],dvi_d[7:6]}),.video_green({dvi_d[4:2],dvi_d[4:2]}),
   .video_blue({dvi_d[1:0],dvi_d[1:0],dvi_d[1]}),.video_hsync(dvi_hs),.video_vsync(dvi_vs),.video_de(dvi_de));
 initial begin wait(sequence_done); wait(presents>=2); if(mon_err||clears<2||tris==0)$fatal(1,"scene-sk mismatch clear=%0d tri=%0d present=%0d mon_err=%b",clears,tris,presents,mon_err); $display("[SCENE_SK] PASS clear=%0d tri=%0d present=%0d reads=%0d",clears,tris,presents,ext_reads); #100 $finish; end
 initial begin #900_000_000;$fatal(1,"scene-sk timeout");end
endmodule
