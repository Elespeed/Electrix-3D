// Scene-controller integration.  The CPU-visible register boundary and the
// pipeline are separate compilation units; legacy SketchBook demos retain
// their own model_scene_core instance and are not affected by this subsystem.
module scene_ctrl_top #(
 parameter int MAX_VERTICES=128, parameter int MAX_TRIANGLES=192, parameter logic [31:0] MODEL_BASE=32'h0040_0000
) (
 input logic clk,input logic resetn,
 input logic s_awvalid,output logic s_awready,input logic [31:0] s_awaddr,input logic [4:0] s_awid,input logic [7:0] s_awlen,input logic [2:0] s_awsize,input logic [1:0] s_awburst,input logic s_awlock,input logic [3:0] s_awcache,input logic [2:0] s_awprot,input logic s_wvalid,output logic s_wready,input logic [31:0] s_wdata,input logic [3:0] s_wstrb,input logic s_wlast,output logic s_bvalid,input logic s_bready,output logic [4:0] s_bid,output logic [1:0] s_bresp,input logic s_arvalid,output logic s_arready,input logic [31:0] s_araddr,input logic [4:0] s_arid,input logic [7:0] s_arlen,input logic [2:0] s_arsize,input logic [1:0] s_arburst,input logic s_arlock,input logic [3:0] s_arcache,input logic [2:0] s_arprot,output logic s_rvalid,input logic s_rready,output logic [31:0] s_rdata,output logic [4:0] s_rid,output logic [1:0] s_rresp,output logic s_rlast,
 output logic mmio_valid,output logic mmio_we,output logic [31:0] mmio_addr,output logic [31:0] mmio_wdata,input logic [31:0] mmio_rdata,input logic mmio_ready,
 output logic [4:0] m_axi_arid,output logic [31:0] m_axi_araddr,output logic [7:0] m_axi_arlen,output logic [2:0] m_axi_arsize,output logic [1:0] m_axi_arburst,output logic m_axi_arlock,output logic [3:0] m_axi_arcache,output logic [2:0] m_axi_arprot,output logic m_axi_arvalid,input logic m_axi_arready,input logic [4:0] m_axi_rid,input logic [31:0] m_axi_rdata,input logic [1:0] m_axi_rresp,input logic m_axi_rlast,input logic m_axi_rvalid,output logic m_axi_rready
 ,output logic irq
);
 logic load_start,render_start,abort,soft_reset,busy,error,cmd_mode,cmd_push,cmd_frame_start,cmd_ready,cmd_full,cmd_locked; logic [31:0] frame_count,base,size,cmd_frame_count; logic [127:0] cmd_data; logic [4:0] cmd_level; logic [3:0] cmd_mesh_count; logic [15:0] yaw,pitch,roll,scale,cx,cy,tz,vp_x,vp_y,vp_w,vp_h; logic [5:0] cfg; logic [7:0] clear; logic [1:0] vp_cfg;
 logic model_valid, load_done, render_done, frame_done; logic [15:0] model_vertex_count,model_triangle_count; logic [7:0] error_code; logic pipeline_resetn;
 logic [31:0] perf_load_bytes, perf_load_transactions, perf_transform_cycles, perf_cull_cycles, perf_sort_cycles, perf_command_cycles;
 logic [31:0] perf_input_triangles, perf_culled_triangles, perf_output_triangles;
 logic [2:0] irq_status, irq_enable; logic error_d;
 wire event_error = error && !error_d;
 assign pipeline_resetn = resetn & ~soft_reset;
 // LOAD fills the Scene-owned cache only.  Once MODEL_VALID is set, RENDER
 // starts a frame using that cache without another ExtRAM transaction.
 // Report only a stalled Scene command.  A low ready while the CPU owns the
 // shared SketchBook port is not Scene/GRU backpressure.
 scene_ctrl_axi_regs u_regs(.*,.model_base(base),.model_size(size),.yaw,.pitch,.roll,.scale,.center_x(cx),.center_y(cy),.translate_z(tz),.render_cfg(cfg),.clear_color(clear),.viewport_x(vp_x),.viewport_y(vp_y),.viewport_w(vp_w),.viewport_h(vp_h),.viewport_cfg(vp_cfg),.cmd_mode,.cmd_push,.cmd_data,.cmd_frame_start,.busy,.load_done,.render_done,.error,.gru_backpressure(mmio_valid && ~mmio_ready),.model_valid,.error_code,.vertex_count(model_vertex_count),.triangle_count(model_triangle_count),.cmd_ready,.cmd_level,.cmd_full,.cmd_locked,.cmd_frame_count,.cmd_mesh_count,.event_render_done(render_done),.event_frame_done(frame_done),.event_error,.irq,.irq_status,.irq_enable);
 scene_ctrl_pipeline #(.MAX_VERTICES(MAX_VERTICES),.MAX_TRIANGLES(MAX_TRIANGLES),.MODEL_BASE(MODEL_BASE)) u_pipeline(.*,.resetn(pipeline_resetn),.start(1'b0),.load_start,.render_start,.abort,.model_base(base),.model_size(size),.animation_enable(cfg[4]),.yaw,.pitch,.roll,.scale,.center_x(cx),.center_y(cy),.translate_z(tz),.clear_before(cfg[0]),.auto_present(cfg[1]),.backface_cull(cfg[2]),.depth_sort(cfg[3]),.keep_current_frame(cfg[5]),.clear_color(clear),.viewport_enable(vp_cfg[0]),.viewport_local_clear(vp_cfg[1]),.viewport_x(vp_x),.viewport_y(vp_y),.viewport_w(vp_w),.viewport_h(vp_h),.cmd_mode,.cmd_push,.cmd_data,.cmd_frame_start,.cmd_ready,.cmd_level,.cmd_full,.cmd_locked,.cmd_frame_count,.cmd_mesh_count,.frame_count,.busy,.error,.error_code,.cache_valid(model_valid),.load_done,.render_done,.frame_done,.model_vertex_count,.model_triangle_count,.perf_load_bytes,.perf_load_transactions,.perf_transform_cycles,.perf_cull_cycles,.perf_sort_cycles,.perf_command_cycles,.perf_input_triangles,.perf_culled_triangles,.perf_output_triangles);
 always_ff @(posedge clk or negedge resetn) begin
   if (!resetn) error_d <= 1'b0;
   else error_d <= error;
 end
endmodule
