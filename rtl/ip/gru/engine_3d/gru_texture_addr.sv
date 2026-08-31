`include "gru_defs.vh"

module gru_texture_addr (
    input  logic [31:0]        tex_base,
    input  logic [31:0]        tex_stride,
    input  logic [15:0]        tex_width,
    input  logic [15:0]        tex_height,
    input  logic               wrap_mode,
    input  logic signed [15:0] u_q8_8,
    input  logic signed [15:0] v_q8_8,
    output logic [15:0]        sample_x,
    output logic [15:0]        sample_y,
    output logic [31:0]        texel_addr
);
    logic signed [16:0] u_px;
    logic signed [16:0] v_px;
    logic [15:0]        x_now;
    logic [15:0]        y_now;
    logic               width_is_pow2;
    logic               height_is_pow2;

    function automatic logic [15:0] clamp_coord(
        input logic signed [16:0] value,
        input logic [15:0]        limit
    );
        begin
            if (limit == 16'd0) begin
                clamp_coord = 16'd0;
            end else if (value < 0) begin
                clamp_coord = 16'd0;
            end else if (value >= $signed({1'b0, limit})) begin
                clamp_coord = limit - 16'd1;
            end else begin
                clamp_coord = value[15:0];
            end
        end
    endfunction

    function automatic logic [15:0] repeat_coord(
        input logic signed [16:0] value,
        input logic [15:0]        limit,
        input logic               limit_is_pow2
    );
        logic signed [16:0] limit_s;
        logic signed [16:0] mod_now;
        begin
            if (limit == 16'd0) begin
                repeat_coord = 16'd0;
            end else if (limit_is_pow2) begin
                repeat_coord = value[15:0] & (limit - 16'd1);
            end else begin
                limit_s = $signed({1'b0, limit});
                mod_now = value % limit_s;
                if (mod_now < 0) begin
                    mod_now = mod_now + limit_s;
                end
                repeat_coord = mod_now[15:0];
            end
        end
    endfunction

    always_comb begin
        width_is_pow2 = (tex_width != 16'd0) && ((tex_width & (tex_width - 16'd1)) == 16'd0);
        height_is_pow2 = (tex_height != 16'd0) && ((tex_height & (tex_height - 16'd1)) == 16'd0);
        u_px = (u_q8_8 + 16'sd128) >>> 8;
        v_px = (v_q8_8 + 16'sd128) >>> 8;

        if (wrap_mode == `GRU_TEX_WRAP_REPEAT) begin
            x_now = repeat_coord(u_px, tex_width, width_is_pow2);
            y_now = repeat_coord(v_px, tex_height, height_is_pow2);
        end else begin
            x_now = clamp_coord(u_px, tex_width);
            y_now = clamp_coord(v_px, tex_height);
        end

        sample_x = x_now;
        sample_y = y_now;
        texel_addr = tex_base + (y_now * tex_stride) + (x_now <<< 1);
    end
endmodule
