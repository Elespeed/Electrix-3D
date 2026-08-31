`include "gru_defs.vh"

module gru_triangle_raster (
    input  logic                      clk,
    input  logic                      rstn,
    input  logic                      clr,
    input  logic                      start,
    input  logic [`GRU_SEQ_W-1:0]     seq_id,
    input  logic                      gouraud_en,
    input  logic                      textured_en,
    input  logic                      perspective_en,
    input  logic [15:0]               flat_rgb565,
    input  logic [15:0]               c0_rgb565,
    input  logic [15:0]               c1_rgb565,
    input  logic [15:0]               c2_rgb565,
    input  logic signed [15:0]        u0_q8_8,
    input  logic signed [15:0]        v0_q8_8,
    input  logic signed [15:0]        u1_q8_8,
    input  logic signed [15:0]        v1_q8_8,
    input  logic signed [15:0]        u2_q8_8,
    input  logic signed [15:0]        v2_q8_8,
    input  logic signed [15:0]        inv_w0_q8_8,
    input  logic signed [15:0]        inv_w1_q8_8,
    input  logic signed [15:0]        inv_w2_q8_8,
    input  logic [31:0]               tex_base,
    input  logic [31:0]               tex_stride,
    input  logic [15:0]               tex_width,
    input  logic [15:0]               tex_height,
    input  logic [2:0]                tex_format,
    input  logic                      tex_wrap_mode,
    input  logic signed [15:0]        x0,
    input  logic signed [15:0]        y0,
    input  logic signed [15:0]        x1,
    input  logic signed [15:0]        y1,
    input  logic signed [15:0]        x2,
    input  logic signed [15:0]        y2,
    input  logic signed [15:0]        bbox_min_x,
    input  logic signed [15:0]        bbox_max_x,
    input  logic signed [15:0]        bbox_min_y,
    input  logic signed [15:0]        bbox_max_y,
    input  logic signed [31:0]        area2,
    input  logic                      reject,
    output logic                      busy,
    output logic                      span_valid,
    input  logic                      span_ready,
    output logic [`GRU_SPAN_W-1:0]    span_data,
    output logic [4:0]                m_axi_arid,
    output logic [31:0]               m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arlock,
    output logic [3:0]                m_axi_arcache,
    output logic [2:0]                m_axi_arprot,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [4:0]                m_axi_rid,
    input  logic [127:0]              m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready
);
    typedef enum logic [3:0] {
        S_IDLE,
        S_SETUP_EDGE,
        S_SETUP_COLOR_GRAD,
        S_SETUP_COLOR_START,
        S_SETUP_UV_GRAD,
        S_SETUP_UV_START,
        S_SCAN,
        S_RECIP,
        S_RECOVER,
        S_TEXADDR,
        S_WAIT_AR,
        S_WAIT_R,
        S_HAVE_TEXEL,
        S_EMIT_SPAN
    } state_t;

    function automatic logic signed [31:0] edge_value(
        input logic signed [15:0] px,
        input logic signed [15:0] py,
        input logic signed [15:0] ax,
        input logic signed [15:0] ay,
        input logic signed [15:0] bx,
        input logic signed [15:0] by
    );
        logic signed [16:0] dx_a;
        logic signed [16:0] dy_a;
        logic signed [16:0] dx_b;
        logic signed [16:0] dy_b;
        begin
            dx_a = px - ax;
            dy_a = py - ay;
            dx_b = bx - ax;
            dy_b = by - ay;
            edge_value = ($signed({{17{dx_a[16]}}, dx_a}) * $signed({{17{dy_b[16]}}, dy_b}))
                       - ($signed({{17{dy_a[16]}}, dy_a}) * $signed({{17{dx_b[16]}}, dx_b}));
        end
    endfunction

    function automatic logic signed [31:0] calc_grad_q8_8(
        input logic signed [15:0] a0,
        input logic signed [15:0] a1,
        input logic signed [15:0] a2,
        input logic signed [15:0] c0,
        input logic signed [15:0] c1,
        input logic signed [15:0] c2,
        input logic signed [31:0] area
    );
        logic signed [47:0] numer;
        logic signed [31:0] denom;
        begin
            numer = ($signed(a0) * $signed(c0))
                  + ($signed(a1) * $signed(c1))
                  + ($signed(a2) * $signed(c2));
            denom = area;
            if (denom < 0) begin
                numer = -numer;
                denom = -denom;
            end
            if (denom == 0) begin
                calc_grad_q8_8 = 32'sd0;
            end else begin
                calc_grad_q8_8 = numer / denom;
            end
        end
    endfunction

    function automatic logic signed [31:0] calc_start_attr_q8_8(
        input logic signed [15:0] base_attr_q8_8,
        input logic signed [31:0] grad_x_q8_8,
        input logic signed [31:0] grad_y_q8_8,
        input logic signed [15:0] start_x,
        input logic signed [15:0] start_y,
        input logic signed [15:0] ref_x,
        input logic signed [15:0] ref_y
    );
        logic signed [16:0] dx;
        logic signed [16:0] dy;
        logic signed [47:0] accum;
        begin
            dx = start_x - ref_x;
            dy = start_y - ref_y;
            accum = ($signed({{32{base_attr_q8_8[15]}}, base_attr_q8_8}) <<< 8)
                  + ($signed(grad_x_q8_8) * $signed(dx))
                  + ($signed(grad_y_q8_8) * $signed(dy));
            calc_start_attr_q8_8 = accum[31:0];
        end
    endfunction

    function automatic logic signed [31:0] interp_attr_q8_8(
        input logic signed [31:0] w0,
        input logic signed [31:0] w1,
        input logic signed [31:0] w2,
        input logic signed [31:0] area,
        input logic signed [15:0] a0_q8_8,
        input logic signed [15:0] a1_q8_8,
        input logic signed [15:0] a2_q8_8
    );
        logic signed [63:0] numer;
        logic signed [31:0] denom;
        begin
            numer = ($signed(w0) * $signed(a0_q8_8))
                  + ($signed(w1) * $signed(a1_q8_8))
                  + ($signed(w2) * $signed(a2_q8_8));
            denom = area;
            if (denom < 0) begin
                numer = -numer;
                denom = -denom;
            end
            if (denom == 0) begin
                interp_attr_q8_8 = 32'sd0;
            end else begin
                interp_attr_q8_8 = numer / denom;
            end
        end
    endfunction

    function automatic logic signed [31:0] reciprocal_q16_16_from_q8_8(
        input logic signed [31:0] value_q8_8
    );
        logic signed [31:0] abs_value_q8_8;
        logic signed [31:0] abs_recip_q16_16;
        begin
            abs_value_q8_8 = value_q8_8[31] ? -value_q8_8 : value_q8_8;
            if (abs_value_q8_8 == 32'sd0) begin
                reciprocal_q16_16_from_q8_8 = 32'sd0;
            end else begin
                abs_recip_q16_16 = (32'sd1 <<< 24) / abs_value_q8_8;
                reciprocal_q16_16_from_q8_8 = value_q8_8[31] ? -abs_recip_q16_16 : abs_recip_q16_16;
            end
        end
    endfunction

    function automatic logic signed [15:0] recover_coord(
        input logic signed [31:0] attr_over_w_q8_8,
        input logic signed [31:0] reciprocal_q16_16
    );
        logic signed [63:0] prod;
        logic signed [63:0] rounded;
        begin
            prod = $signed(attr_over_w_q8_8) * $signed(reciprocal_q16_16);
            if (prod >= 0) begin
                rounded = prod + 64'sd32768;
            end else begin
                rounded = prod - 64'sd32768;
            end
            recover_coord = rounded[31:16];
        end
    endfunction

    function automatic logic [5:0] clamp_u6(input logic signed [31:0] value_q8_8);
        logic signed [31:0] rounded;
        begin
            rounded = value_q8_8 + 32'sd128;
            if (rounded < 0) begin
                clamp_u6 = 6'd0;
            end else if ((rounded >>> 8) > 63) begin
                clamp_u6 = 6'd63;
            end else begin
                clamp_u6 = rounded >>> 8;
            end
        end
    endfunction

    function automatic logic [4:0] clamp_u5(input logic signed [31:0] value_q8_8);
        logic signed [31:0] rounded;
        begin
            rounded = value_q8_8 + 32'sd128;
            if (rounded < 0) begin
                clamp_u5 = 5'd0;
            end else if ((rounded >>> 8) > 31) begin
                clamp_u5 = 5'd31;
            end else begin
                clamp_u5 = rounded >>> 8;
            end
        end
    endfunction

    logic active;
    logic dummy_pending;
    logic [`GRU_SEQ_W-1:0] seq_q;
    logic gouraud_q;
    logic textured_q;
    logic perspective_q;
    logic [15:0] flat_rgb565_q;
    logic [15:0] c0_rgb565_q;
    logic [15:0] c1_rgb565_q;
    logic [15:0] c2_rgb565_q;
    logic [2:0]  tex_format_q;
    logic [31:0] tex_base_q;
    logic [31:0] tex_stride_q;
    logic [15:0] tex_width_q;
    logic [15:0] tex_height_q;
    logic        tex_wrap_mode_q;
    logic signed [15:0] x0_q;
    logic signed [15:0] y0_q;
    logic signed [15:0] x1_q;
    logic signed [15:0] y1_q;
    logic signed [15:0] x2_q;
    logic signed [15:0] y2_q;
    logic signed [15:0] u0_q8_8_q;
    logic signed [15:0] v0_q8_8_q;
    logic signed [15:0] u1_q8_8_q;
    logic signed [15:0] v1_q8_8_q;
    logic signed [15:0] u2_q8_8_q;
    logic signed [15:0] v2_q8_8_q;
    logic signed [15:0] inv_w0_q8_8_q;
    logic signed [15:0] inv_w1_q8_8_q;
    logic signed [15:0] inv_w2_q8_8_q;

    logic signed [15:0] min_x_q;
    logic signed [15:0] max_x_q;
    logic signed [15:0] min_y_q;
    logic signed [15:0] max_y_q;
    logic signed [15:0] cur_x;
    logic signed [15:0] cur_y;
    logic signed [31:0] area_q;

    logic signed [31:0] edge0_dx_q;
    logic signed [31:0] edge0_dy_q;
    logic signed [31:0] edge1_dx_q;
    logic signed [31:0] edge1_dy_q;
    logic signed [31:0] edge2_dx_q;
    logic signed [31:0] edge2_dy_q;
    logic signed [31:0] row_w0_q;
    logic signed [31:0] row_w1_q;
    logic signed [31:0] row_w2_q;
    logic signed [31:0] w0_q;
    logic signed [31:0] w1_q;
    logic signed [31:0] w2_q;

    logic signed [31:0] color_r_dx_q;
    logic signed [31:0] color_r_dy_q;
    logic signed [31:0] color_g_dx_q;
    logic signed [31:0] color_g_dy_q;
    logic signed [31:0] color_b_dx_q;
    logic signed [31:0] color_b_dy_q;
    logic signed [31:0] row_color_r_q;
    logic signed [31:0] row_color_g_q;
    logic signed [31:0] row_color_b_q;
    logic signed [31:0] color_r_q;
    logic signed [31:0] color_g_q;
    logic signed [31:0] color_b_q;

    logic signed [31:0] u_dx_q;
    logic signed [31:0] u_dy_q;
    logic signed [31:0] v_dx_q;
    logic signed [31:0] v_dy_q;
    logic signed [31:0] inv_w_dx_q;
    logic signed [31:0] inv_w_dy_q;
    logic signed [31:0] row_u_q;
    logic signed [31:0] row_v_q;
    logic signed [31:0] row_inv_w_q;
    logic signed [31:0] u_q;
    logic signed [31:0] v_q;
    logic signed [31:0] inv_w_q;

    logic        pixel_inside_q;
    logic        pixel_last_q;
    logic [15:0] pixel_color565_q;
    logic signed [31:0] recip_q16_16_q;
    logic        recip_valid_q;
    logic signed [15:0] final_u_q8_8_q;
    logic signed [15:0] final_v_q8_8_q;
    logic [31:0] texel_addr_q;
    logic [15:0] sampled_texel_q;

    logic [15:0] tex_sample_x_now;
    logic [15:0] tex_sample_y_now;
    logic [31:0] texel_addr_now;
    logic [127:0] tex_beat_data;
    logic         tex_cache_resp_valid;
    logic         tex_cache_resp_ready;
    logic         tex_cache_resp_error;
    logic         tex_cache_req_ready;
    logic [15:0] sampled_texel_now;
    logic        tex_format_supported;
    logic [15:0] color_r0_q8_8;
    logic [15:0] color_r1_q8_8;
    logic [15:0] color_r2_q8_8;
    logic [15:0] color_g0_q8_8;
    logic [15:0] color_g1_q8_8;
    logic [15:0] color_g2_q8_8;
    logic [15:0] color_b0_q8_8;
    logic [15:0] color_b1_q8_8;
    logic [15:0] color_b2_q8_8;
    state_t      state_q;

    assign color_r0_q8_8 = {c0_rgb565_q[15:11], 8'd0};
    assign color_r1_q8_8 = {c1_rgb565_q[15:11], 8'd0};
    assign color_r2_q8_8 = {c2_rgb565_q[15:11], 8'd0};
    assign color_g0_q8_8 = {c0_rgb565_q[10:5], 8'd0};
    assign color_g1_q8_8 = {c1_rgb565_q[10:5], 8'd0};
    assign color_g2_q8_8 = {c2_rgb565_q[10:5], 8'd0};
    assign color_b0_q8_8 = {c0_rgb565_q[4:0], 8'd0};
    assign color_b1_q8_8 = {c1_rgb565_q[4:0], 8'd0};
    assign color_b2_q8_8 = {c2_rgb565_q[4:0], 8'd0};

    gru_texture_addr u_gru_texture_addr (
        .tex_base    (tex_base_q),
        .tex_stride  (tex_stride_q),
        .tex_width   (tex_width_q),
        .tex_height  (tex_height_q),
        .wrap_mode   (tex_wrap_mode_q),
        .u_q8_8      (final_u_q8_8_q),
        .v_q8_8      (final_v_q8_8_q),
        .sample_x    (tex_sample_x_now),
        .sample_y    (tex_sample_y_now),
        .texel_addr  (texel_addr_now)
    );

    gru_texture_sampler u_gru_texture_sampler (
        .beat_data         (tex_beat_data),
        .texel_byte_lane   (texel_addr_q[3:0]),
        .tex_format        (tex_format_q),
        .rgb565            (sampled_texel_now),
        .format_supported  (tex_format_supported)
    );

    gru_texture_line_cache u_gru_texture_line_cache (
        .clk          (clk),
        .rstn         (rstn),
        .clr          (clr),
        .req_valid    (active && textured_q && (state_q == S_WAIT_AR)),
        .req_ready    (tex_cache_req_ready),
        .req_addr     (texel_addr_q),
        .resp_valid   (tex_cache_resp_valid),
        .resp_ready   (tex_cache_resp_ready),
        .resp_data    (tex_beat_data),
        .resp_error   (tex_cache_resp_error),
        .hit_count    (),
        .miss_count   (),
        .m_axi_arid   (m_axi_arid),
        .m_axi_araddr (m_axi_araddr),
        .m_axi_arlen  (m_axi_arlen),
        .m_axi_arsize (m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock (m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot (m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid    (m_axi_rid),
        .m_axi_rdata  (m_axi_rdata),
        .m_axi_rresp  (m_axi_rresp),
        .m_axi_rlast  (m_axi_rlast),
        .m_axi_rvalid (m_axi_rvalid),
        .m_axi_rready (m_axi_rready)
    );

    assign busy = active;
    assign tex_cache_resp_ready = active && textured_q && (state_q == S_WAIT_R);

    always_comb begin
        pixel_inside_q = 1'b0;
        if (area_q > 0) begin
            pixel_inside_q = (w0_q >= 0) && (w1_q >= 0) && (w2_q >= 0);
        end else if (area_q < 0) begin
            pixel_inside_q = (w0_q <= 0) && (w1_q <= 0) && (w2_q <= 0);
        end
        pixel_last_q = (cur_x == max_x_q) && (cur_y == max_y_q);
        pixel_color565_q = {clamp_u5(color_r_q), clamp_u6(color_g_q), clamp_u5(color_b_q)};

        span_data = '0;
        span_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] = seq_q;
        span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB] = cur_y[`GRU_Y_W-1:0];
        span_data[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB] = cur_x[8:0];
        span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = dummy_pending ? 10'd0 : 10'd1;
        if (dummy_pending) begin
            span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] = 16'd0;
        end else if (textured_q) begin
            span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] = sampled_texel_q;
        end else if (gouraud_q) begin
            span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] = pixel_color565_q;
        end else begin
            span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] = flat_rgb565_q;
        end
        span_data[`GRU_SPAN_LAST_BIT] = dummy_pending ? 1'b1 : pixel_last_q;
    end

    assign span_valid = active && (dummy_pending ||
                                   (textured_q ? (state_q == S_HAVE_TEXEL)
                                               : (state_q == S_EMIT_SPAN)));

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            seq_q <= '0;
            gouraud_q <= 1'b0;
            textured_q <= 1'b0;
            perspective_q <= 1'b0;
            flat_rgb565_q <= '0;
            c0_rgb565_q <= '0;
            c1_rgb565_q <= '0;
            c2_rgb565_q <= '0;
            tex_format_q <= '0;
            tex_base_q <= '0;
            tex_stride_q <= '0;
            tex_width_q <= '0;
            tex_height_q <= '0;
            tex_wrap_mode_q <= 1'b0;
            x0_q <= '0; y0_q <= '0;
            x1_q <= '0; y1_q <= '0;
            x2_q <= '0; y2_q <= '0;
            u0_q8_8_q <= '0; v0_q8_8_q <= '0;
            u1_q8_8_q <= '0; v1_q8_8_q <= '0;
            u2_q8_8_q <= '0; v2_q8_8_q <= '0;
            inv_w0_q8_8_q <= '0;
            inv_w1_q8_8_q <= '0;
            inv_w2_q8_8_q <= '0;
            min_x_q <= '0;
            max_x_q <= '0;
            min_y_q <= '0;
            max_y_q <= '0;
            cur_x <= '0;
            cur_y <= '0;
            area_q <= '0;
            edge0_dx_q <= '0; edge0_dy_q <= '0;
            edge1_dx_q <= '0; edge1_dy_q <= '0;
            edge2_dx_q <= '0; edge2_dy_q <= '0;
            row_w0_q <= '0; row_w1_q <= '0; row_w2_q <= '0;
            w0_q <= '0; w1_q <= '0; w2_q <= '0;
            color_r_dx_q <= '0; color_r_dy_q <= '0;
            color_g_dx_q <= '0; color_g_dy_q <= '0;
            color_b_dx_q <= '0; color_b_dy_q <= '0;
            row_color_r_q <= '0; row_color_g_q <= '0; row_color_b_q <= '0;
            color_r_q <= '0; color_g_q <= '0; color_b_q <= '0;
            u_dx_q <= '0; u_dy_q <= '0; v_dx_q <= '0; v_dy_q <= '0;
            inv_w_dx_q <= '0; inv_w_dy_q <= '0;
            row_u_q <= '0; row_v_q <= '0; row_inv_w_q <= '0;
            u_q <= '0; v_q <= '0; inv_w_q <= '0;
            recip_q16_16_q <= '0;
            recip_valid_q <= 1'b0;
            final_u_q8_8_q <= '0;
            final_v_q8_8_q <= '0;
            texel_addr_q <= '0;
            sampled_texel_q <= '0;
            state_q <= S_IDLE;
        end else if (clr) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            recip_valid_q <= 1'b0;
            state_q <= S_IDLE;
        end else begin
            if (start) begin
                active <= 1'b1;
                dummy_pending <= reject;
                seq_q <= seq_id;
                gouraud_q <= gouraud_en;
                textured_q <= textured_en;
                perspective_q <= perspective_en;
                flat_rgb565_q <= flat_rgb565;
                c0_rgb565_q <= c0_rgb565;
                c1_rgb565_q <= c1_rgb565;
                c2_rgb565_q <= c2_rgb565;
                tex_format_q <= tex_format;
                tex_base_q <= tex_base;
                tex_stride_q <= tex_stride;
                tex_width_q <= tex_width;
                tex_height_q <= tex_height;
                tex_wrap_mode_q <= tex_wrap_mode;
                x0_q <= x0; y0_q <= y0;
                x1_q <= x1; y1_q <= y1;
                x2_q <= x2; y2_q <= y2;
                u0_q8_8_q <= u0_q8_8; v0_q8_8_q <= v0_q8_8;
                u1_q8_8_q <= u1_q8_8; v1_q8_8_q <= v1_q8_8;
                u2_q8_8_q <= u2_q8_8; v2_q8_8_q <= v2_q8_8;
                inv_w0_q8_8_q <= inv_w0_q8_8;
                inv_w1_q8_8_q <= inv_w1_q8_8;
                inv_w2_q8_8_q <= inv_w2_q8_8;
                min_x_q <= bbox_min_x;
                max_x_q <= bbox_max_x;
                min_y_q <= bbox_min_y;
                max_y_q <= bbox_max_y;
                cur_x <= bbox_min_x;
                cur_y <= bbox_min_y;
                area_q <= area2;
                recip_q16_16_q <= 32'sd0;
                recip_valid_q <= 1'b0;
                final_u_q8_8_q <= 16'sd0;
                final_v_q8_8_q <= 16'sd0;
                texel_addr_q <= 32'd0;
                sampled_texel_q <= 16'd0;
                state_q <= reject ? S_IDLE : S_SETUP_EDGE;
            end else if (active) begin
                if (dummy_pending && span_ready) begin
                    active <= 1'b0;
                    dummy_pending <= 1'b0;
                    state_q <= S_IDLE;
                end else begin
                    case (state_q)
                        S_IDLE: begin
                        end
                        S_SETUP_EDGE: begin
                            edge0_dx_q <= y2_q - y1_q;
                            edge0_dy_q <= x1_q - x2_q;
                            edge1_dx_q <= y0_q - y2_q;
                            edge1_dy_q <= x2_q - x0_q;
                            edge2_dx_q <= y1_q - y0_q;
                            edge2_dy_q <= x0_q - x1_q;
                            row_w0_q <= edge_value(min_x_q, min_y_q, x1_q, y1_q, x2_q, y2_q);
                            row_w1_q <= edge_value(min_x_q, min_y_q, x2_q, y2_q, x0_q, y0_q);
                            row_w2_q <= edge_value(min_x_q, min_y_q, x0_q, y0_q, x1_q, y1_q);
                            w0_q <= edge_value(min_x_q, min_y_q, x1_q, y1_q, x2_q, y2_q);
                            w1_q <= edge_value(min_x_q, min_y_q, x2_q, y2_q, x0_q, y0_q);
                            w2_q <= edge_value(min_x_q, min_y_q, x0_q, y0_q, x1_q, y1_q);
                            if (gouraud_q) begin
                                state_q <= S_SETUP_COLOR_GRAD;
                            end else if (textured_q) begin
                                state_q <= S_SETUP_UV_GRAD;
                            end else begin
                                state_q <= S_SCAN;
                            end
                        end
                        S_SETUP_COLOR_GRAD: begin
                            color_r_dx_q <= calc_grad_q8_8(color_r0_q8_8, color_r1_q8_8, color_r2_q8_8, y2_q - y1_q, y0_q - y2_q, y1_q - y0_q, area_q);
                            color_r_dy_q <= calc_grad_q8_8(color_r0_q8_8, color_r1_q8_8, color_r2_q8_8, x1_q - x2_q, x2_q - x0_q, x0_q - x1_q, area_q);
                            color_g_dx_q <= calc_grad_q8_8(color_g0_q8_8, color_g1_q8_8, color_g2_q8_8, y2_q - y1_q, y0_q - y2_q, y1_q - y0_q, area_q);
                            color_g_dy_q <= calc_grad_q8_8(color_g0_q8_8, color_g1_q8_8, color_g2_q8_8, x1_q - x2_q, x2_q - x0_q, x0_q - x1_q, area_q);
                            color_b_dx_q <= calc_grad_q8_8(color_b0_q8_8, color_b1_q8_8, color_b2_q8_8, y2_q - y1_q, y0_q - y2_q, y1_q - y0_q, area_q);
                            color_b_dy_q <= calc_grad_q8_8(color_b0_q8_8, color_b1_q8_8, color_b2_q8_8, x1_q - x2_q, x2_q - x0_q, x0_q - x1_q, area_q);
                            state_q <= S_SETUP_COLOR_START;
                        end
                        S_SETUP_COLOR_START: begin
                            row_color_r_q <= calc_start_attr_q8_8(color_r0_q8_8, color_r_dx_q, color_r_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            row_color_g_q <= calc_start_attr_q8_8(color_g0_q8_8, color_g_dx_q, color_g_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            row_color_b_q <= calc_start_attr_q8_8(color_b0_q8_8, color_b_dx_q, color_b_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            color_r_q <= calc_start_attr_q8_8(color_r0_q8_8, color_r_dx_q, color_r_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            color_g_q <= calc_start_attr_q8_8(color_g0_q8_8, color_g_dx_q, color_g_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            color_b_q <= calc_start_attr_q8_8(color_b0_q8_8, color_b_dx_q, color_b_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            if (textured_q) begin
                                state_q <= S_SETUP_UV_GRAD;
                            end else begin
                                state_q <= S_SCAN;
                            end
                        end
                        S_SETUP_UV_GRAD: begin
                            u_dx_q <= calc_grad_q8_8(u0_q8_8_q, u1_q8_8_q, u2_q8_8_q, y2_q - y1_q, y0_q - y2_q, y1_q - y0_q, area_q);
                            u_dy_q <= calc_grad_q8_8(u0_q8_8_q, u1_q8_8_q, u2_q8_8_q, x1_q - x2_q, x2_q - x0_q, x0_q - x1_q, area_q);
                            v_dx_q <= calc_grad_q8_8(v0_q8_8_q, v1_q8_8_q, v2_q8_8_q, y2_q - y1_q, y0_q - y2_q, y1_q - y0_q, area_q);
                            v_dy_q <= calc_grad_q8_8(v0_q8_8_q, v1_q8_8_q, v2_q8_8_q, x1_q - x2_q, x2_q - x0_q, x0_q - x1_q, area_q);
                            inv_w_dx_q <= calc_grad_q8_8(inv_w0_q8_8_q, inv_w1_q8_8_q, inv_w2_q8_8_q, y2_q - y1_q, y0_q - y2_q, y1_q - y0_q, area_q);
                            inv_w_dy_q <= calc_grad_q8_8(inv_w0_q8_8_q, inv_w1_q8_8_q, inv_w2_q8_8_q, x1_q - x2_q, x2_q - x0_q, x0_q - x1_q, area_q);
                            state_q <= S_SETUP_UV_START;
                        end
                        S_SETUP_UV_START: begin
                            row_u_q <= calc_start_attr_q8_8(u0_q8_8_q, u_dx_q, u_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            row_v_q <= calc_start_attr_q8_8(v0_q8_8_q, v_dx_q, v_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            row_inv_w_q <= calc_start_attr_q8_8(inv_w0_q8_8_q, inv_w_dx_q, inv_w_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            u_q <= calc_start_attr_q8_8(u0_q8_8_q, u_dx_q, u_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            v_q <= calc_start_attr_q8_8(v0_q8_8_q, v_dx_q, v_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            inv_w_q <= calc_start_attr_q8_8(inv_w0_q8_8_q, inv_w_dx_q, inv_w_dy_q, min_x_q, min_y_q, x0_q, y0_q);
                            state_q <= S_SCAN;
                        end
                        S_SCAN: begin
                            if (pixel_inside_q) begin
                                if (textured_q) begin
                                    if (perspective_q) begin
                                        u_q <= interp_attr_q8_8(w0_q, w1_q, w2_q, area_q, u0_q8_8_q, u1_q8_8_q, u2_q8_8_q);
                                        v_q <= interp_attr_q8_8(w0_q, w1_q, w2_q, area_q, v0_q8_8_q, v1_q8_8_q, v2_q8_8_q);
                                        inv_w_q <= interp_attr_q8_8(w0_q, w1_q, w2_q, area_q, inv_w0_q8_8_q, inv_w1_q8_8_q, inv_w2_q8_8_q);
                                        state_q <= S_RECIP;
                                    end else begin
                                        final_u_q8_8_q <= interp_attr_q8_8(w0_q, w1_q, w2_q, area_q, u0_q8_8_q, u1_q8_8_q, u2_q8_8_q);
                                        final_v_q8_8_q <= interp_attr_q8_8(w0_q, w1_q, w2_q, area_q, v0_q8_8_q, v1_q8_8_q, v2_q8_8_q);
                                        state_q <= S_TEXADDR;
                                    end
                                end else begin
                                    state_q <= S_EMIT_SPAN;
                                end
                            end else if (pixel_last_q) begin
                                dummy_pending <= 1'b1;
                                state_q <= S_IDLE;
                            end else if (cur_x == max_x_q) begin
                                cur_x <= min_x_q;
                                cur_y <= cur_y + 16'sd1;
                                row_w0_q <= row_w0_q + edge0_dy_q;
                                row_w1_q <= row_w1_q + edge1_dy_q;
                                row_w2_q <= row_w2_q + edge2_dy_q;
                                w0_q <= row_w0_q + edge0_dy_q;
                                w1_q <= row_w1_q + edge1_dy_q;
                                w2_q <= row_w2_q + edge2_dy_q;
                                row_color_r_q <= row_color_r_q + color_r_dy_q;
                                row_color_g_q <= row_color_g_q + color_g_dy_q;
                                row_color_b_q <= row_color_b_q + color_b_dy_q;
                                color_r_q <= row_color_r_q + color_r_dy_q;
                                color_g_q <= row_color_g_q + color_g_dy_q;
                                color_b_q <= row_color_b_q + color_b_dy_q;
                                row_u_q <= row_u_q + u_dy_q;
                                row_v_q <= row_v_q + v_dy_q;
                                row_inv_w_q <= row_inv_w_q + inv_w_dy_q;
                                u_q <= row_u_q + u_dy_q;
                                v_q <= row_v_q + v_dy_q;
                                inv_w_q <= row_inv_w_q + inv_w_dy_q;
                            end else begin
                                cur_x <= cur_x + 16'sd1;
                                w0_q <= w0_q + edge0_dx_q;
                                w1_q <= w1_q + edge1_dx_q;
                                w2_q <= w2_q + edge2_dx_q;
                                color_r_q <= color_r_q + color_r_dx_q;
                                color_g_q <= color_g_q + color_g_dx_q;
                                color_b_q <= color_b_q + color_b_dx_q;
                                u_q <= u_q + u_dx_q;
                                v_q <= v_q + v_dx_q;
                                inv_w_q <= inv_w_q + inv_w_dx_q;
                            end
                        end
                        S_RECIP: begin
                            recip_valid_q <= (inv_w_q != 32'sd0);
                            recip_q16_16_q <= reciprocal_q16_16_from_q8_8(inv_w_q);
                            state_q <= S_RECOVER;
                        end
                        S_RECOVER: begin
                            if (recip_valid_q) begin
                                final_u_q8_8_q <= recover_coord(u_q, recip_q16_16_q);
                                final_v_q8_8_q <= recover_coord(v_q, recip_q16_16_q);
                            end else begin
                                final_u_q8_8_q <= 16'sd0;
                                final_v_q8_8_q <= 16'sd0;
                            end
                            state_q <= S_TEXADDR;
                        end
                        S_TEXADDR: begin
                            texel_addr_q <= texel_addr_now;
                            state_q <= S_WAIT_AR;
                        end
                        S_WAIT_AR: begin
                            if (tex_cache_req_ready) begin
                                state_q <= S_WAIT_R;
                            end
                        end
                        S_WAIT_R: begin
                            if (tex_cache_resp_valid) begin
                                sampled_texel_q <= (tex_cache_resp_error || !tex_format_supported) ? 16'h0000
                                                                                                    : sampled_texel_now;
                                state_q <= S_HAVE_TEXEL;
                            end
                        end
                        S_HAVE_TEXEL,
                        S_EMIT_SPAN: begin
                            if (span_ready) begin
                                if (pixel_last_q) begin
                                    active <= 1'b0;
                                    state_q <= S_IDLE;
                                end else if (cur_x == max_x_q) begin
                                    cur_x <= min_x_q;
                                    cur_y <= cur_y + 16'sd1;
                                    row_w0_q <= row_w0_q + edge0_dy_q;
                                    row_w1_q <= row_w1_q + edge1_dy_q;
                                    row_w2_q <= row_w2_q + edge2_dy_q;
                                    w0_q <= row_w0_q + edge0_dy_q;
                                    w1_q <= row_w1_q + edge1_dy_q;
                                    w2_q <= row_w2_q + edge2_dy_q;
                                    row_color_r_q <= row_color_r_q + color_r_dy_q;
                                    row_color_g_q <= row_color_g_q + color_g_dy_q;
                                    row_color_b_q <= row_color_b_q + color_b_dy_q;
                                    color_r_q <= row_color_r_q + color_r_dy_q;
                                    color_g_q <= row_color_g_q + color_g_dy_q;
                                    color_b_q <= row_color_b_q + color_b_dy_q;
                                    row_u_q <= row_u_q + u_dy_q;
                                    row_v_q <= row_v_q + v_dy_q;
                                    row_inv_w_q <= row_inv_w_q + inv_w_dy_q;
                                    u_q <= row_u_q + u_dy_q;
                                    v_q <= row_v_q + v_dy_q;
                                    inv_w_q <= row_inv_w_q + inv_w_dy_q;
                                    state_q <= S_SCAN;
                                end else begin
                                    cur_x <= cur_x + 16'sd1;
                                    w0_q <= w0_q + edge0_dx_q;
                                    w1_q <= w1_q + edge1_dx_q;
                                    w2_q <= w2_q + edge2_dx_q;
                                    color_r_q <= color_r_q + color_r_dx_q;
                                    color_g_q <= color_g_q + color_g_dx_q;
                                    color_b_q <= color_b_q + color_b_dx_q;
                                    u_q <= u_q + u_dx_q;
                                    v_q <= v_q + v_dx_q;
                                    inv_w_q <= inv_w_q + inv_w_dx_q;
                                    state_q <= S_SCAN;
                                end
                            end
                        end
                        default: begin
                            active <= 1'b0;
                            state_q <= S_IDLE;
                        end
                    endcase
                end
            end
        end
    end
endmodule
