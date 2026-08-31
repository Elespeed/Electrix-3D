// Standalone multi-mesh Scene system.  It deliberately has no AXI slave: the
// testbench feeds a small synchronous command port, while a later SoC adapter
// can translate MMIO staging registers to exactly this interface.
module scene_multimesh_cmd_top #(
    parameter logic [31:0] MODEL_BASE = 32'h0040_0000,
    parameter int MAX_VERTICES = 128, parameter int MAX_TRIANGLES = 192
) (
    input logic clk, input logic resetn,
    input logic load_start, input logic [31:0] model_base, input logic [31:0] model_size,
    input logic cmd_valid, input logic [127:0] cmd_data, output logic cmd_ready,
    input logic frame_start, output logic [4:0] cmd_level, output logic cmd_full,
    output logic busy, output logic frame_done, output logic error, output logic [7:0] error_code,
    output logic model_valid, output logic [3:0] mesh_count,
    output logic [4:0] m_axi_arid, output logic [31:0] m_axi_araddr, output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize, output logic [1:0] m_axi_arburst, output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache, output logic [2:0] m_axi_arprot, output logic m_axi_arvalid,
    input logic m_axi_arready, input logic [4:0] m_axi_rid, input logic [31:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp, input logic m_axi_rlast, input logic m_axi_rvalid, output logic m_axi_rready,
    output logic dvi_clk, output logic dvi_hs, output logic dvi_vs, output logic dvi_de, output logic [7:0] dvi_d
);
    localparam [3:0] CMD_CLEAR = 4'd1, CMD_DRAW = 4'd2, CMD_PRESENT = 4'd3;
    typedef enum logic [2:0] {Q_IDLE,Q_DISPATCH,Q_DRAW_WAIT,Q_MMIO,Q_PRESENT_WAIT,Q_FAIL} qstate_t;
    qstate_t qstate;
    logic fifo_locked, fifo_empty, fifo_pop, fifo_complete, fifo_error;
    logic [127:0] fifo_head;
    logic e_busy, e_error, e_load_done, e_render_done, e_draw_done;
    logic [7:0] e_error_code; logic [31:0] e_frame_count;
    logic [15:0] e_vcount, e_tcount;
    logic e_mmio_valid,e_mmio_we,e_mmio_ready; logic [31:0] e_mmio_addr,e_mmio_wdata,e_mmio_rdata;
    logic f_mmio_valid,f_mmio_we,f_mmio_ready; logic [31:0] f_mmio_addr,f_mmio_wdata,f_mmio_rdata;
    logic cmd_draw_start; logic [3:0] cmd_mesh_id,cmd_yaw,cmd_pitch,cmd_roll; logic signed [15:0] cmd_tx,cmd_ty,cmd_tz; logic [15:0] cmd_scale;
    logic [2:0] mmio_phase; logic [31:0] mmio_w0; logic present_pending;

    scene_cmd_fifo #(.DEPTH(16),.WIDTH(128)) u_fifo(
        .clk,.resetn,.push_valid(cmd_valid),.push_data(cmd_data),.push_ready(cmd_ready),.level(cmd_level),.full(cmd_full),.locked(fifo_locked),
        .frame_start,.frame_complete(fifo_complete),.frame_error(fifo_error),.pop(fifo_pop),.head(fifo_head),.empty(fifo_empty));

    scene_ctrl_engine #(.MAX_VERTICES(MAX_VERTICES),.MAX_TRIANGLES(MAX_TRIANGLES),.MODEL_BASE(MODEL_BASE),.SCENE_CONTROLLED(1'b1)) u_engine(
        .clk,.resetn,.start(1'b0),.scene_load_start(load_start),.scene_render_start(1'b0),.scene_abort(1'b0),
        .cmd_mode(1'b1),.cmd_draw_start,.cmd_mesh_id,.cmd_translate_x(cmd_tx),.cmd_translate_y(cmd_ty),.cmd_translate_z(cmd_tz),.cmd_yaw,.cmd_pitch,.cmd_roll,.cmd_scale,.cmd_draw_done(e_draw_done),.cmd_mesh_count(mesh_count),
        .scene_model_base(model_base),.scene_model_size(model_size),.scene_animation_enable(1'b0),
        .scene_yaw(16'd0),.scene_pitch(16'd0),.scene_roll(16'd0),.scene_scale(16'h0100),.scene_center_x(16'd200),.scene_center_y(16'd150),.scene_translate_z(16'd0),
        .scene_clear_before(1'b0),.scene_auto_present(1'b0),.scene_backface_cull(1'b1),.scene_depth_sort(1'b1),.scene_keep_current_frame(1'b1),.scene_clear_color(8'h00),
        .scene_viewport_enable(1'b0),.scene_viewport_local_clear(1'b0),.scene_viewport_x(16'd0),.scene_viewport_y(16'd0),.scene_viewport_w(16'd0),.scene_viewport_h(16'd0),
        .busy(e_busy),.error(e_error),.error_code(e_error_code),.frame_count(e_frame_count),.cache_valid(model_valid),.load_done(e_load_done),.render_done(e_render_done),.model_vertex_count(e_vcount),.model_triangle_count(e_tcount),
        .mmio_valid(e_mmio_valid),.mmio_we(e_mmio_we),.mmio_addr(e_mmio_addr),.mmio_wdata(e_mmio_wdata),.mmio_rdata(e_mmio_rdata),.mmio_ready(e_mmio_ready),
        .m_axi_arid,.m_axi_araddr,.m_axi_arlen,.m_axi_arsize,.m_axi_arburst,.m_axi_arlock,.m_axi_arcache,.m_axi_arprot,.m_axi_arvalid,.m_axi_arready,.m_axi_rid,.m_axi_rdata,.m_axi_rresp,.m_axi_rlast,.m_axi_rvalid,.m_axi_rready);

    // The front end and engine never issue SketchBook commands concurrently:
    // CLEAR/PRESENT are emitted only between complete DRAW executions.
    always_comb begin
        f_mmio_valid = (qstate == Q_MMIO) || (qstate == Q_PRESENT_WAIT);
        f_mmio_we = (qstate == Q_MMIO);
        f_mmio_addr = (qstate == Q_PRESENT_WAIT) ? 32'h4 : ((mmio_phase == 0) ? 32'h8 : (mmio_phase == 1) ? 32'hc : (mmio_phase == 2) ? 32'h10 : (mmio_phase == 3) ? 32'h14 : 32'h18);
        f_mmio_wdata = (mmio_phase == 0) ? mmio_w0 : (mmio_phase == 4 ? 32'd1 : 32'd0);
    end
    wire use_front = f_mmio_valid;
    wire sk_valid = use_front ? f_mmio_valid : e_mmio_valid;
    wire sk_we = use_front ? f_mmio_we : e_mmio_we;
    wire [31:0] sk_addr = use_front ? f_mmio_addr : e_mmio_addr;
    wire [31:0] sk_wdata = use_front ? f_mmio_wdata : e_mmio_wdata;
    assign f_mmio_ready = use_front && sk_ready;
    // e_mmio_ready cannot self-reference; only grant it when the front end is idle.
    wire engine_ready = !use_front && sk_ready;
    assign e_mmio_ready = engine_ready;
    wire [31:0] sk_rdata;
    assign e_mmio_rdata = sk_rdata;
    assign f_mmio_rdata = sk_rdata;
    logic sk_ready;
    logic sk_irq,sk_err;
    sketch_book_top u_sketch(.clk,.resetn,.mmio_valid(sk_valid),.mmio_we(sk_we),.mmio_addr(sk_addr),.mmio_wdata(sk_wdata),.mmio_rdata(sk_rdata),.mmio_ready(sk_ready),.dvi_clk,.dvi_hs,.dvi_vs,.dvi_de,.dvi_d,.irq_done(sk_irq),.err_active_write(sk_err));

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin qstate<=Q_IDLE; fifo_pop<=0; fifo_complete<=0; fifo_error<=0; frame_done<=0; error<=0; error_code<=0; cmd_draw_start<=0; mmio_phase<=0; mmio_w0<=0; present_pending<=0; cmd_mesh_id<=0; cmd_tx<=0; cmd_ty<=0; cmd_tz<=0; cmd_yaw<=0; cmd_pitch<=0; cmd_roll<=0; cmd_scale<=16'h0100; end
        else begin
            fifo_pop<=0; fifo_complete<=0; fifo_error<=0; frame_done<=0; cmd_draw_start<=0;
            if (e_error && qstate != Q_IDLE) begin error<=1; error_code<=e_error_code; fifo_error<=1; qstate<=Q_FAIL; end
            else case(qstate)
                // fifo_complete clears the FIFO in scene_cmd_fifo on this
                // edge.  Do not re-enter dispatch from the stale pre-clear
                // locked value on the following cycle, or an empty FIFO is
                // incorrectly treated as a new frame.
                Q_IDLE: if (fifo_locked && model_valid && !fifo_complete) qstate<=Q_DISPATCH;
                Q_DISPATCH: if (fifo_empty) begin error<=1; error_code<=8'd10; fifo_error<=1; qstate<=Q_FAIL; end
                    else case(fifo_head[3:0])
                        CMD_CLEAR: begin fifo_pop<=1; mmio_w0<={19'd0,fifo_head[103:96],5'd0}; mmio_phase<=0; qstate<=Q_MMIO; end
                        CMD_DRAW: begin fifo_pop<=1; cmd_mesh_id<=fifo_head[11:8]; cmd_tx<=fifo_head[31:16]; cmd_ty<=fifo_head[47:32]; cmd_tz<=fifo_head[63:48]; cmd_yaw<=fifo_head[67:64]; cmd_pitch<=fifo_head[71:68]; cmd_roll<=fifo_head[75:72]; cmd_scale<=fifo_head[95:80]; cmd_draw_start<=1; qstate<=Q_DRAW_WAIT; end
                        CMD_PRESENT: begin fifo_pop<=1; mmio_w0<={27'd0,5'd6}; mmio_phase<=0; present_pending<=1; qstate<=Q_MMIO; end
                        default: begin error<=1; error_code<=8'd9; fifo_error<=1; qstate<=Q_FAIL; end
                    endcase
                Q_DRAW_WAIT: if (e_draw_done) qstate<=Q_DISPATCH;
                Q_MMIO: if (f_mmio_ready) begin if (mmio_phase==4) begin if (present_pending) begin present_pending<=0; qstate<=Q_PRESENT_WAIT; end else qstate<=Q_DISPATCH; end else mmio_phase<=mmio_phase+1'b1; end
                Q_PRESENT_WAIT: if (f_mmio_ready && f_mmio_rdata[5]) begin fifo_complete<=1; frame_done<=1; qstate<=Q_IDLE; end
                default: qstate<=Q_FAIL;
            endcase
        end
    end
    assign busy = e_busy || fifo_locked || (qstate != Q_IDLE);
endmodule
