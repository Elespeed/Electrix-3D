`timescale 1ns/1ps

// Scene-owned pipeline compilation unit.  The implementation is deliberately
// kept separate from the legacy SketchBook demo hierarchy.  The Scene engine
// now lives entirely under rtl/ip/scene_ctrl; legacy demos retain their own
// model_scene_core compatibility wrapper.
module scene_ctrl_pipeline #(
    parameter int MAX_VERTICES = 128,
    parameter int MAX_TRIANGLES = 192,
    parameter logic [31:0] MODEL_BASE = 32'h0040_0000
) (
    input logic clk, input logic resetn, input logic start,
    input logic load_start, input logic render_start, input logic abort,
    input logic [31:0] model_base, input logic [31:0] model_size, input logic animation_enable,
    input logic [15:0] yaw, input logic [15:0] pitch, input logic [15:0] roll, input logic [15:0] scale, input logic [15:0] center_x, input logic [15:0] center_y, input logic [15:0] translate_z,
    input logic clear_before, input logic auto_present, input logic backface_cull, input logic depth_sort, input logic keep_current_frame, input logic [7:0] clear_color,
    input logic viewport_enable, input logic viewport_local_clear, input logic [15:0] viewport_x, input logic [15:0] viewport_y, input logic [15:0] viewport_w, input logic [15:0] viewport_h,
    input logic cmd_mode, input logic cmd_push, input logic [127:0] cmd_data, input logic cmd_frame_start,
    output logic cmd_ready, output logic [4:0] cmd_level, output logic cmd_full, output logic cmd_locked,
    output logic [31:0] cmd_frame_count, output logic [3:0] cmd_mesh_count,
    output logic busy, output logic error, output logic [31:0] frame_count,
    output logic [7:0] error_code,
    output logic cache_valid, output logic load_done, output logic render_done,
    output logic [15:0] model_vertex_count, output logic [15:0] model_triangle_count,
    output logic mmio_valid, output logic mmio_we, output logic [31:0] mmio_addr,
    output logic [31:0] mmio_wdata, input logic [31:0] mmio_rdata, input logic mmio_ready,
    output logic [4:0] m_axi_arid, output logic [31:0] m_axi_araddr, output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize, output logic [1:0] m_axi_arburst, output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache, output logic [2:0] m_axi_arprot, output logic m_axi_arvalid,
    input logic m_axi_arready, input logic [4:0] m_axi_rid, input logic [31:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp, input logic m_axi_rlast, input logic m_axi_rvalid, output logic m_axi_rready
);
    localparam [3:0] CMD_CLEAR = 4'd1, CMD_DRAW = 4'd2, CMD_PRESENT = 4'd3;
    typedef enum logic [2:0] {Q_IDLE,Q_DISPATCH,Q_DRAW_WAIT,Q_MMIO,Q_PRESENT_CLEAR,Q_PRESENT_WAIT,Q_FAIL} qstate_t;
    qstate_t qstate;
    logic fifo_empty, fifo_pop, fifo_complete, fifo_error;
    logic [127:0] fifo_head;
    logic engine_busy, engine_error, engine_load_done, engine_render_done, cmd_draw_done;
    logic [7:0] engine_error_code;
    logic engine_mmio_valid, engine_mmio_we, engine_mmio_ready;
    logic [31:0] engine_mmio_addr, engine_mmio_wdata, engine_mmio_rdata;
    logic front_mmio_valid, front_mmio_we, front_mmio_ready;
    logic [31:0] front_mmio_addr, front_mmio_wdata, front_mmio_rdata;
    logic [2:0] mmio_phase; logic [31:0] mmio_w0; logic present_pending;
    logic cmd_draw_start; logic [3:0] cmd_mesh_id,cmd_yaw,cmd_pitch,cmd_roll;
    logic signed [15:0] cmd_tx,cmd_ty,cmd_tz; logic [15:0] cmd_scale;
    logic front_error; logic [7:0] front_error_code;

    scene_cmd_fifo #(.DEPTH(16), .WIDTH(128)) u_cmd_fifo (
        .clk, .resetn, .push_valid(cmd_push && cmd_mode), .push_data(cmd_data), .push_ready(cmd_ready),
        .level(cmd_level), .full(cmd_full), .locked(cmd_locked), .frame_start(cmd_frame_start && cmd_mode),
        .frame_complete(fifo_complete), .frame_error(fifo_error), .pop(fifo_pop), .head(fifo_head), .empty(fifo_empty));

    always_comb begin
        front_mmio_valid = (qstate == Q_MMIO) || (qstate == Q_PRESENT_CLEAR) || (qstate == Q_PRESENT_WAIT);
        front_mmio_we = (qstate == Q_MMIO) || (qstate == Q_PRESENT_CLEAR);
        front_mmio_addr = (qstate == Q_PRESENT_CLEAR || qstate == Q_PRESENT_WAIT) ? 32'h4 :
                          ((mmio_phase == 0) ? 32'h8 : (mmio_phase == 1) ? 32'hc :
                           (mmio_phase == 2) ? 32'h10 : (mmio_phase == 3) ? 32'h14 : 32'h18);
        front_mmio_wdata = (qstate == Q_PRESENT_CLEAR) ? 32'h20 :
                           ((mmio_phase == 0) ? mmio_w0 : (mmio_phase == 4 ? 32'd1 : 32'd0));
    end
    assign mmio_valid = front_mmio_valid ? front_mmio_valid : engine_mmio_valid;
    assign mmio_we = front_mmio_valid ? front_mmio_we : engine_mmio_we;
    assign mmio_addr = front_mmio_valid ? front_mmio_addr : engine_mmio_addr;
    assign mmio_wdata = front_mmio_valid ? front_mmio_wdata : engine_mmio_wdata;
    assign front_mmio_ready = front_mmio_valid && mmio_ready;
    assign engine_mmio_ready = !front_mmio_valid && mmio_ready;
    assign engine_mmio_rdata = mmio_rdata;
    assign front_mmio_rdata = mmio_rdata;
    assign busy = engine_busy || cmd_locked || (qstate != Q_IDLE);
    assign error = engine_error || front_error;
    assign error_code = engine_error ? engine_error_code : front_error_code;
    assign load_done = engine_load_done;
    assign render_done = engine_render_done;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            qstate <= Q_IDLE; fifo_pop <= 0; fifo_complete <= 0; fifo_error <= 0;
            cmd_draw_start <= 0; mmio_phase <= 0; mmio_w0 <= 0; present_pending <= 0;
            cmd_mesh_id <= 0; cmd_tx <= 0; cmd_ty <= 0; cmd_tz <= 0; cmd_yaw <= 0; cmd_pitch <= 0; cmd_roll <= 0; cmd_scale <= 16'h0100;
            front_error <= 0; front_error_code <= 0; cmd_frame_count <= 0;
        end else begin
            fifo_pop <= 0; fifo_complete <= 0; fifo_error <= 0; cmd_draw_start <= 0;
            if (!cmd_mode && qstate != Q_IDLE) begin fifo_error <= 1; qstate <= Q_IDLE; end
            else if (engine_error && qstate != Q_IDLE) begin front_error <= 1; front_error_code <= engine_error_code; fifo_error <= 1; qstate <= Q_FAIL; end
            else case (qstate)
                Q_IDLE: if (cmd_mode && cmd_locked && cache_valid && !fifo_complete) qstate <= Q_DISPATCH;
                Q_DISPATCH: if (fifo_empty) begin front_error <= 1; front_error_code <= 8'd10; fifo_error <= 1; qstate <= Q_FAIL; end
                    else case (fifo_head[3:0])
                        CMD_CLEAR: begin fifo_pop <= 1; mmio_w0 <= {19'd0,fifo_head[103:96],5'd0}; mmio_phase <= 0; qstate <= Q_MMIO; end
                        CMD_DRAW: begin fifo_pop <= 1; cmd_mesh_id <= fifo_head[11:8]; cmd_tx <= fifo_head[31:16]; cmd_ty <= fifo_head[47:32]; cmd_tz <= fifo_head[63:48]; cmd_yaw <= fifo_head[67:64]; cmd_pitch <= fifo_head[71:68]; cmd_roll <= fifo_head[75:72]; cmd_scale <= fifo_head[95:80]; cmd_draw_start <= 1; qstate <= Q_DRAW_WAIT; end
                        CMD_PRESENT: begin fifo_pop <= 1; mmio_w0 <= {27'd0,5'd6}; mmio_phase <= 0; present_pending <= 1; qstate <= Q_MMIO; end
                        default: begin front_error <= 1; front_error_code <= 8'd9; fifo_error <= 1; qstate <= Q_FAIL; end
                    endcase
                Q_DRAW_WAIT: if (cmd_draw_done) qstate <= Q_DISPATCH;
                Q_MMIO: if (front_mmio_ready) begin if (mmio_phase == 4) begin if (present_pending) begin present_pending <= 0; qstate <= Q_PRESENT_CLEAR; end else qstate <= Q_DISPATCH; end else mmio_phase <= mmio_phase + 1'b1; end
                // frame_done_sticky is sticky across presents.  Clear the old
                // completion before polling, otherwise frame N+1 can unlock
                // immediately on frame N's completion and write the active page.
                Q_PRESENT_CLEAR: if (front_mmio_ready) qstate <= Q_PRESENT_WAIT;
                Q_PRESENT_WAIT: if (front_mmio_ready && front_mmio_rdata[5]) begin fifo_complete <= 1; cmd_frame_count <= cmd_frame_count + 1'b1; qstate <= Q_IDLE; end
                default: qstate <= Q_FAIL;
            endcase
        end
    end

    scene_ctrl_engine #(.MAX_VERTICES(MAX_VERTICES), .MAX_TRIANGLES(MAX_TRIANGLES), .MODEL_BASE(MODEL_BASE), .SCENE_CONTROLLED(1'b1)) u_engine (
        .clk, .resetn, .start(1'b0), .scene_load_start(load_start), .scene_render_start(render_start && !cmd_mode), .scene_abort(abort),
        .cmd_mode, .cmd_draw_start, .cmd_mesh_id, .cmd_translate_x(cmd_tx), .cmd_translate_y(cmd_ty), .cmd_translate_z(cmd_tz), .cmd_yaw, .cmd_pitch, .cmd_roll, .cmd_scale, .cmd_draw_done, .cmd_mesh_count,
        .scene_model_base(model_base), .scene_model_size(model_size), .scene_animation_enable(cmd_mode ? 1'b0 : animation_enable),
        .scene_yaw(yaw), .scene_pitch(pitch), .scene_roll(roll), .scene_scale(scale), .scene_center_x(center_x), .scene_center_y(center_y), .scene_translate_z(translate_z),
        .scene_clear_before(clear_before), .scene_auto_present(cmd_mode ? 1'b0 : auto_present), .scene_backface_cull(backface_cull), .scene_depth_sort(depth_sort),
        // Command-mode DRAWs must accumulate into the same back page until the
        // explicit PRESENT, matching the standalone multimesh command path.
        .scene_keep_current_frame(cmd_mode ? 1'b1 : keep_current_frame), .scene_clear_color(clear_color),
        .scene_viewport_enable(viewport_enable), .scene_viewport_local_clear(viewport_local_clear), .scene_viewport_x(viewport_x), .scene_viewport_y(viewport_y), .scene_viewport_w(viewport_w), .scene_viewport_h(viewport_h),
        .busy(engine_busy), .error(engine_error), .error_code(engine_error_code), .frame_count, .cache_valid, .load_done(engine_load_done), .render_done(engine_render_done), .model_vertex_count, .model_triangle_count,
        .mmio_valid(engine_mmio_valid), .mmio_we(engine_mmio_we), .mmio_addr(engine_mmio_addr), .mmio_wdata(engine_mmio_wdata), .mmio_rdata(engine_mmio_rdata), .mmio_ready(engine_mmio_ready),
        .m_axi_arid, .m_axi_araddr, .m_axi_arlen, .m_axi_arsize, .m_axi_arburst, .m_axi_arlock, .m_axi_arcache, .m_axi_arprot, .m_axi_arvalid,
        .m_axi_arready, .m_axi_rid, .m_axi_rdata, .m_axi_rresp, .m_axi_rlast, .m_axi_rvalid, .m_axi_rready);
endmodule
