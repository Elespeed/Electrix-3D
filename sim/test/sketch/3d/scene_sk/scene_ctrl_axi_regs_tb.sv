`timescale 1ns/1ps
// T09/T11 directed AXI-MMIO boundary test.  Events are injected at the
// register boundary so the test does not depend on model-memory contents.
module scene_ctrl_axi_regs_tb;
  logic clk=0, resetn=0; always #5 clk=~clk;
  logic awvalid,awready; logic [31:0] awaddr; logic [4:0] awid; logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst; logic awlock; logic [3:0] awcache; logic [2:0] awprot;
  logic wvalid,wready; logic [31:0] wdata; logic [3:0] wstrb; logic wlast; logic bvalid,bready; logic [4:0] bid; logic [1:0] bresp;
  logic arvalid,arready; logic [31:0] araddr; logic [4:0] arid; logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst; logic arlock; logic [3:0] arcache; logic [2:0] arprot; logic rvalid,rready; logic [31:0] rdata; logic [4:0] rid; logic [1:0] rresp; logic rlast;
  logic load_start,render_start,abort,soft_reset; logic [31:0] model_base,model_size; logic [15:0] yaw,pitch,roll,scale,center_x,center_y,translate_z; logic [5:0] render_cfg; logic [7:0] clear_color; logic [15:0] viewport_x,viewport_y,viewport_w,viewport_h; logic [1:0] viewport_cfg; logic cmd_mode,cmd_push,cmd_frame_start; logic [127:0] cmd_data;
  logic busy,load_done,render_done,error,gru_backpressure,model_valid; logic [7:0] error_code; logic [15:0] vertex_count,triangle_count; logic [31:0] perf_load_bytes,perf_load_transactions,perf_transform_cycles,perf_cull_cycles,perf_sort_cycles,perf_command_cycles,perf_input_triangles,perf_culled_triangles,perf_output_triangles; logic cmd_ready; logic [4:0] cmd_level; logic cmd_full,cmd_locked; logic [31:0] cmd_frame_count; logic [3:0] cmd_mesh_count; logic event_render_done,event_frame_done,event_error; logic irq; logic [2:0] irq_status,irq_enable;
  `define s_awvalid awvalid
  `define s_awready awready
  `define s_awaddr awaddr
  `define s_awid awid
  `define s_awlen awlen
  `define s_awsize awsize
  `define s_awburst awburst
  `define s_awlock awlock
  `define s_awcache awcache
  `define s_awprot awprot
  `define s_wvalid wvalid
  `define s_wready wready
  `define s_wdata wdata
  `define s_wstrb wstrb
  `define s_wlast wlast
  `define s_bvalid bvalid
  `define s_bready bready
  `define s_bid bid
  `define s_bresp bresp
  `define s_arvalid arvalid
  `define s_arready arready
  `define s_araddr araddr
  `define s_arid arid
  `define s_arlen arlen
  `define s_arsize arsize
  `define s_arburst arburst
  `define s_arlock arlock
  `define s_arcache arcache
  `define s_arprot arprot
  `define s_rvalid rvalid
  `define s_rready rready
  `define s_rdata rdata
  `define s_rid rid
  `define s_rresp rresp
  `define s_rlast rlast
  scene_ctrl_axi_regs dut (.clk(clk),.resetn(resetn),.s_awvalid(awvalid),.s_awready(awready),.s_awaddr(awaddr),.s_awid(awid),.s_awlen(awlen),.s_awsize(awsize),.s_awburst(awburst),.s_awlock(awlock),.s_awcache(awcache),.s_awprot(awprot),.s_wvalid(wvalid),.s_wready(wready),.s_wdata(wdata),.s_wstrb(wstrb),.s_wlast(wlast),.s_bvalid(bvalid),.s_bready(bready),.s_bid(bid),.s_bresp(bresp),.s_arvalid(arvalid),.s_arready(arready),.s_araddr(araddr),.s_arid(arid),.s_arlen(arlen),.s_arsize(arsize),.s_arburst(arburst),.s_arlock(arlock),.s_arcache(arcache),.s_arprot(arprot),.s_rvalid(rvalid),.s_rready(rready),.s_rdata(rdata),.s_rid(rid),.s_rresp(rresp),.s_rlast(rlast),.load_start(load_start),.render_start(render_start),.abort(abort),.soft_reset(soft_reset),.model_base(model_base),.model_size(model_size),.yaw(yaw),.pitch(pitch),.roll(roll),.scale(scale),.center_x(center_x),.center_y(center_y),.translate_z(translate_z),.render_cfg(render_cfg),.clear_color(clear_color),.viewport_x(viewport_x),.viewport_y(viewport_y),.viewport_w(viewport_w),.viewport_h(viewport_h),.viewport_cfg(viewport_cfg),.cmd_mode(cmd_mode),.cmd_push(cmd_push),.cmd_data(cmd_data),.cmd_frame_start(cmd_frame_start),.busy(busy),.load_done(load_done),.render_done(render_done),.error(error),.gru_backpressure(gru_backpressure),.model_valid(model_valid),.error_code(error_code),.vertex_count(vertex_count),.triangle_count(triangle_count),.perf_load_bytes(perf_load_bytes),.perf_load_transactions(perf_load_transactions),.perf_transform_cycles(perf_transform_cycles),.perf_cull_cycles(perf_cull_cycles),.perf_sort_cycles(perf_sort_cycles),.perf_command_cycles(perf_command_cycles),.perf_input_triangles(perf_input_triangles),.perf_culled_triangles(perf_culled_triangles),.perf_output_triangles(perf_output_triangles),.cmd_ready(cmd_ready),.cmd_level(cmd_level),.cmd_full(cmd_full),.cmd_locked(cmd_locked),.cmd_frame_count(cmd_frame_count),.cmd_mesh_count(cmd_mesh_count),.event_render_done(event_render_done),.event_frame_done(event_frame_done),.event_error(event_error),.irq(irq),.irq_status(irq_status),.irq_enable(irq_enable));

  task automatic wr(input [11:0] a,input [31:0] d);
    begin @(negedge clk); awaddr={20'b0,a}; awvalid=1; @(posedge clk); while(!awready) @(posedge clk); @(negedge clk); awvalid=0; wdata=d; wvalid=1; @(posedge clk); while(!wready) @(posedge clk); @(negedge clk); wvalid=0; while(!bvalid) @(posedge clk); @(negedge clk); bready=1; @(posedge clk); @(negedge clk); bready=0; end
  endtask
  task automatic rd(input [11:0] a,output [31:0] d);
    begin @(negedge clk); araddr={20'b0,a}; arvalid=1; @(posedge clk); while(!arready) @(posedge clk); @(negedge clk); arvalid=0; while(!rvalid) @(posedge clk); d=rdata; @(negedge clk); rready=1; @(posedge clk); @(negedge clk); rready=0; end
  endtask
  reg [31:0] q;
  initial begin
    awvalid=0; awaddr=0; awid=0; awlen=0; awsize=3'd2; awburst=2'b01; awlock=0; awcache=0; awprot=0; wvalid=0; wdata=0; wstrb=4'hf; wlast=1; bready=0; arvalid=0; araddr=0; arid=0; arlen=0; arsize=3'd2; arburst=2'b01; arlock=0; arcache=0; arprot=0; rready=0; busy=0; load_done=0; render_done=0; error=0; gru_backpressure=0; model_valid=0; error_code=0; vertex_count=0; triangle_count=0; cmd_ready=1; cmd_level=0; cmd_full=0; cmd_locked=0; cmd_frame_count=0; cmd_mesh_count=0; event_render_done=0; event_frame_done=0; event_error=0; perf_load_bytes=32'd64; perf_load_transactions=32'd4; perf_transform_cycles=32'd17; perf_cull_cycles=32'd9; perf_sort_cycles=32'd5; perf_command_cycles=32'd3; perf_input_triangles=32'd8; perf_culled_triangles=32'd2; perf_output_triangles=32'd6;
    repeat(2) @(posedge clk); resetn=1;
    wr(12'h058,32'h7); // enable all three interrupt causes
    event_render_done=1; event_frame_done=1; @(posedge clk); @(negedge clk); event_render_done=0; event_frame_done=0; @(posedge clk);
    // No polling occurred between event and this read: both causes persist.
    rd(12'h05c,q); if(q[2:0]!==3'b011 || !irq) $fatal(1,"sticky IRQ lost status=%h irq=%b",q,irq);
    event_error=1; @(posedge clk); @(negedge clk); event_error=0; @(posedge clk); rd(12'h05c,q); if(q[2:0]!==3'b111) $fatal(1,"error event lost status=%h",q);
    wr(12'h060,32'h3); rd(12'h05c,q); if(q[2:0]!==3'b100 || irq!==1'b1) $fatal(1,"W1C/IRQ mask failed status=%h irq=%b",q,irq);
    wr(12'h060,32'h4); rd(12'h05c,q); if(q[2:0]!==3'b000 || irq!==1'b0) $fatal(1,"final W1C failed status=%h irq=%b",q,irq);
    // T11: every performance register is read-only and carries a non-zero
    // value supplied by the completed scene pipeline.  A write attempt must
    // not alter the sampled counters.
    wr(12'h064,32'hdead_beef); wr(12'h06c,32'hdead_beef);
    rd(12'h064,q); if(q!==64 || q===0) $fatal(1,"LOAD bytes readback invalid %h",q);
    rd(12'h068,q); if(q!==4 || q===0) $fatal(1,"LOAD transactions readback invalid %h",q);
    rd(12'h06c,q); if(q!==17 || q===0) $fatal(1,"transform cycles readback invalid %h",q);
    rd(12'h070,q); if(q!==9 || q===0) $fatal(1,"cull cycles readback invalid %h",q);
    rd(12'h074,q); if(q!==5 || q===0) $fatal(1,"sort cycles readback invalid %h",q);
    rd(12'h078,q); if(q!==3 || q===0) $fatal(1,"command cycles readback invalid %h",q);
    rd(12'h07c,q); if(q!==8 || q===0) $fatal(1,"input triangles readback invalid %h",q);
    rd(12'h080,q); if(q!==2 || q===0) $fatal(1,"culled triangles readback invalid %h",q);
    rd(12'h084,q); if(q!==6 || q===0) $fatal(1,"output triangles readback invalid %h",q);
    $display("[SCENE_AXI_REGS] PASS sticky_irq w1c perf_readback"); #10 $finish;
  end
endmodule
