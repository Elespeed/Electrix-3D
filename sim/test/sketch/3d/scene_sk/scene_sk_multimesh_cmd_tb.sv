`timescale 1ns/1ps
module scene_sk_multimesh_cmd_tb;
`ifdef MODELSIM_BUILD
 localparam string INIT_FILE="../../../assets/3d/generated/robotss/v4/robotss_shade.s3d.mif";
`else
 localparam string INIT_FILE="../../assets/3d/generated/robotss/v4/robotss_shade.s3d.mif";
`endif
 logic clk=0,resetn=0; always #10 clk=~clk;
 logic load_start,cmd_valid,cmd_ready,frame_start,cmd_full,busy,frame_done,error,model_valid;
 logic [127:0] cmd_data; logic [4:0] cmd_level; logic [7:0] error_code; logic [3:0] mesh_count;
 logic [4:0] arid,rid; logic [31:0] araddr,rdata; logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst,rresp; logic arlock; logic [3:0] arcache; logic [2:0] arprot; logic arvalid,arready,rlast,rvalid,rready;
 logic dvi_clk,dvi_hs,dvi_vs,dvi_de; logic [7:0] dvi_d; logic mon_err,ref_err; logic [31:0] clears,fills,tris,presents; integer reads,reads_after_load;
 always @(posedge clk) if(arvalid&&arready) reads++;
 task automatic push(input [127:0] d); begin @(negedge clk); cmd_data=d;cmd_valid=1; while(!cmd_ready)@(posedge clk); @(negedge clk);cmd_valid=0; end endtask
 function automatic [127:0] draw(input [3:0] mesh,input signed [15:0] x,input signed [15:0] y,input [3:0] pitch); begin draw='0; draw[3:0]=2;draw[11:8]=mesh;draw[31:16]=x;draw[47:32]=y;draw[71:68]=pitch;draw[95:80]=16'h0100; end endfunction
 initial begin load_start=0;cmd_valid=0;cmd_data=0;frame_start=0;reads=0; #200 resetn=1; @(negedge clk);load_start=1;@(negedge clk);load_start=0; wait(model_valid); if(mesh_count!=5)$fatal(1,"mesh descriptor load %d",mesh_count); reads_after_load=reads;
   // Match tools/3d_gen/robotss_articulation's V4 frame 0.  V4 vertices are
   // mesh-local, so DRAW must restore the exported pivot for every mesh.
   // The offline renderer's default background is RGB332 1C (green).
   push({24'd0,8'h1c,96'd1}); // CLEAR RGB332=1C at fifo_head[103:96]
   push(draw(0,-16'sd11,-16'sd25,0)); // leg_r pivot (-10.60, -24.82, -2.32)
   push(draw(1, 16'sd11,-16'sd25,0)); // leg_l pivot ( 10.88, -24.68, -2.32)
   push(draw(2,-16'sd18, 16'sd11,0)); // arm_r pivot (-17.88,  11.06, -2.32)
   push(draw(3, 16'sd18, 16'sd11,0)); // arm_l pivot ( 17.89,  10.89, -2.32)
   push(draw(4,0,16'sd31,0));          // body  pivot ( -0.41,  30.62, 13.38)
   push({124'd0,4'd3}); @(negedge clk);frame_start=1;@(negedge clk);frame_start=0; wait(frame_done); if(error)$fatal(1,"frame error %d",error_code); if(clears!=1||presents!=1||tris==0)$fatal(1,"commands clear=%0d tri=%0d present=%0d",clears,tris,presents); if(reads!=reads_after_load)$fatal(1,"rerender reread ExtRAM");
   // PRESENT only swaps at a GDU frame boundary; the rendered page reaches the
   // front during the NEXT frame.  Wait until that frame has been displayed and
   // captured so the pixel checks exercise the actual render, not the empty
   // pre-swap page the monitor captured first.
   wait(dvi.captured_frame_id >= 2);
   dvi.assert_captured_region_nonblack(0,0,799,599,100,"full frame");
   dvi.dump_captured_frame("scene_sk_multimesh_cmd_tb_rendered");
   $display("[SCENE_MULTI] PASS meshes=%0d clear=%0d tri=%0d present=%0d frame=%0d",mesh_count,clears,tris,presents,dvi.captured_frame_id); #100 $finish;
 end
 scene_multimesh_cmd_top dut(.*,.model_base(32'h0040_0000),.model_size(32'd2048),.m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arlock(arlock),.m_axi_arcache(arcache),.m_axi_arprot(arprot),.m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready));
 sketch_ext_sram_agent #(.INIT_FILE(INIT_FILE)) mem(.clk,.resetn,.s_arid(arid),.s_araddr(araddr),.s_arlen(arlen),.s_arsize(arsize),.s_arburst(arburst),.s_arlock(arlock),.s_arcache(arcache),.s_arprot(arprot),.s_arvalid(arvalid),.s_arready(arready),.s_rid(rid),.s_rdata(rdata),.s_rresp(rresp),.s_rlast(rlast),.s_rvalid(rvalid),.s_rready(rready));
 sketch_cmd_monitor cm(.clk,.resetn,.valid(dut.sk_valid),.we(dut.sk_we),.ready(dut.sk_ready),.addr(dut.sk_addr),.wdata(dut.sk_wdata),.error(mon_err),.clear_count(clears),.fill_count(fills),.tri_count(tris),.present_count(presents));
 model_scene_ref_agent rm(.clk,.resetn,.valid(dut.sk_valid),.we(dut.sk_we),.ready(dut.sk_ready),.addr(dut.sk_addr),.wdata(dut.sk_wdata),.error(ref_err));
 dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0),.TESTCASE("scene_sk_multimesh_cmd_tb"),.OUTPUT_ROOT("../../../sim/frame_output")) dvi(.video_clk(dvi_clk),.resetn,.video_red({dvi_d[7:5],dvi_d[7:6]}),.video_green({dvi_d[4:2],dvi_d[4:2]}),.video_blue({dvi_d[1:0],dvi_d[1:0],dvi_d[1]}),.video_hsync(dvi_hs),.video_vsync(dvi_vs),.video_de(dvi_de));
 initial begin #30_000_000; $display("[SCENE_MULTI] timeout q=%0d fifo=%0d locked=%b engine=%0d model=%b err=%b/%0d engineerr=%b/%0d",dut.qstate,cmd_level,dut.fifo_locked,dut.u_engine.state,model_valid,error,error_code,dut.e_error,dut.e_error_code); $fatal(1,"scene multi timeout");end
endmodule
