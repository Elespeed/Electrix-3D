// On-chip cache for the immutable SK3D model data.  Read ports are
// combinational because the current Scene engine consumes one record per
// state-machine cycle; synthesis may map these small, independently addressed
// arrays to LUTRAM or BRAM according to the target and parameters.
module scene_ctrl_model_cache #(
    parameter int MAX_VERTICES = 128,
    parameter int MAX_TRIANGLES = 192,
    parameter int MAX_MATERIALS = 64,
    parameter int MAX_FACE_GROUPS = 192
) (
    input logic clk,
    input logic vertex_wr_en, input logic [7:0] vertex_wr_addr,
    input logic [15:0] vertex_wr_x, input logic [15:0] vertex_wr_y, input logic [15:0] vertex_wr_z,
    input logic triangle_wr_en, input logic [7:0] triangle_wr_addr,
    input logic [7:0] triangle_wr_i0, input logic [7:0] triangle_wr_i1, input logic [7:0] triangle_wr_i2,
    input logic [7:0] triangle_wr_color, input logic [7:0] triangle_wr_material, input logic [7:0] triangle_wr_group,
    input logic material_wr_en, input logic [7:0] material_wr_addr,
    input logic [7:0] material_wr_s0, input logic [7:0] material_wr_s1, input logic [7:0] material_wr_s2, input logic [7:0] material_wr_s3,
    input logic group_wr_en, input logic [7:0] group_wr_addr,
    input logic signed [9:0] group_wr_nx, input logic signed [9:0] group_wr_ny, input logic signed [9:0] group_wr_nz,
    input logic group_shade_wr_en, input logic [7:0] group_shade_wr_addr, input logic [1:0] group_shade_wr_data,
    input logic [7:0] vertex_rd_addr0, input logic [7:0] vertex_rd_addr1, input logic [7:0] vertex_rd_addr2,
    output logic [15:0] vertex_rd0_x, output logic [15:0] vertex_rd0_y, output logic [15:0] vertex_rd0_z,
    output logic [15:0] vertex_rd1_x, output logic [15:0] vertex_rd1_y, output logic [15:0] vertex_rd1_z,
    output logic [15:0] vertex_rd2_x, output logic [15:0] vertex_rd2_y, output logic [15:0] vertex_rd2_z,
    input logic [7:0] triangle_rd_addr,
    output logic [7:0] triangle_rd_i0, output logic [7:0] triangle_rd_i1, output logic [7:0] triangle_rd_i2,
    output logic [7:0] triangle_rd_color, output logic [7:0] triangle_rd_material, output logic [7:0] triangle_rd_group,
    input logic [7:0] material_rd_addr,
    output logic [7:0] material_rd_s0, output logic [7:0] material_rd_s1, output logic [7:0] material_rd_s2, output logic [7:0] material_rd_s3,
    input logic [7:0] group_rd_addr,
    output logic signed [9:0] group_rd_nx, output logic signed [9:0] group_rd_ny, output logic signed [9:0] group_rd_nz,
    output logic [1:0] group_rd_shade
);
    // Three replicated 1W1R RAMs infer BRAMs.  An asynchronous 1W3R array
    // was implemented as flip-flops, leaving load_index on a 128-way decoder.
    (* ram_style = "block" *) logic [47:0] vertex_mem0 [0:MAX_VERTICES-1];
    (* ram_style = "block" *) logic [47:0] vertex_mem1 [0:MAX_VERTICES-1];
    (* ram_style = "block" *) logic [47:0] vertex_mem2 [0:MAX_VERTICES-1];
    (* ram_style = "block" *) logic [47:0] triangle_mem [0:MAX_TRIANGLES-1];
    (* ram_style = "block" *) logic [31:0] material_mem [0:MAX_MATERIALS-1];
    (* ram_style = "block" *) logic [29:0] group_mem [0:MAX_FACE_GROUPS-1];
    (* ram_style = "block" *) logic [1:0] grp_shade_level [0:MAX_FACE_GROUPS-1];

    always_ff @(posedge clk) begin
        if (vertex_wr_en) begin
            vertex_mem0[vertex_wr_addr] <= {vertex_wr_x, vertex_wr_y, vertex_wr_z};
            vertex_mem1[vertex_wr_addr] <= {vertex_wr_x, vertex_wr_y, vertex_wr_z};
            vertex_mem2[vertex_wr_addr] <= {vertex_wr_x, vertex_wr_y, vertex_wr_z};
        end
        if (triangle_wr_en) triangle_mem[triangle_wr_addr] <= {triangle_wr_i0, triangle_wr_i1, triangle_wr_i2, triangle_wr_color, triangle_wr_material, triangle_wr_group};
        if (material_wr_en) material_mem[material_wr_addr] <= {material_wr_s0, material_wr_s1, material_wr_s2, material_wr_s3};
        if (group_wr_en) group_mem[group_wr_addr] <= {group_wr_nx, group_wr_ny, group_wr_nz};
        if (group_shade_wr_en) grp_shade_level[group_shade_wr_addr] <= group_shade_wr_data;
        {vertex_rd0_x, vertex_rd0_y, vertex_rd0_z} <= vertex_mem0[vertex_rd_addr0];
        {vertex_rd1_x, vertex_rd1_y, vertex_rd1_z} <= vertex_mem1[vertex_rd_addr1];
        {vertex_rd2_x, vertex_rd2_y, vertex_rd2_z} <= vertex_mem2[vertex_rd_addr2];
        {triangle_rd_i0, triangle_rd_i1, triangle_rd_i2, triangle_rd_color, triangle_rd_material, triangle_rd_group} <= triangle_mem[triangle_rd_addr];
        {material_rd_s0, material_rd_s1, material_rd_s2, material_rd_s3} <= material_mem[material_rd_addr];
        {group_rd_nx, group_rd_ny, group_rd_nz} <= group_mem[group_rd_addr];
        group_rd_shade <= grp_shade_level[group_rd_addr];
    end
endmodule
