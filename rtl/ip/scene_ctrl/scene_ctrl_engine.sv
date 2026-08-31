`timescale 1ns/1ps

// Generic fixed-function SketchBook 3D-Lite producer.
// It loads a static mesh from ExtRAM, applies a yaw-only orthographic transform,
// performs back-face culling and painter sorting, then emits Flat Triangle commands.
//
// Current limitation: visibility is resolved only at triangle granularity with a
// painter sort on summed vertex depth. This keeps the pipeline small, but it also
// means side views can still show structural occlusion errors that a per-pixel
// Z-buffer would fix. Treat those cases as an architecture limit, not as a random
// ordering bug in the state machine.
// Scene execution engine.  Kept in the Scene IP hierarchy so Scene Controller
// no longer depends on the legacy SketchBook model core.
module scene_ctrl_engine #(
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
    // Command-mode is used only by the isolated multi-mesh subsystem.  Legacy
    // and SoC users leave it low and retain their v2/v3 contract.
    input logic cmd_mode, input logic cmd_draw_start, input logic [3:0] cmd_mesh_id,
    input logic signed [15:0] cmd_translate_x, input logic signed [15:0] cmd_translate_y,
    input logic signed [15:0] cmd_translate_z, input logic [3:0] cmd_yaw, input logic [3:0] cmd_pitch, input logic [3:0] cmd_roll, input logic [15:0] cmd_scale,
    output logic cmd_draw_done, output logic [3:0] cmd_mesh_count,
    input logic [31:0] scene_model_base, input logic [31:0] scene_model_size,
    input logic scene_animation_enable,
    input logic [15:0] scene_yaw, input logic [15:0] scene_pitch, input logic [15:0] scene_roll, input logic [15:0] scene_scale,
    input logic [15:0] scene_center_x, input logic [15:0] scene_center_y,
    input logic [15:0] scene_translate_z,
    input logic scene_clear_before, input logic scene_auto_present, input logic scene_backface_cull,
    input logic scene_depth_sort, input logic scene_keep_current_frame, input logic [7:0] scene_clear_color,
    input logic scene_viewport_enable, input logic scene_viewport_local_clear,
    input logic [15:0] scene_viewport_x, input logic [15:0] scene_viewport_y,
    input logic [15:0] scene_viewport_w, input logic [15:0] scene_viewport_h,
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
    import scene_ctrl_math_pkg::*;
    localparam [31:0] MAGIC_SK3D = 32'h534b3344;
    localparam logic [7:0] SK3D_VERSION_STATIC = 8'd2;
    localparam logic [7:0] SK3D_VERSION_DYNAMIC = 8'd3;
    localparam logic [7:0] SK3D_VERSION_MULTIMESH = 8'd4;
    localparam logic [7:0] MAX_VERTICES_U8 = MAX_VERTICES[7:0];
    localparam logic [7:0] MAX_TRIANGLES_U8 = MAX_TRIANGLES[7:0];
    localparam logic [7:0] MAX_MATERIALS_U8 = MAX_MATERIALS[7:0];
    localparam logic [7:0] MAX_FACE_GROUPS_U8 = MAX_FACE_GROUPS[7:0];
    localparam logic signed [9:0] LIGHT_X_Q8 = -10'sd89;
    localparam logic signed [9:0] LIGHT_Y_Q8 = 10'sd127;
    localparam logic signed [9:0] LIGHT_Z_Q8 = -10'sd203;
    localparam [4:0] OP_CLEAR = 0;
    localparam [4:0] OP_TRI = 5;
    localparam [4:0] OP_PRESENT = 6;
    typedef enum logic [5:0] {
        IDLE, HDR_REQ, HDR_WAIT, MESH_REQ, MESH_WAIT, VTX_REQ, VTX_WAIT, MAT_REQ, MAT_WAIT, GRP_REQ, GRP_WAIT, TRI_REQ, TRI_WAIT,
        XFORM_READ, XFORM_LAUNCH, XFORM_WAIT, SHADE_GROUP_READ, SHADE_GROUP_ROTATE, SHADE_GROUP_LIGHT, SHADE_GROUP_WRITE, BUILD_TRI_READ, BUILD_VERTEX_READ, BUILD, BUILD_CAPTURE,
        SORT_I, SORT_READ, SORT_COMPARE, SORT_WRITE_I, SORT_WRITE_J,
        CMD_SETUP, CMD_TRI_READ, CMD_WRITE, WAIT_FRAME, CLEAR_DONE, RENDER_FINISH, READY, FAIL
    } state_t;
    state_t state;

    logic rd_start, rd_busy, rd_valid, rd_error;
    logic [31:0] rd_addr, rd_data, pending_word;
    // Per-frame work buffers stay local.  Immutable SK3D data is held by the
    // separately instantiated scene_ctrl_model_cache below.
    // Replicated 1W1R transform stores keep the three triangle vertex reads
    // in BRAM.  The old asynchronous three-read array became a large FF bank
    // and placed load_index on every transformed-Y register D path.
    (* ram_style = "block" *) logic [71:0] transform_mem0 [0:MAX_VERTICES-1];
    (* ram_style = "block" *) logic [71:0] transform_mem1 [0:MAX_VERTICES-1];
    (* ram_style = "block" *) logic [71:0] transform_mem2 [0:MAX_VERTICES-1];
    logic signed [23:0] tx0, ty0, tz0, tx1, ty1, tz1, tx2, ty2, tz2;
    // The visible triangle list is a synchronous true-dual-port BRAM.  Do not
    // turn this back into separate arrays: SORT needs two arbitrary reads and
    // an in-place swap, which becomes tens of thousands of LUT muxes unless
    // the reads/writes are explicitly scheduled across multiple cycles.
    logic [129:0] tri_work_a_rdata, tri_work_b_rdata;
    logic [129:0] tri_work_a_wdata;
    logic [7:0] tri_work_a_addr, tri_work_b_addr;
    logic tri_work_a_we;
    logic [129:0] sort_i_record, sort_j_record;
    logic [7:0] vertex_count, triangle_count, hdr_index, load_index, visible_count, sort_i, sort_j, submit_index;
    logic [7:0] format_version, material_count, face_group_count;
    (* ram_style = "block" *) logic [7:0] mesh_vertex_base [0:15], mesh_vertex_count [0:15], mesh_triangle_base [0:15], mesh_triangle_count [0:15];
    logic [3:0] mesh_count, mesh_load_index;
    logic [7:0] active_vertex_base, active_vertex_count, active_triangle_base, active_triangle_count;
    wire is_multimesh = (format_version == SK3D_VERSION_MULTIMESH);
    wire [31:0] vertex_pool_base = 32'd16 + (is_multimesh ? ({28'd0,mesh_count} << 4) : 32'd0);
    logic [1:0] load_half;
    logic [3:0] yaw;
    logic [2:0] write_phase;
    logic [1:0] cmd_kind;
    logic [31:0] cw0, cw1, cw2, cw3;
    wire scene_emit_clear = scene_clear_before && !scene_keep_current_frame;
    wire scene_emit_local_clear = SCENE_CONTROLLED && scene_emit_clear && scene_viewport_enable && scene_viewport_local_clear;
    wire [31:0] active_model_base = SCENE_CONTROLLED ? scene_model_base : MODEL_BASE;
    logic [15:0] cache_v0x, cache_v0y, cache_v0z, cache_v1x, cache_v1y, cache_v1z, cache_v2x, cache_v2y, cache_v2z;
    logic [7:0] cache_i0, cache_i1, cache_i2, cache_color, cache_material, cache_group;
    logic [7:0] cache_mat_s0, cache_mat_s1, cache_mat_s2, cache_mat_s3;
    logic signed [9:0] cache_grp_nx, cache_grp_ny, cache_grp_nz;
    logic [1:0] cache_group_shade;
    logic [7:0] cache_vaddr0, cache_vaddr1, cache_vaddr2, cache_gaddr;
    wire cache_vertex_wr = state == VTX_WAIT && rd_valid && !rd_error && load_half;
    wire cache_material_wr = state == MAT_WAIT && rd_valid && !rd_error;
    wire cache_group_wr = state == GRP_WAIT && rd_valid && !rd_error;
    wire cache_triangle_wr = state == TRI_WAIT && rd_valid && !rd_error && load_half;
    always_comb begin
        cache_vaddr0 = (state == BUILD_VERTEX_READ) ? cache_i0 : load_index;
        cache_vaddr1 = (state == BUILD_VERTEX_READ) ? cache_i1 : 0;
        cache_vaddr2 = (state == BUILD_VERTEX_READ) ? cache_i2 : 0;
        cache_gaddr = (state == SHADE_GROUP_READ) ? load_index : cache_group;
    end
    scene_ctrl_model_cache #(
        .MAX_VERTICES(MAX_VERTICES), .MAX_TRIANGLES(MAX_TRIANGLES),
        .MAX_MATERIALS(MAX_MATERIALS), .MAX_FACE_GROUPS(MAX_FACE_GROUPS)
    ) u_model_cache (
        .clk,
        .vertex_wr_en(cache_vertex_wr), .vertex_wr_addr(load_index), .vertex_wr_x(pending_word[31:16]), .vertex_wr_y(pending_word[15:0]), .vertex_wr_z(rd_data[15:0]),
        .triangle_wr_en(cache_triangle_wr), .triangle_wr_addr(load_index), .triangle_wr_i0(pending_word[7:0]), .triangle_wr_i1(pending_word[15:8]), .triangle_wr_i2(pending_word[23:16]),
        .triangle_wr_color((format_version == SK3D_VERSION_DYNAMIC) ? 8'd0 : rd_data[7:0]), .triangle_wr_material((format_version == SK3D_VERSION_DYNAMIC) ? rd_data[7:0] : 8'd0), .triangle_wr_group((format_version == SK3D_VERSION_DYNAMIC) ? rd_data[15:8] : 8'd0),
        .material_wr_en(cache_material_wr), .material_wr_addr(load_index), .material_wr_s0(rd_data[7:0]), .material_wr_s1(rd_data[15:8]), .material_wr_s2(rd_data[23:16]), .material_wr_s3(rd_data[31:24]),
        .group_wr_en(cache_group_wr), .group_wr_addr(load_index), .group_wr_nx(unpack_q1_8(rd_data[9:0])), .group_wr_ny(unpack_q1_8(rd_data[19:10])), .group_wr_nz(unpack_q1_8(rd_data[29:20])),
        .group_shade_wr_en(state == SHADE_GROUP_WRITE), .group_shade_wr_addr(load_index), .group_shade_wr_data(group_shade_q),
        .vertex_rd_addr0(cache_vaddr0), .vertex_rd_addr1(cache_vaddr1), .vertex_rd_addr2(cache_vaddr2),
        .vertex_rd0_x(cache_v0x), .vertex_rd0_y(cache_v0y), .vertex_rd0_z(cache_v0z), .vertex_rd1_x(cache_v1x), .vertex_rd1_y(cache_v1y), .vertex_rd1_z(cache_v1z), .vertex_rd2_x(cache_v2x), .vertex_rd2_y(cache_v2y), .vertex_rd2_z(cache_v2z),
        .triangle_rd_addr(load_index), .triangle_rd_i0(cache_i0), .triangle_rd_i1(cache_i1), .triangle_rd_i2(cache_i2), .triangle_rd_color(cache_color), .triangle_rd_material(cache_material), .triangle_rd_group(cache_group),
        .material_rd_addr(cache_material), .material_rd_s0(cache_mat_s0), .material_rd_s1(cache_mat_s1), .material_rd_s2(cache_mat_s2), .material_rd_s3(cache_mat_s3),
        .group_rd_addr(cache_gaddr), .group_rd_nx(cache_grp_nx), .group_rd_ny(cache_grp_ny), .group_rd_nz(cache_grp_nz), .group_rd_shade(cache_group_shade));
    logic signed [25:0] scene_xform_x, scene_xform_y, scene_xform_z;
    logic scene_xform_valid;
    scene_ctrl_vertex_transform u_scene_xform(
        .clk, .resetn, .in_valid(state == XFORM_LAUNCH),
        .vx(cache_v0x), .vy(cache_v0y), .vz(cache_v0z), .yaw(yaw),
        // In command mode every DRAW carries its own complete transform.
        // Using the scene registers here silently discarded cmd_pitch/cmd_roll,
        // so multi-mesh articulation could never match its V4 reference pose.
        .pitch(cmd_mode ? cmd_pitch : (SCENE_CONTROLLED ? scene_pitch[3:0] : 4'd0)),
        .roll(cmd_mode ? cmd_roll : (SCENE_CONTROLLED ? scene_roll[3:0] : 4'd0)),
        .scale(cmd_mode ? cmd_scale : (SCENE_CONTROLLED ? scene_scale : 16'h0100)),
        .translate_x(cmd_mode ? cmd_translate_x : 16'sd0), .translate_y(cmd_mode ? cmd_translate_y : 16'sd0),
        .translate_z(cmd_mode ? cmd_translate_z : (SCENE_CONTROLLED ? $signed(scene_translate_z) : 16'sd0)),
        .out_valid(scene_xform_valid), .x(scene_xform_x), .y(scene_xform_y), .z(scene_xform_z));
    // Waveform-visible debug counters for future scene-quality triage.
    logic [7:0] dbg_visible_triangles_q, dbg_overlap_hotspot_q;
    logic signed [25:0] dbg_depth_min_q, dbg_depth_max_q;

    function automatic logic signed [9:0] unpack_q1_8(input logic [9:0] packed_value);
        unpack_q1_8 = {packed_value[9], packed_value[8:0]};
    endfunction

    function automatic logic [7:0] shade_lookup(input logic [1:0] shade_level);
        begin
            case (shade_level)
                2'd0: shade_lookup = cache_mat_s0;
                2'd1: shade_lookup = cache_mat_s1;
                2'd2: shade_lookup = cache_mat_s2;
                default: shade_lookup = cache_mat_s3;
            endcase
        end
    endfunction

    // Keep group shading in the model cache too.  This avoids another
    // load_index-addressed flip-flop array during dynamic-model rendering.
    logic signed [35:0] group_rvx_calc, group_rvy_calc, group_rvz_calc, group_dot_calc;
    logic signed [35:0] group_rvx_q, group_rvy_q, group_rvz_q;
    logic [1:0] group_shade_q;
    always_comb begin
        group_rvx_calc = (($signed(cache_grp_nx) * $signed(sin16(yaw + 4))) +
                          ($signed(cache_grp_nz) * $signed(sin16(yaw)))) >>> 6;
        group_rvy_calc = $signed(cache_grp_ny);
        group_rvz_calc = ((-$signed(cache_grp_nx) * $signed(sin16(yaw))) +
                          ($signed(cache_grp_nz) * $signed(sin16(yaw + 4)))) >>> 6;
        group_dot_calc = (group_rvx_q * LIGHT_X_Q8) + (group_rvy_q * LIGHT_Y_Q8) + (group_rvz_q * LIGHT_Z_Q8);
    end

    generate
        if (SCENE_CONTROLLED) begin : g_scene_fetcher
            scene_ctrl_model_fetcher u_reader(.*);
        end else begin : g_legacy_fetcher
            model_scene_axi_reader u_reader(.*);
        end
    endgenerate

    always_comb begin
        rd_start = 0;
        rd_addr = active_model_base;
        if (state == HDR_REQ) begin
            rd_start = 1;
            rd_addr = active_model_base + {hdr_index, 2'b00};
        end else if (state == VTX_REQ) begin
            rd_start = 1;
            rd_addr = active_model_base + vertex_pool_base + ({load_index, 3'b0}) + (load_half ? 32'd4 : 0);
        end else if (state == MESH_REQ) begin
            rd_start = 1;
            rd_addr = active_model_base + 32'd16 + ({28'd0,mesh_load_index} << 4) + ({load_half, 2'b00});
        end else if (state == MAT_REQ) begin
            rd_start = 1;
            rd_addr = active_model_base + vertex_pool_base + (vertex_count << 3) + ({load_index, 2'b00});
        end else if (state == GRP_REQ) begin
            rd_start = 1;
            rd_addr = active_model_base + vertex_pool_base + (vertex_count << 3) + (material_count << 3) + ({load_index, 2'b00});
        end else if (state == TRI_REQ) begin
            rd_start = 1;
            rd_addr = active_model_base + vertex_pool_base + (vertex_count << 3) +
                ((format_version == SK3D_VERSION_DYNAMIC) ? ((material_count << 2) + (face_group_count << 2)) : 32'd0) +
                ({load_index, 3'b0}) + (load_half ? 32'd4 : 0);
        end

        mmio_valid = 0;
        mmio_we = 1;
        mmio_addr = 0;
        mmio_wdata = 0;
        if (state == CMD_WRITE) begin
            mmio_valid = 1;
            case (write_phase)
                0: begin mmio_addr = 32'h8; mmio_wdata = cw0; end
                1: begin mmio_addr = 32'hc; mmio_wdata = cw1; end
                2: begin mmio_addr = 32'h10; mmio_wdata = cw2; end
                3: begin mmio_addr = 32'h14; mmio_wdata = cw3; end
                default: begin mmio_addr = 32'h18; mmio_wdata = 1; end
            endcase
        end else if (state == WAIT_FRAME) begin
            mmio_valid = 1;
            mmio_we = 0;
            mmio_addr = 32'h4;
        end else if (state == CLEAR_DONE) begin
            mmio_valid = 1;
            mmio_addr = 32'h4;
            mmio_wdata = 32'h20;
        end
    end

    always_comb begin
        tri_work_a_we = 1'b0;
        tri_work_a_addr = 0;
        tri_work_b_addr = 0;
        tri_work_a_wdata = 0;
        if (state == BUILD_CAPTURE && frontend_visible_q) begin
            tri_work_a_we = 1'b1;
            tri_work_a_addr = visible_count;
            tri_work_a_wdata = {frontend_depth_q, (format_version == SK3D_VERSION_DYNAMIC) ? shade_lookup(cache_group_shade) : cache_color,
                                frontend_sy2_q, frontend_sx2_q, frontend_sy1_q, frontend_sx1_q, frontend_sy0_q, frontend_sx0_q};
        end else if (state == SORT_WRITE_I) begin
            tri_work_a_we = 1'b1;
            tri_work_a_addr = sort_i;
            tri_work_a_wdata = sort_j_record;
        end else if (state == SORT_WRITE_J) begin
            tri_work_a_we = 1'b1;
            tri_work_a_addr = sort_j;
            tri_work_a_wdata = sort_i_record;
        end else if (state == SORT_READ || state == SORT_COMPARE) begin
            tri_work_a_addr = sort_i;
            tri_work_b_addr = sort_j;
        // CMD_WRITE spans five MMIO beats.  Keep the BRAM address stable for
        // all of them; otherwise only cw0 belongs to submit_index while cw1-
        // cw3 silently switch back to entry zero on the following cycles.
        end else if (state == CMD_TRI_READ || (state == CMD_WRITE && cmd_kind == 1)) begin
            tri_work_b_addr = submit_index;
        end
    end

    scene_ctrl_triangle_work_bram #(.DEPTH(MAX_TRIANGLES)) u_triangle_work (
        .clk,
        .a_we(tri_work_a_we), .a_addr(tri_work_a_addr), .a_wdata(tri_work_a_wdata), .a_rdata(tri_work_a_rdata),
        .b_we(1'b0), .b_addr(tri_work_b_addr), .b_wdata('0), .b_rdata(tri_work_b_rdata));

    scene_ctrl_painter_backend u_scene_painter(
        .cmd_kind,.clear_color(SCENE_CONTROLLED ? scene_clear_color : 8'h18),.triangle_color(tri_work_b_rdata[103:96]),
        .x0(tri_work_b_rdata[15:0]),.y0(tri_work_b_rdata[31:16]),.x1(tri_work_b_rdata[47:32]),.y1(tri_work_b_rdata[63:48]),.x2(tri_work_b_rdata[79:64]),.y2(tri_work_b_rdata[95:80]),
        .clear_x(scene_viewport_x),.clear_y(scene_viewport_y),.clear_w(scene_viewport_w),.clear_h(scene_viewport_h),
        .w0(cw0),.w1(cw1),.w2(cw2),.w3(cw3));

    // BUILD owns only cache insertion and material selection.  Geometry
    // visibility, projection and coordinate clamping are delegated to the
    // Scene-owned Triangle Frontend so that this boundary can later move out
    // of the legacy core without changing its behaviour.
    logic frontend_visible;
    logic [15:0] frontend_sx0, frontend_sy0, frontend_sx1, frontend_sy1, frontend_sx2, frontend_sy2;
    logic signed [25:0] frontend_depth;
    // Keep the BRAM-read-to-result path in its own cycle.  This prevents
    // Vivado from routing the transform BRAM output through the frontend
    // arithmetic into the triangle-work BRAM write data in one cycle.
    // DONT_TOUCH prevents retiming this timing boundary away.
    (* DONT_TOUCH = "true" *) logic frontend_visible_q;
    (* DONT_TOUCH = "true" *) logic [15:0] frontend_sx0_q, frontend_sy0_q;
    (* DONT_TOUCH = "true" *) logic [15:0] frontend_sx1_q, frontend_sy1_q;
    (* DONT_TOUCH = "true" *) logic [15:0] frontend_sx2_q, frontend_sy2_q;
    (* DONT_TOUCH = "true" *) logic signed [25:0] frontend_depth_q;
    scene_ctrl_triangle_frontend #(.FRAME_W(FRAME_W), .FRAME_H(FRAME_H)) u_scene_triangle_frontend (
        .x0(tx0), .y0(ty0), .z0(tz0), .x1(tx1), .y1(ty1), .z1(tz1), .x2(tx2), .y2(ty2), .z2(tz2),
        .center_x(SCENE_CONTROLLED ? scene_center_x : (FRAME_W >> 1)),
        .center_y(SCENE_CONTROLLED ? scene_center_y : (FRAME_H >> 1)),
        .enable_backface_cull(SCENE_CONTROLLED ? scene_backface_cull : 1'b1),
        .viewport_enable(SCENE_CONTROLLED && scene_viewport_enable),
        .viewport_x(scene_viewport_x), .viewport_y(scene_viewport_y),
        .viewport_w(scene_viewport_w), .viewport_h(scene_viewport_h),
        .visible(frontend_visible), .sx0(frontend_sx0), .sy0(frontend_sy0),
        .sx1(frontend_sx1), .sy1(frontend_sy1), .sx2(frontend_sx2), .sy2(frontend_sy2),
        .depth(frontend_depth));

    // Registered reads are intentional: XFORM_READ and BUILD_VERTEX_READ
    // issue the address, and their following states consume these outputs.
    always_ff @(posedge clk) begin
        if (state == BUILD) begin
            frontend_visible_q <= frontend_visible;
            frontend_sx0_q <= frontend_sx0;
            frontend_sy0_q <= frontend_sy0;
            frontend_sx1_q <= frontend_sx1;
            frontend_sy1_q <= frontend_sy1;
            frontend_sx2_q <= frontend_sx2;
            frontend_sy2_q <= frontend_sy2;
            frontend_depth_q <= frontend_depth;
        end
        if (scene_xform_valid) begin
            transform_mem0[load_index] <= {scene_xform_x[23:0], scene_xform_y[23:0], scene_xform_z[23:0]};
            transform_mem1[load_index] <= {scene_xform_x[23:0], scene_xform_y[23:0], scene_xform_z[23:0]};
            transform_mem2[load_index] <= {scene_xform_x[23:0], scene_xform_y[23:0], scene_xform_z[23:0]};
        end
        {tx0, ty0, tz0} <= transform_mem0[(state == XFORM_READ) ? load_index : cache_i0];
        {tx1, ty1, tz1} <= transform_mem1[cache_i1];
        {tx2, ty2, tz2} <= transform_mem2[cache_i2];
    end

    always_ff @(posedge clk or negedge resetn) begin : core_seq
        if (!resetn) begin
            state <= IDLE;
            busy <= 0;
            error <= 0;
            error_code <= 0;
            frame_count <= 0;
            yaw <= 0;
            hdr_index <= 0;
            load_index <= 0;
            load_half <= 0;
            vertex_count <= 0;
            triangle_count <= 0;
            format_version <= SK3D_VERSION_STATIC;
            material_count <= 0;
            face_group_count <= 0;
            visible_count <= 0;
            write_phase <= 0;
            cmd_kind <= 0;
            submit_index <= 0;
            dbg_visible_triangles_q <= 0;
            dbg_overlap_hotspot_q <= 0;
            dbg_depth_min_q <= 0;
            dbg_depth_max_q <= 0;
            cache_valid <= 0;
            load_done <= 0;
            render_done <= 0;
            cmd_draw_done <= 0;
            cmd_mesh_count <= 0;
            mesh_count <= 0;
            mesh_load_index <= 0;
            active_vertex_base <= 0; active_vertex_count <= 0;
            active_triangle_base <= 0; active_triangle_count <= 0;
            model_vertex_count <= 0;
            model_triangle_count <= 0;
            sort_i_record <= 0;
            sort_j_record <= 0;
        end else begin
            cmd_draw_done <= 0;
            if (SCENE_CONTROLLED && scene_abort) begin
                busy <= 0; cache_valid <= 0; load_done <= 0; render_done <= 0; state <= IDLE;
            end else begin
            case (state)
                IDLE: if ((SCENE_CONTROLLED && scene_load_start) || (!SCENE_CONTROLLED && start)) begin
                    busy <= 1;
                    error <= 0;
                    error_code <= 0;
                    load_done <= 0; render_done <= 0; cache_valid <= 0;
                    hdr_index <= 0;
                    format_version <= SK3D_VERSION_STATIC;
                    material_count <= 0;
                    face_group_count <= 0;
                    state <= HDR_REQ;
                end
                // The reader raises rd_busy only after the AR request has
                // actually handshaken.  Waiting for it prevents a one-cycle
                // ARREADY stall from dropping the request and deadlocking in
                // the corresponding *_WAIT state.
                HDR_REQ: if (rd_busy) state <= HDR_WAIT;
                HDR_WAIT: if (rd_valid) begin
                    if (rd_error || (hdr_index == 0 && rd_data != MAGIC_SK3D)) begin error_code <= rd_error ? 8'd6 : 8'd2; state <= FAIL; end
                    else begin
                        if (hdr_index == 1) vertex_count <= rd_data[7:0];
                        if (hdr_index == 2) triangle_count <= rd_data[7:0];
                        if (hdr_index == 3) begin
                            format_version <= rd_data[7:0];
                            material_count <= rd_data[15:8];
                            face_group_count <= rd_data[23:16];
                            if (vertex_count > MAX_VERTICES_U8 || triangle_count > MAX_TRIANGLES_U8 ||
                                    vertex_count == 0 || triangle_count == 0 ||
                                    (rd_data[7:0] == SK3D_VERSION_MULTIMESH && (rd_data[11:8] == 0 || rd_data[11:8] > 16)) ||
                                    !(rd_data[7:0] == SK3D_VERSION_STATIC || rd_data[7:0] == SK3D_VERSION_DYNAMIC || rd_data[7:0] == SK3D_VERSION_MULTIMESH) ||
                                    (rd_data[7:0] == SK3D_VERSION_DYNAMIC &&
                                        (rd_data[15:8] == 0 || rd_data[15:8] > MAX_MATERIALS_U8 ||
                                         rd_data[23:16] == 0 || rd_data[23:16] > MAX_FACE_GROUPS_U8)) ||
                                    (SCENE_CONTROLLED && scene_model_size <
                                      (32'd16 + (vertex_count << 3) + (triangle_count << 3) +
                                       ((rd_data[7:0] == SK3D_VERSION_DYNAMIC) ?
                                        (({24'd0,rd_data[15:8]} << 2) + ({24'd0,rd_data[23:16]} << 2)) : 32'd0) +
                                       ((rd_data[7:0] == SK3D_VERSION_MULTIMESH) ? ({24'd0,rd_data[11:8]} << 4) : 32'd0)))) begin
                                if (SCENE_CONTROLLED && scene_model_size < 16) error_code <= 8'd1;
                                else if (!(rd_data[7:0] == SK3D_VERSION_STATIC || rd_data[7:0] == SK3D_VERSION_DYNAMIC || rd_data[7:0] == SK3D_VERSION_MULTIMESH)) error_code <= 8'd3;
                                else if (vertex_count > MAX_VERTICES_U8 || vertex_count == 0) error_code <= 8'd4;
                                else if (triangle_count > MAX_TRIANGLES_U8 || triangle_count == 0) error_code <= 8'd5;
                                else error_code <= 8'd1;
                                state <= FAIL;
                            end
                            else begin
                                model_vertex_count <= {8'd0, vertex_count};
                                model_triangle_count <= {8'd0, triangle_count};
                                mesh_count <= (rd_data[7:0] == SK3D_VERSION_MULTIMESH) ? rd_data[11:8] : 0;
                                cmd_mesh_count <= (rd_data[7:0] == SK3D_VERSION_MULTIMESH) ? rd_data[11:8] : 0;
                                load_index <= 0;
                                load_half <= 0;
                                mesh_load_index <= 0;
                                state <= (rd_data[7:0] == SK3D_VERSION_MULTIMESH) ? MESH_REQ : VTX_REQ;
                            end
                        end else begin
                            hdr_index <= hdr_index + 1;
                            state <= HDR_REQ;
                        end
                    end
                end
                MESH_REQ: if (rd_busy) state <= MESH_WAIT;
                // Descriptor is four 32-bit words: vertex base/count then
                // triangle base/count.  v4 indices are global pool indices.
                MESH_WAIT: if (rd_valid) begin
                    if (rd_error) begin error_code <= 8'd6; state <= FAIL; end
                    else begin
                        if ((load_half == 2'd0 && rd_data[7:0] >= vertex_count) ||
                                (load_half == 2'd1 && (rd_data[7:0] == 0 || ({1'b0, mesh_vertex_base[mesh_load_index]} + {1'b0, rd_data[7:0]}) > {1'b0, vertex_count})) ||
                                (load_half == 2'd2 && rd_data[7:0] >= triangle_count) ||
                                (load_half == 2'd3 && (rd_data[7:0] == 0 || ({1'b0, mesh_triangle_base[mesh_load_index]} + {1'b0, rd_data[7:0]}) > {1'b0, triangle_count}))) begin
                            error_code <= 8'd7;
                            state <= FAIL;
                        end else begin
                            case (load_half)
                                0: mesh_vertex_base[mesh_load_index] <= rd_data[7:0];
                                1: mesh_vertex_count[mesh_load_index] <= rd_data[7:0];
                                2: mesh_triangle_base[mesh_load_index] <= rd_data[7:0];
                                default: mesh_triangle_count[mesh_load_index] <= rd_data[7:0];
                            endcase
                        if (load_half == 2'd3) begin
                            load_half <= 0;
                            if (mesh_load_index + 1 >= mesh_count) begin
                                load_index <= 0;
                                state <= VTX_REQ;
                            end else begin
                                mesh_load_index <= mesh_load_index + 1'b1;
                                state <= MESH_REQ;
                            end
                        end else begin
                            load_half <= load_half + 1'b1;
                            state <= MESH_REQ;
                        end
                        end
                    end
                end
                VTX_REQ: if (rd_busy) state <= VTX_WAIT;
                VTX_WAIT: if (rd_valid) begin
                    if (rd_error) begin error_code <= 8'd6; state <= FAIL; end
                    else if (!load_half) begin
                        pending_word <= rd_data;
                        load_half <= 1;
                        state <= VTX_REQ;
                    end else begin
                        load_half <= 0;
                        if (load_index + 1 >= vertex_count) begin
                            load_index <= 0;
                            state <= (format_version == SK3D_VERSION_DYNAMIC) ? MAT_REQ : TRI_REQ;
                        end else begin
                            load_index <= load_index + 1;
                            state <= VTX_REQ;
                        end
                    end
                end
                MAT_REQ: if (rd_busy) state <= MAT_WAIT;
                MAT_WAIT: if (rd_valid) begin
                    if (rd_error) begin error_code <= 8'd6; state <= FAIL; end
                    else begin
                        if (load_index + 1 >= material_count) begin
                            load_index <= 0;
                            state <= GRP_REQ;
                        end else begin
                            load_index <= load_index + 1;
                            state <= MAT_REQ;
                        end
                    end
                end
                GRP_REQ: if (rd_busy) state <= GRP_WAIT;
                GRP_WAIT: if (rd_valid) begin
                    if (rd_error) begin error_code <= 8'd6; state <= FAIL; end
                    else begin
                        if (load_index + 1 >= face_group_count) begin
                            load_index <= 0;
                            load_half <= 0;
                            state <= TRI_REQ;
                        end else begin
                            load_index <= load_index + 1;
                            state <= GRP_REQ;
                        end
                    end
                end
                TRI_REQ: if (rd_busy) state <= TRI_WAIT;
                TRI_WAIT: if (rd_valid) begin
                    if (rd_error) begin error_code <= 8'd6; state <= FAIL; end
                    else if (!load_half) begin
                        pending_word <= rd_data;
                        load_half <= 1;
                        state <= TRI_REQ;
                    end else begin
                        load_half <= 0;
                        if ((!is_multimesh && (pending_word[7:0] >= vertex_count || pending_word[15:8] >= vertex_count || pending_word[23:16] >= vertex_count)) ||
                                (format_version == SK3D_VERSION_DYNAMIC && (rd_data[7:0] >= material_count || rd_data[15:8] >= face_group_count))) begin error_code <= 8'd7; state <= FAIL; end
                        else if (load_index + 1 >= triangle_count) begin
                        load_index <= 0;
                            state <= SCENE_CONTROLLED ? READY : XFORM_READ;
                        end else begin
                            load_index <= load_index + 1;
                            state <= TRI_REQ;
                        end
                    end
                end
                XFORM_READ: state <= XFORM_LAUNCH;
                XFORM_LAUNCH: state <= XFORM_WAIT;
                XFORM_WAIT: if (scene_xform_valid) begin
                    if (load_index + 1 >= (cmd_mode ? (active_vertex_base + active_vertex_count) : vertex_count)) begin
                        load_index <= cmd_mode ? active_triangle_base : 0;
                        visible_count <= 0;
                        dbg_visible_triangles_q <= 0;
                        dbg_overlap_hotspot_q <= 0;
                        dbg_depth_min_q <= 0;
                        dbg_depth_max_q <= 0;
                        state <= (format_version == SK3D_VERSION_DYNAMIC) ? SHADE_GROUP_READ : BUILD_TRI_READ;
                    end else begin
                        load_index <= load_index + 1;
                        state <= XFORM_READ;
                    end
                end
                SHADE_GROUP_READ: state <= SHADE_GROUP_ROTATE;
                SHADE_GROUP_ROTATE: begin
                    group_rvx_q <= group_rvx_calc;
                    group_rvy_q <= group_rvy_calc;
                    group_rvz_q <= group_rvz_calc;
                    state <= SHADE_GROUP_LIGHT;
                end
                SHADE_GROUP_LIGHT: begin
                    if ((group_dot_calc >>> 8) <= 0) group_shade_q <= 0;
                    else if ((group_dot_calc >>> 8) >= 36'sd192) group_shade_q <= 3;
                    else if ((group_dot_calc >>> 8) >= 36'sd128) group_shade_q <= 2;
                    else if ((group_dot_calc >>> 8) >= 36'sd64) group_shade_q <= 1;
                    else group_shade_q <= 0;
                    state <= SHADE_GROUP_WRITE;
                end
                SHADE_GROUP_WRITE: begin
                    if (load_index + 1 >= face_group_count) begin
                        load_index <= 0;
                        state <= BUILD_TRI_READ;
                    end else begin
                        load_index <= load_index + 1;
                        state <= SHADE_GROUP_READ;
                    end
                end
                BUILD_TRI_READ: state <= BUILD_VERTEX_READ;
                BUILD_VERTEX_READ: state <= BUILD;
                BUILD: state <= BUILD_CAPTURE;
                BUILD_CAPTURE: begin
                    if (frontend_visible_q) begin
                        visible_count <= visible_count + 1;
                        dbg_visible_triangles_q <= visible_count + 1;
                        if (visible_count == 0) begin
                            dbg_depth_min_q <= frontend_depth_q;
                            dbg_depth_max_q <= frontend_depth_q;
                        end else begin
                            if (frontend_depth_q < dbg_depth_min_q) dbg_depth_min_q <= frontend_depth_q;
                            if (frontend_depth_q > dbg_depth_max_q) dbg_depth_max_q <= frontend_depth_q;
                            if (frontend_depth_q > dbg_depth_min_q && frontend_depth_q < dbg_depth_max_q) begin
                                dbg_overlap_hotspot_q <= dbg_overlap_hotspot_q + 1;
                            end
                        end
                    end
                    if (load_index + 1 >= (cmd_mode ? (active_triangle_base + active_triangle_count) : triangle_count)) begin
                        sort_i <= 0;
                        sort_j <= 0;
                        state <= SORT_I;
                    end else begin
                        load_index <= load_index + 1;
                        state <= BUILD_TRI_READ;
                    end
                end
                SORT_I: if (SCENE_CONTROLLED && !scene_depth_sort) begin
                    submit_index <= 0;
                    cmd_kind <= scene_emit_clear ? (scene_emit_local_clear ? 3 : 0) : 1;
                    write_phase <= 0;
                    state <= scene_emit_clear ? CMD_WRITE : CMD_TRI_READ;
                end else if (sort_i + 1 >= visible_count) begin
                    submit_index <= 0;
                    cmd_kind <= (SCENE_CONTROLLED && !scene_emit_clear) ? 1 :
                                (scene_emit_local_clear ? 3 : 0);
                    write_phase <= 0;
                    state <= (SCENE_CONTROLLED && !scene_emit_clear) ? CMD_TRI_READ : CMD_WRITE;
                end else begin
                    sort_j <= sort_i + 1;
                    state <= SORT_READ;
                end
                // Both BRAM ports issue their reads in SORT_READ.  The output
                // registers are valid in SORT_COMPARE, where we capture them
                // before writing the two halves of a swap on separate cycles.
                SORT_READ: state <= SORT_COMPARE;
                SORT_COMPARE: begin
                    sort_i_record <= tri_work_a_rdata;
                    sort_j_record <= tri_work_b_rdata;
                    if ($signed(tri_work_b_rdata[129:104]) < $signed(tri_work_a_rdata[129:104])) state <= SORT_WRITE_I;
                    else if (sort_j + 1 >= visible_count) begin
                        sort_i <= sort_i + 1;
                        state <= SORT_I;
                    end else begin
                        sort_j <= sort_j + 1;
                        state <= SORT_READ;
                    end
                end
                SORT_WRITE_I: state <= SORT_WRITE_J;
                SORT_WRITE_J: begin
                    if (sort_j + 1 >= visible_count) begin
                        sort_i <= sort_i + 1;
                        state <= SORT_I;
                    end else begin
                        sort_j <= sort_j + 1;
                        state <= SORT_READ;
                    end
                end
                CMD_WRITE: if (mmio_ready) begin
                    if (write_phase == 4) begin
                        write_phase <= 0;
                        state <= CMD_SETUP;
                    end else write_phase <= write_phase + 1;
                end
                CMD_SETUP: if ((cmd_kind == 0) || (cmd_kind == 3)) begin
                    cmd_kind <= 1;
                    submit_index <= 0;
                    state <= CMD_TRI_READ;
                end else if (cmd_kind == 1) begin
                    if (submit_index + 1 >= visible_count) begin
                        if (SCENE_CONTROLLED && !scene_auto_present) state <= RENDER_FINISH;
                        else begin cmd_kind <= 2; state <= CMD_WRITE; end
                    end else begin
                        submit_index <= submit_index + 1;
                        state <= CMD_TRI_READ;
                    end
                end else state <= WAIT_FRAME;
                CMD_TRI_READ: state <= CMD_WRITE;
                WAIT_FRAME: if (mmio_ready && mmio_rdata[5]) state <= CLEAR_DONE;
                CLEAR_DONE: if (mmio_ready) begin
                    frame_count <= frame_count + 1;
                    yaw <= yaw + 1;
                    load_index <= 0;
                    visible_count <= 0;
                    if (SCENE_CONTROLLED && !scene_animation_enable) begin
                        busy <= 0;
                        render_done <= 1;
                        state <= READY;
                    end else state <= XFORM_READ;
                end
                RENDER_FINISH: begin
                    frame_count <= frame_count + 1;
                    yaw <= yaw + 1;
                    load_index <= 0;
                    visible_count <= 0;
                    if (cmd_mode) begin
                        busy <= 0;
                        cmd_draw_done <= 1;
                        state <= READY;
                    end else if (SCENE_CONTROLLED && !scene_animation_enable) begin
                        busy <= 0;
                        render_done <= 1;
                        state <= READY;
                    end else state <= XFORM_READ;
                end
                READY: begin
                    busy <= 0;
                    cache_valid <= 1;
                    load_done <= 1;
                    // Scene-controlled users may replace the cached asset
                    // without resetting the whole subsystem.  This is the
                    // hand-off used by the S3PK catalog selector.
                    if (SCENE_CONTROLLED && scene_load_start) begin
                        busy <= 1;
                        error <= 0;
                        error_code <= 0;
                        cache_valid <= 0;
                        load_done <= 0;
                        render_done <= 0;
                        hdr_index <= 0;
                        format_version <= SK3D_VERSION_STATIC;
                        material_count <= 0;
                        face_group_count <= 0;
                        state <= HDR_REQ;
                    end else if (scene_render_start) begin
                        busy <= 1;
                        render_done <= 0;
                        yaw <= scene_yaw[3:0];
                        load_index <= 0;
                        visible_count <= 0;
                        state <= XFORM_READ;
                    end else if (cmd_mode && cmd_draw_start) begin
                        if (cmd_mesh_id >= mesh_count || mesh_vertex_count[cmd_mesh_id] == 0 || mesh_triangle_count[cmd_mesh_id] == 0) begin
                            error_code <= 8'd8;
                            error <= 1'b1;
                        end else begin
                            busy <= 1;
                            active_vertex_base <= mesh_vertex_base[cmd_mesh_id];
                            active_vertex_count <= mesh_vertex_count[cmd_mesh_id];
                            active_triangle_base <= mesh_triangle_base[cmd_mesh_id];
                            active_triangle_count <= mesh_triangle_count[cmd_mesh_id];
                            yaw <= cmd_yaw;
                            load_index <= mesh_vertex_base[cmd_mesh_id];
                            visible_count <= 0;
                            state <= XFORM_READ;
                        end
                    end
                end
                FAIL: begin
                    error <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
            end
        end
    end
endmodule

// 130 bits is intentionally one logical triangle record.  Vivado splits the
// wide word across RAMB primitives as needed, while retaining the required
// true-dual-port BRAM behaviour.  Both ports use the same synchronous-read
// template as sketch_frame_page_bram.
module scene_ctrl_triangle_work_bram #(
    parameter int DEPTH = 192,
    parameter int AW = $clog2(DEPTH)
) (
    input  logic           clk,
    input  logic           a_we,
    input  logic [AW-1:0]  a_addr,
    input  logic [129:0]   a_wdata,
    output logic [129:0]   a_rdata,
    input  logic           b_we,
    input  logic [AW-1:0]  b_addr,
    input  logic [129:0]   b_wdata,
    output logic [129:0]   b_rdata
);
    localparam V_STYLE = "block";
    localparam P_STYLE = "block_ram";
    (* ram_style = V_STYLE *) logic [129:0] BRAM [0:DEPTH-1]
        /* synthesis syn_ramstyle = P_STYLE */;

    always_ff @(posedge clk) begin
        if (a_we) BRAM[a_addr] <= a_wdata;
        if (b_we) BRAM[b_addr] <= b_wdata;
        a_rdata <= BRAM[a_addr];
        b_rdata <= BRAM[b_addr];
    end
endmodule
