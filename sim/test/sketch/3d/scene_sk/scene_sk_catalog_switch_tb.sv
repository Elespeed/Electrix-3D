`timescale 1ns/1ps
module scene_sk_catalog_switch_tb;
`ifdef MODELSIM_BUILD
 localparam string INIT_FILE="../../../assets/3d/packages/br01/br01.s3dpkg.mif";
`else
 localparam string INIT_FILE="../../assets/3d/packages/br01/br01.s3dpkg.mif";
`endif
 logic clk=0,resetn=0,catalog_load,cmd_valid,cmd_ready,frame_start,cmd_full,busy,frame_done,error,model_valid,catalog_busy,catalog_valid,catalog_error;
 logic [3:0] model_select,selected_model,mesh_count; logic [7:0] error_code,catalog_error_code; logic [127:0] cmd_data; logic [4:0] cmd_level;
 logic [31:0] selected_model_base,selected_model_size; logic [4:0] arid,rid; logic [31:0] araddr,rdata; logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst,rresp; logic arlock; logic [3:0] arcache; logic [2:0] arprot; logic arvalid,arready,rlast,rvalid,rready;
 logic dvi_clk,dvi_hs,dvi_vs,dvi_de; logic [7:0] dvi_d; logic mon_err,ref_err; logic [31:0] clears,fills,tris,presents; integer reads,reads_after_load;
 always #10 clk=~clk; always @(posedge clk) if(arvalid&&arready) reads++;
 task automatic push(input [127:0] d); begin @(negedge clk);cmd_data=d;cmd_valid=1;while(!cmd_ready)@(posedge clk);@(negedge clk);cmd_valid=0;end endtask
 task automatic select_model(input [3:0] id,input [3:0] expected_meshes); begin
   @(negedge clk); model_select=id; catalog_load=1; @(negedge clk); catalog_load=0; wait(catalog_busy); wait(!catalog_busy);
   if(catalog_error || !catalog_valid || selected_model!=id || mesh_count!=expected_meshes) $fatal(1,"catalog select id=%0d valid=%b err=%b mesh=%0d",id,catalog_valid,catalog_error,mesh_count);
   $display("[SCENE_CATALOG] loaded id=%0d meshes=%0d base=%h size=%0d", id, mesh_count, selected_model_base, selected_model_size);
   reads_after_load=reads;
 end endtask
 function automatic [127:0] draw(input [3:0] mesh,input signed [15:0] x,input signed [15:0] y,input [3:0] pitch); begin draw='0;draw[3:0]=2;draw[11:8]=mesh;draw[31:16]=x;draw[47:32]=y;draw[71:68]=pitch;draw[95:80]=16'h0100;end endfunction
 task automatic finish_frame; begin push({124'd0,4'd3});@(negedge clk);frame_start=1;@(negedge clk);frame_start=0;wait(frame_done);wait(!busy);if(error)$fatal(1,"scene error %0d",error_code);if(reads!=reads_after_load)$fatal(1,"model reread after cache valid");$display("[SCENE_CATALOG] frame complete");end endtask
 initial begin catalog_load=0;model_select=0;cmd_valid=0;cmd_data=0;frame_start=0;reads=0;#200 resetn=1;
   // The current S3PK header is 32 bytes larger than the legacy package.
   select_model(0,1); if(selected_model_base!=32'h0040_0070||selected_model_size!=760)$fatal(1,"blade descriptor base=%h size=%0d",selected_model_base,selected_model_size); push({24'd0,8'h1c,96'd1});push(draw(0,0,0,0));finish_frame();
   // Entry 1 is the V2 rigid robot.  This catalog top accepts SK3D V4, so
   // select entry 2: the five-mesh V4 robot used by this command-mode test.
   select_model(2,5); if(selected_model_base!=32'h0040_0A60||selected_model_size!=1856)$fatal(1,"robot descriptor base=%h size=%0d",selected_model_base,selected_model_size); push({24'd0,8'h1c,96'd1});push(draw(0,-11,-25,0));push(draw(1,11,-25,0));push(draw(2,-18,11,0));push(draw(3,18,11,0));push(draw(4,0,31,0));finish_frame();
   if(clears!=2||presents!=2||tris==0)$fatal(1,"commands clear=%0d tri=%0d present=%0d",clears,tris,presents);wait(dvi.captured_frame_id>=3);dvi.assert_captured_region_nonblack(0,0,799,599,100,"catalog robot frame");dvi.dump_captured_frame("scene_sk_catalog_switch_tb_rendered");$display("[SCENE_CATALOG] PASS clear=%0d tri=%0d present=%0d",clears,tris,presents);#100 $finish;
 end
 scene_multimesh_catalog_top #(.PACKAGE_SIZE(32'd4512)) dut(.*,.m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arlock(arlock),.m_axi_arcache(arcache),.m_axi_arprot(arprot),.m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready));
 sketch_ext_sram_agent #(.INIT_FILE(INIT_FILE)) mem(.clk,.resetn,.s_arid(arid),.s_araddr(araddr),.s_arlen(arlen),.s_arsize(arsize),.s_arburst(arburst),.s_arlock(arlock),.s_arcache(arcache),.s_arprot(arprot),.s_arvalid(arvalid),.s_arready(arready),.s_rid(rid),.s_rdata(rdata),.s_rresp(rresp),.s_rlast(rlast),.s_rvalid(rvalid),.s_rready(rready));
 sketch_cmd_monitor cm(.clk,.resetn,.valid(dut.u_scene.sk_valid),.we(dut.u_scene.sk_we),.ready(dut.u_scene.sk_ready),.addr(dut.u_scene.sk_addr),.wdata(dut.u_scene.sk_wdata),.error(mon_err),.clear_count(clears),.fill_count(fills),.tri_count(tris),.present_count(presents));
 model_scene_ref_agent rm(.clk,.resetn,.valid(dut.u_scene.sk_valid),.we(dut.u_scene.sk_we),.ready(dut.u_scene.sk_ready),.addr(dut.u_scene.sk_addr),.wdata(dut.u_scene.sk_wdata),.error(ref_err));
 dvi_monitor_800x600 #(.FRAME_DUMP_LIMIT(0),.TESTCASE("scene_sk_catalog_switch_tb"),.OUTPUT_ROOT("../../../sim/frame_output")) dvi(.video_clk(dvi_clk),.resetn,.video_red({dvi_d[7:5],dvi_d[7:6]}),.video_green({dvi_d[4:2],dvi_d[4:2]}),.video_blue({dvi_d[1:0],dvi_d[1:0],dvi_d[1]}),.video_hsync(dvi_hs),.video_vsync(dvi_vs),.video_de(dvi_de));
 initial begin #60_000_000;$fatal(1,"catalog timeout state=%0d err=%b/%0d",dut.cstate,catalog_error,catalog_error_code);end
endmodule
