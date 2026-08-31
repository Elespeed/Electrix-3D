`timescale 1ns/1ps

// Standalone integration boundary for generic SketchBook model demonstrations.
module sketch_model_demo_top #(
    parameter int MAX_VERTICES = 128,
    parameter int MAX_TRIANGLES = 192,
    parameter logic [31:0] MODEL_BASE = 32'h0040_0000
) (
    input logic clk, input logic resetn, input logic start,
    output logic busy, output logic error, output logic [31:0] frame_count,
    output logic [4:0] m_axi_arid, output logic [31:0] m_axi_araddr, output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize, output logic [1:0] m_axi_arburst, output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache, output logic [2:0] m_axi_arprot, output logic m_axi_arvalid,
    input logic m_axi_arready, input logic [4:0] m_axi_rid, input logic [31:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp, input logic m_axi_rlast, input logic m_axi_rvalid, output logic m_axi_rready,
    output logic dvi_clk, output logic dvi_hs, output logic dvi_vs, output logic dvi_de, output logic [7:0] dvi_d
);
    logic mmio_valid, mmio_we, mmio_ready;
    logic [31:0] mmio_addr, mmio_wdata, mmio_rdata;
    logic irq_done, err_active_write;
    // Legacy mode ignores these Scene-controller ports; keep explicit local
    // ties so the original standalone model-demo interface remains stable.
    logic scene_load_start, scene_render_start, scene_abort, scene_animation_enable;
    logic [31:0] scene_model_base, scene_model_size;
    logic [15:0] scene_yaw, scene_pitch, scene_roll, scene_scale, scene_center_x, scene_center_y, scene_translate_z;
    logic scene_clear_before, scene_auto_present, scene_backface_cull, scene_depth_sort, scene_keep_current_frame;
    logic [7:0] scene_clear_color, error_code;
    logic cache_valid, load_done, render_done;
    logic [15:0] model_vertex_count, model_triangle_count;

    model_scene_core #(
        .MAX_VERTICES(MAX_VERTICES),
        .MAX_TRIANGLES(MAX_TRIANGLES),
        .MODEL_BASE(MODEL_BASE)
    ) u_model(.*);

    sketch_book_top u_sketch(
        .clk, .resetn, .mmio_valid, .mmio_we, .mmio_addr, .mmio_wdata, .mmio_rdata, .mmio_ready,
        .dvi_clk, .dvi_hs, .dvi_vs, .dvi_de, .dvi_d, .irq_done, .err_active_write
    );

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
        end else if (err_active_write) $error("[model_demo] attempted active-page write");
    end
endmodule
