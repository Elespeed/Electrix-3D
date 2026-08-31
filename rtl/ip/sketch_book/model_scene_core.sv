`timescale 1ns/1ps

// Compatibility boundary for the standalone SketchBook model demos.
// Scene Controller owns the implementation in scene_ctrl_engine; retaining
// this thin wrapper preserves the public legacy module name and its testbench
// interface while keeping the two hierarchies independent.
module model_scene_core #(
    parameter int MAX_VERTICES = 128,
    parameter int MAX_TRIANGLES = 192,
    parameter int MAX_MATERIALS = 64,
    parameter int MAX_FACE_GROUPS = 192,
    parameter logic [31:0] MODEL_BASE = 32'h0040_0000,
    parameter bit SCENE_CONTROLLED = 1'b0,
    parameter logic [15:0] FRAME_W = 400,
    parameter logic [15:0] FRAME_H = 300
) (
    input logic clk, input logic resetn, input logic start,
    input logic scene_load_start, input logic scene_render_start, input logic scene_abort,
    input logic [31:0] scene_model_base, input logic [31:0] scene_model_size,
    input logic scene_animation_enable,
    input logic [15:0] scene_yaw, input logic [15:0] scene_pitch, input logic [15:0] scene_roll, input logic [15:0] scene_scale,
    input logic [15:0] scene_center_x, input logic [15:0] scene_center_y,
    input logic [15:0] scene_translate_z,
    input logic scene_clear_before, input logic scene_auto_present, input logic scene_backface_cull,
    input logic scene_depth_sort, input logic scene_keep_current_frame, input logic [7:0] scene_clear_color,
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
    // Legacy SketchBook demos do not expose Scene Controller viewport
    // registers.  Keep the wrapper interface stable while satisfying the
    // engine's Scene-Controlled-only inputs (which are ignored here).
    wire        scene_viewport_enable = 1'b0;
    wire        scene_viewport_local_clear = 1'b0;
    wire [15:0] scene_viewport_x = 16'd0;
    wire [15:0] scene_viewport_y = 16'd0;
    wire [15:0] scene_viewport_w = 16'd0;
    wire [15:0] scene_viewport_h = 16'd0;
    wire cmd_mode = 1'b0, cmd_draw_start = 1'b0;
    wire [3:0] cmd_mesh_id = '0, cmd_yaw = '0, cmd_pitch = '0, cmd_roll = '0;
    wire signed [15:0] cmd_translate_x = '0, cmd_translate_y = '0, cmd_translate_z = '0;
    wire [15:0] cmd_scale = 16'h0100;
    wire cmd_draw_done;
    wire [3:0] cmd_mesh_count;

    scene_ctrl_engine #(
        .MAX_VERTICES(MAX_VERTICES), .MAX_TRIANGLES(MAX_TRIANGLES),
        .MAX_MATERIALS(MAX_MATERIALS), .MAX_FACE_GROUPS(MAX_FACE_GROUPS),
        .MODEL_BASE(MODEL_BASE), .SCENE_CONTROLLED(SCENE_CONTROLLED),
        .FRAME_W(FRAME_W), .FRAME_H(FRAME_H)
    ) u_engine (.*);
endmodule
