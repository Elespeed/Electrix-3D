`timescale 1ns / 1ps
`include "../../rtl/ip/gru/gru_defs.vh"

module gru_ref_model #(
    parameter integer FRAME_W = 80,
    parameter integer FRAME_H = 60,
    parameter [31:0]  FB_BASE_A = 32'h0000_0000,
    parameter [31:0]  FB_BASE_B = 32'h0000_2580
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        fb_base_write_valid,
    input  logic [31:0] fb_base_write_data,
    input  logic        depth_base_write_valid,
    input  logic [31:0] depth_base_write_data,
    input  logic        depth_ctrl_write_valid,
    input  logic [31:0] depth_ctrl_write_data,
    input  logic        cmd_valid,
    input  logic [31:0] cmd_w0,
    input  logic [31:0] cmd_w1,
    input  logic        ext_cmd_valid,
    input  logic [31:0] ext_cmd_w0,
    input  logic [31:0] ext_cmd_w1,
    input  logic [31:0] ext_cmd_w2,
    input  logic [31:0] ext_cmd_w3,
    input  logic [31:0] ext_cmd_w4,
    input  logic [31:0] ext_cmd_cmd_w0,
    input  logic [31:0] ext_cmd_cmd_w1
);

    localparam integer FRAME_PIXELS = FRAME_W * FRAME_H;

    reg [15:0] frame_a [0:FRAME_PIXELS-1];
    reg [15:0] frame_b [0:FRAME_PIXELS-1];
    reg [15:0] depth_buf [0:FRAME_PIXELS-1];

    logic        target_select_b;
    logic [31:0] target_fb_base;
    logic [31:0] target_depth_base;
    logic [31:0] depth_ctrl;

    function automatic [15:0] color_idx_to_rgb565(input [7:0] color_idx);
        begin
            // Keep the test oracle aligned with gru_colour_lut: command colour
            // is a 3:3:2 quantised RGB value, not a legacy palette index.
            color_idx_to_rgb565 = {
                color_idx[7:5], color_idx[7:6],
                color_idx[4:2], color_idx[4:2],
                color_idx[1:0], color_idx[1:0], color_idx[1]
            };
        end
    endfunction

    function automatic [39:0] glyph_5x7(input [7:0] ch);
        begin
            case (ch)
`include "../../rtl/ip/gru/gru_font_5x7_table.svh"
                default: glyph_5x7 = 40'h0000000000;
            endcase
        end
    endfunction

    function automatic integer ref_font_width(input [1:0] font_id);
        begin
            case (font_id)
                2'd1: ref_font_width = 5;
                2'd2: ref_font_width = 6;
                default: ref_font_width = 4;
            endcase
        end
    endfunction

    function automatic integer ref_font_height(input [1:0] font_id);
        begin
            case (font_id)
                2'd1: ref_font_height = 7;
                2'd2: ref_font_height = 8;
                default: ref_font_height = 6;
            endcase
        end
    endfunction

    function automatic bit ref_font_pixel(
        input [1:0] font_id,
        input [7:0] ascii,
        input integer gx,
        input integer gy
    );
        logic [39:0] glyph_bits_5x7;
        logic [7:0]  glyph_col;
        integer x5;
        integer y5;
        begin
            ref_font_pixel = 1'b0;
            glyph_bits_5x7 = glyph_5x7(ascii);
            glyph_col = 8'd0;
            x5 = 0;
            y5 = 0;

            case (font_id)
                2'd1: begin
                    if ((gx >= 0) && (gx < 5) && (gy >= 0) && (gy < 7)) begin
                        glyph_col = (glyph_bits_5x7 >> (gx * 8)) & 8'hff;
                        ref_font_pixel = glyph_col[gy];
                    end
                end
                2'd2: begin
                    if ((gx >= 0) && (gx < 5) && (gy >= 0) && (gy < 7)) begin
                        glyph_col = (glyph_bits_5x7 >> (gx * 8)) & 8'hff;
                        ref_font_pixel = glyph_col[gy];
                    end
                end
                default: begin
                    if ((gx >= 0) && (gx < 4) && (gy >= 0) && (gy < 6)) begin
                        x5 = (gx * 5) / 4;
                        y5 = (gy * 7) / 6;
                        glyph_col = (glyph_bits_5x7 >> (x5 * 8)) & 8'hff;
                        ref_font_pixel = glyph_col[y5];
                    end
                end
            endcase
        end
    endfunction

    function automatic bit decode_select_b(input [31:0] fb_base);
        begin
            if (fb_base == FB_BASE_B) begin
                decode_select_b = 1'b1;
            end else begin
                decode_select_b = 1'b0;
            end
        end
    endfunction

    function automatic [15:0] get_pixel565(input bit select_b, input integer idx);
        begin
            if ((idx < 0) || (idx >= FRAME_PIXELS)) begin
                get_pixel565 = 16'h0000;
            end else if (select_b) begin
                get_pixel565 = frame_b[idx];
            end else begin
                get_pixel565 = frame_a[idx];
            end
        end
    endfunction

    function automatic bit decode_addr_select_b(input [31:0] addr);
        begin
            if ((addr >= FB_BASE_B) && (addr < (FB_BASE_B + (FRAME_PIXELS * 2)))) begin
                decode_addr_select_b = 1'b1;
            end else begin
                decode_addr_select_b = 1'b0;
            end
        end
    endfunction

    function automatic integer decode_depth_addr_offset_px(input [31:0] addr);
        begin
            decode_depth_addr_offset_px = integer'((addr - target_depth_base) >> 1);
        end
    endfunction

    function automatic [15:0] get_depth(input integer idx);
        begin
            if ((idx < 0) || (idx >= FRAME_PIXELS)) begin
                get_depth = 16'hffff;
            end else begin
                get_depth = depth_buf[idx];
            end
        end
    endfunction

    function automatic integer decode_addr_base_offset_px(input [31:0] addr);
        begin
            if ((addr >= FB_BASE_B) && (addr < (FB_BASE_B + (FRAME_PIXELS * 2)))) begin
                decode_addr_base_offset_px = integer'((addr - FB_BASE_B) >> 1);
            end else begin
                decode_addr_base_offset_px = integer'((addr - FB_BASE_A) >> 1);
            end
        end
    endfunction

    task automatic clear_selected_buffer(
        input bit      select_b,
        input [15:0]   color565
    );
        integer idx;
        begin
            for (idx = 0; idx < FRAME_PIXELS; idx = idx + 1) begin
                if (select_b) begin
                    frame_b[idx] = color565;
                end else begin
                    frame_a[idx] = color565;
                end
            end
        end
    endtask

    task automatic write_pixel(
        input bit      select_b,
        input integer  x,
        input integer  y,
        input [15:0]   color565
    );
        integer idx;
        begin
            // The reference model tracks only visible framebuffer writes,
            // which matches the post-clipper architectural result.
            if ((x < 0) || (x >= FRAME_W) || (y < 0) || (y >= FRAME_H)) begin
                return;
            end
            idx = y * FRAME_W + x;
            if (select_b) begin
                frame_b[idx] = color565;
            end else begin
                frame_a[idx] = color565;
            end
        end
    endtask

    task automatic write_depth(
        input integer x,
        input integer y,
        input [15:0] depth_value
    );
        integer idx;
        begin
            if ((x < 0) || (x >= FRAME_W) || (y < 0) || (y >= FRAME_H)) begin
                return;
            end
            idx = y * FRAME_W + x;
            depth_buf[idx] = depth_value;
        end
    endtask

    task automatic apply_fill_rect(
        input bit      select_b,
        input integer  x,
        input integer  y,
        input integer  w,
        input integer  h,
        input [15:0]   color565
    );
        integer x0;
        integer y0;
        integer x1;
        integer y1;
        integer xx;
        integer yy;
        begin
            if ((w <= 0) || (h <= 0)) begin
                return;
            end

            x0 = x;
            y0 = y;
            x1 = x + w - 1;
            y1 = y + h - 1;

            if ((x1 < 0) || (y1 < 0) || (x0 >= FRAME_W) || (y0 >= FRAME_H)) begin
                return;
            end
            if (x0 < 0) x0 = 0;
            if (y0 < 0) y0 = 0;
            if (x1 >= FRAME_W) x1 = FRAME_W - 1;
            if (y1 >= FRAME_H) y1 = FRAME_H - 1;

            for (yy = y0; yy <= y1; yy = yy + 1) begin
                for (xx = x0; xx <= x1; xx = xx + 1) begin
                    write_pixel(select_b, xx, yy, color565);
                end
            end
        end
    endtask

    task automatic apply_draw_line(
        input bit      select_b,
        input integer  x0,
        input integer  y0,
        input integer  x1,
        input integer  y1,
        input [15:0]   color565
    );
        integer dx;
        integer sx;
        integer dy;
        integer sy;
        integer err;
        integer e2;
        begin
            dx = (x1 >= x0) ? (x1 - x0) : (x0 - x1);
            sx = (x0 < x1) ? 1 : -1;
            dy = -((y1 >= y0) ? (y1 - y0) : (y0 - y1));
            sy = (y0 < y1) ? 1 : -1;
            err = dx + dy;

            while (1) begin
                write_pixel(select_b, x0, y0, color565);
                if ((x0 == x1) && (y0 == y1)) begin
                    return;
                end
                e2 = err <<< 1;
                if (e2 >= dy) begin
                    err = err + dy;
                    x0 = x0 + sx;
                end
                if (e2 <= dx) begin
                    err = err + dx;
                    y0 = y0 + sy;
                end
            end
        end
    endtask

    task automatic apply_draw_glyph(
        input bit      select_b,
        input integer  x,
        input integer  y,
        input [7:0]    ascii,
        input [1:0]    font_id,
        input [15:0]   color565
    );
        integer gx;
        integer gy;
        integer px;
        integer py;
        integer gw;
        integer gh;
        begin
            gw = ref_font_width(font_id);
            gh = ref_font_height(font_id);

            for (gy = 0; gy < gh; gy = gy + 1) begin
                for (gx = 0; gx < gw; gx = gx + 1) begin
                    if (ref_font_pixel(font_id, ascii, gx, gy)) begin
                        px = x + gx;
                        py = y + gy;
                        write_pixel(select_b, px, py, color565);
                    end
                end
            end
        end
    endtask

    task automatic apply_blit_rgb565(
        input bit      dst_select_b,
        input [31:0]   src_base_addr,
        input [31:0]   src_stride_bytes,
        input integer  src_x,
        input integer  src_y,
        input integer  dst_x,
        input integer  dst_y,
        input integer  width,
        input integer  height,
        input [2:0]    src_pixel_format
    );
        integer sx0;
        integer sy0;
        integer sx1;
        integer sy1;
        integer sx;
        integer sy;
        integer src_stride_px;
        integer src_base_offset_px;
        integer src_idx;
        bit     src_select_b;
        reg [15:0] pixel565;
        begin
            if ((width <= 0) || (height <= 0)) begin
                return;
            end
            if (src_stride_bytes == 32'd0) begin
                return;
            end
            if (src_pixel_format != `GRU_PIXFMT_RGB565) begin
                return;
            end

            src_stride_px = integer'(src_stride_bytes >> 1);
            if (src_stride_px <= 0) begin
                return;
            end

            sx0 = 0;
            sy0 = 0;
            sx1 = width - 1;
            sy1 = height - 1;

            if (dst_x < 0) begin
                sx0 = -dst_x;
            end
            if (dst_y < 0) begin
                sy0 = -dst_y;
            end
            if ((dst_x + sx1) >= FRAME_W) begin
                sx1 = FRAME_W - 1 - dst_x;
            end
            if ((dst_y + sy1) >= FRAME_H) begin
                sy1 = FRAME_H - 1 - dst_y;
            end
            if ((sx0 > sx1) || (sy0 > sy1)) begin
                return;
            end

            src_select_b = decode_addr_select_b(src_base_addr);
            src_base_offset_px = decode_addr_base_offset_px(src_base_addr);

            for (sy = sy0; sy <= sy1; sy = sy + 1) begin
                for (sx = sx0; sx <= sx1; sx = sx + 1) begin
                    src_idx = src_base_offset_px +
                              ((src_y + sy) * src_stride_px) +
                              (src_x + sx);
                    pixel565 = get_pixel565(src_select_b, src_idx);
                    write_pixel(dst_select_b, dst_x + sx, dst_y + sy, pixel565);
                end
            end
        end
    endtask

    function automatic integer decode_signed_x9(input logic [8:0] value);
        begin
            decode_signed_x9 = $signed({{23{value[8]}}, value});
        end
    endfunction

    function automatic integer decode_signed_y8(input logic [7:0] value);
        begin
            decode_signed_y8 = $signed({{24{value[7]}}, value});
        end
    endfunction

    function automatic bit triangle_pixel_inside(
        input integer px,
        input integer py,
        input integer ax,
        input integer ay,
        input integer bx,
        input integer by,
        input integer cx,
        input integer cy,
        input integer area_twice
    );
        integer e0;
        integer e1;
        integer e2;
        begin
            e0 = (px - ax) * (by - ay) - (py - ay) * (bx - ax);
            e1 = (px - bx) * (cy - by) - (py - by) * (cx - bx);
            e2 = (px - cx) * (ay - cy) - (py - cy) * (ax - cx);
            if (area_twice > 0) begin
                triangle_pixel_inside = (e0 >= 0) && (e1 >= 0) && (e2 >= 0);
            end else begin
                triangle_pixel_inside = (e0 <= 0) && (e1 <= 0) && (e2 <= 0);
            end
        end
    endfunction

    task automatic apply_triangle_flat(
        input bit      select_b,
        input integer  vx0,
        input integer  vy0,
        input integer  vx1,
        input integer  vy1,
        input integer  vx2,
        input integer  vy2,
        input [15:0]   color565
    );
        integer area_twice;
        integer min_x;
        integer max_x;
        integer min_y;
        integer max_y;
        integer x;
        integer y;
        begin
            area_twice = (vx2 - vx0) * (vy1 - vy0) - (vy2 - vy0) * (vx1 - vx0);
            if (area_twice == 0) begin
                return;
            end

            min_x = vx0;
            if (vx1 < min_x) min_x = vx1;
            if (vx2 < min_x) min_x = vx2;
            max_x = vx0;
            if (vx1 > max_x) max_x = vx1;
            if (vx2 > max_x) max_x = vx2;
            min_y = vy0;
            if (vy1 < min_y) min_y = vy1;
            if (vy2 < min_y) min_y = vy2;
            max_y = vy0;
            if (vy1 > max_y) max_y = vy1;
            if (vy2 > max_y) max_y = vy2;

            if ((max_x < 0) || (max_y < 0) || (min_x >= FRAME_W) || (min_y >= FRAME_H)) begin
                return;
            end
            if (min_x < 0) min_x = 0;
            if (min_y < 0) min_y = 0;
            if (max_x >= FRAME_W) max_x = FRAME_W - 1;
            if (max_y >= FRAME_H) max_y = FRAME_H - 1;

            for (y = min_y; y <= max_y; y = y + 1) begin
                for (x = min_x; x <= max_x; x = x + 1) begin
                    if (triangle_pixel_inside(x, y, vx0, vy0, vx1, vy1, vx2, vy2, area_twice)) begin
                        write_pixel(select_b, x, y, color565);
                    end
                end
            end
        end
    endtask

    task automatic apply_clear_depth(input [15:0] depth_value);
        integer idx;
        begin
            for (idx = 0; idx < FRAME_PIXELS; idx = idx + 1) begin
                depth_buf[idx] = depth_value;
            end
        end
    endtask

    task automatic apply_triangle_z(
        input bit      select_b,
        input integer  vx0,
        input integer  vy0,
        input [15:0]   vz0,
        input integer  vx1,
        input integer  vy1,
        input [15:0]   vz1,
        input integer  vx2,
        input integer  vy2,
        input [15:0]   vz2,
        input [15:0]   color565
    );
        integer area_twice;
        integer min_x;
        integer max_x;
        integer min_y;
        integer max_y;
        integer x;
        integer y;
        integer idx;
        integer w0;
        integer w1;
        integer w2;
        integer numer;
        integer new_depth;
        bit compare_lequal;
        bit pass;
        begin
            area_twice = (vx2 - vx0) * (vy1 - vy0) - (vy2 - vy0) * (vx1 - vx0);
            if (area_twice == 0) begin
                return;
            end

            min_x = vx0;
            if (vx1 < min_x) min_x = vx1;
            if (vx2 < min_x) min_x = vx2;
            max_x = vx0;
            if (vx1 > max_x) max_x = vx1;
            if (vx2 > max_x) max_x = vx2;
            min_y = vy0;
            if (vy1 < min_y) min_y = vy1;
            if (vy2 < min_y) min_y = vy2;
            max_y = vy0;
            if (vy1 > max_y) max_y = vy1;
            if (vy2 > max_y) max_y = vy2;

            if ((max_x < 0) || (max_y < 0) || (min_x >= FRAME_W) || (min_y >= FRAME_H)) begin
                return;
            end
            if (min_x < 0) min_x = 0;
            if (min_y < 0) min_y = 0;
            if (max_x >= FRAME_W) max_x = FRAME_W - 1;
            if (max_y >= FRAME_H) max_y = FRAME_H - 1;

            compare_lequal = depth_ctrl[`GRU_DEPTH_CTRL_LEQUAL_BIT];
            for (y = min_y; y <= max_y; y = y + 1) begin
                for (x = min_x; x <= max_x; x = x + 1) begin
                    if (triangle_pixel_inside(x, y, vx0, vy0, vx1, vy1, vx2, vy2, area_twice)) begin
                        w0 = ((x - vx1) * (vy2 - vy1)) - ((y - vy1) * (vx2 - vx1));
                        w1 = ((x - vx2) * (vy0 - vy2)) - ((y - vy2) * (vx0 - vx2));
                        w2 = ((x - vx0) * (vy1 - vy0)) - ((y - vy0) * (vx1 - vx0));
                        numer = (w0 * vz0) + (w1 * vz1) + (w2 * vz2);
                        if (area_twice < 0) begin
                            numer = -numer;
                            new_depth = numer / (-area_twice);
                        end else begin
                            new_depth = numer / area_twice;
                        end

                        idx = y * FRAME_W + x;
                        pass = 1'b1;
                        if (depth_ctrl[`GRU_DEPTH_CTRL_ENABLE_BIT]) begin
                            if (compare_lequal) begin
                                pass = (new_depth <= depth_buf[idx]);
                            end else begin
                                pass = (new_depth < depth_buf[idx]);
                            end
                        end

                        if (pass) begin
                            if (depth_ctrl[`GRU_DEPTH_CTRL_WRITE_BIT]) begin
                                depth_buf[idx] = new_depth[15:0];
                            end
                            write_pixel(select_b, x, y, color565);
                        end
                    end
                end
            end
        end
    endtask

    function automatic [5:0] interp_channel(
        input integer w0,
        input integer w1,
        input integer w2,
        input integer area_twice,
        input integer v0,
        input integer v1,
        input integer v2
    );
        integer numer;
        integer denom;
        integer value;
        begin
            numer = (w0 * v0) + (w1 * v1) + (w2 * v2);
            denom = area_twice;
            if (denom < 0) begin
                numer = -numer;
                denom = -denom;
            end
            if (denom == 0) begin
                value = 0;
            end else begin
                value = numer / denom;
            end

            if (value < 0) begin
                interp_channel = 6'd0;
            end else if (value > 63) begin
                interp_channel = 6'd63;
            end else begin
                interp_channel = value[5:0];
            end
        end
    endfunction

    function automatic [15:0] interp_rgb565(
        input integer area_twice,
        input integer w0,
        input integer w1,
        input integer w2,
        input [15:0] c0_rgb565,
        input [15:0] c1_rgb565,
        input [15:0] c2_rgb565
    );
        reg [5:0] r;
        reg [5:0] g;
        reg [5:0] b;
        begin
            r = interp_channel(w0, w1, w2, area_twice, c0_rgb565[15:11], c1_rgb565[15:11], c2_rgb565[15:11]);
            g = interp_channel(w0, w1, w2, area_twice, c0_rgb565[10:5],  c1_rgb565[10:5],  c2_rgb565[10:5]);
            b = interp_channel(w0, w1, w2, area_twice, c0_rgb565[4:0],   c1_rgb565[4:0],   c2_rgb565[4:0]);
            interp_rgb565 = {r[4:0], g, b[4:0]};
        end
    endfunction

    task automatic apply_triangle_gouraud(
        input bit      select_b,
        input integer  vx0,
        input integer  vy0,
        input [15:0]   c0_rgb565,
        input integer  vx1,
        input integer  vy1,
        input [15:0]   c1_rgb565,
        input integer  vx2,
        input integer  vy2,
        input [15:0]   c2_rgb565
    );
        integer area_twice;
        integer min_x;
        integer max_x;
        integer min_y;
        integer max_y;
        integer x;
        integer y;
        integer w0;
        integer w1;
        integer w2;
        reg [15:0] pixel565;
        begin
            area_twice = (vx2 - vx0) * (vy1 - vy0) - (vy2 - vy0) * (vx1 - vx0);
            if (area_twice == 0) begin
                return;
            end

            min_x = vx0;
            if (vx1 < min_x) min_x = vx1;
            if (vx2 < min_x) min_x = vx2;
            max_x = vx0;
            if (vx1 > max_x) max_x = vx1;
            if (vx2 > max_x) max_x = vx2;
            min_y = vy0;
            if (vy1 < min_y) min_y = vy1;
            if (vy2 < min_y) min_y = vy2;
            max_y = vy0;
            if (vy1 > max_y) max_y = vy1;
            if (vy2 > max_y) max_y = vy2;

            if ((max_x < 0) || (max_y < 0) || (min_x >= FRAME_W) || (min_y >= FRAME_H)) begin
                return;
            end
            if (min_x < 0) min_x = 0;
            if (min_y < 0) min_y = 0;
            if (max_x >= FRAME_W) max_x = FRAME_W - 1;
            if (max_y >= FRAME_H) max_y = FRAME_H - 1;

            for (y = min_y; y <= max_y; y = y + 1) begin
                for (x = min_x; x <= max_x; x = x + 1) begin
                    if (triangle_pixel_inside(x, y, vx0, vy0, vx1, vy1, vx2, vy2, area_twice)) begin
                        w0 = ((x - vx1) * (vy2 - vy1)) - ((y - vy1) * (vx2 - vx1));
                        w1 = ((x - vx2) * (vy0 - vy2)) - ((y - vy2) * (vx0 - vx2));
                        w2 = ((x - vx0) * (vy1 - vy0)) - ((y - vy0) * (vx1 - vx0));
                        pixel565 = interp_rgb565(area_twice, w0, w1, w2, c0_rgb565, c1_rgb565, c2_rgb565);
                        write_pixel(select_b, x, y, pixel565);
                    end
                end
            end
        end
    endtask

    task automatic apply_cmd(
        input bit      select_b,
        input [31:0]   w0,
        input [31:0]   w1
    );
        reg [4:0]  opcode;
        reg [7:0]  color_idx;
        reg [1:0]  font_id;
        reg [8:0]  x0;
        reg [7:0]  y0;
        reg [8:0]  x1;
        reg [7:0]  y1;
        reg [7:0]  ascii;
        reg [15:0] color565;
        begin
            opcode    = w0[`GRU_CMD0_OPCODE_MSB:`GRU_CMD0_OPCODE_LSB];
            color_idx = w0[`GRU_CMD0_COLOR_MSB:`GRU_CMD0_COLOR_LSB];
            font_id   = w0[`GRU_CMD0_FONT_MSB:`GRU_CMD0_FONT_LSB];
            x0        = w0[`GRU_CMD0_X0_MSB:`GRU_CMD0_X0_LSB];
            y0        = w0[`GRU_CMD0_Y0_MSB:`GRU_CMD0_Y0_LSB];
            x1        = w1[`GRU_CMD1_X1_MSB:`GRU_CMD1_X1_LSB];
            y1        = w1[`GRU_CMD1_Y1_MSB:`GRU_CMD1_Y1_LSB];
            ascii     = w1[`GRU_CMD1_ASCII_MSB:`GRU_CMD1_ASCII_LSB];
            color565  = color_idx_to_rgb565(color_idx);

            case (opcode)
                `GRU_OP_CLEAR: begin
                    clear_selected_buffer(select_b, color565);
                end
                `GRU_OP_FILL_RECT: begin
                    apply_fill_rect(
                        select_b,
                        integer'(x0),
                        integer'(y0),
                        integer'(x1) - integer'(x0) + 1,
                        integer'(y1) - integer'(y0) + 1,
                        color565
                    );
                end
                `GRU_OP_DRAW_LINE: begin
                    apply_draw_line(select_b, integer'(x0), integer'(y0), integer'(x1), integer'(y1), color565);
                end
                `GRU_OP_DRAW_GLYPH: begin
                    apply_draw_glyph(select_b, integer'(x0), integer'(y0), ascii, font_id, color565);
                end
                `GRU_OP_CLEAR_DEPTH: begin
                    apply_clear_depth(w1[15:0]);
                end
                default: begin
                end
            endcase
        end
    endtask

    task automatic apply_ext_cmd(
        input bit      select_b,
        input [31:0]   cmd_w0,
        input [31:0]   cmd_w1,
        input [31:0]   ext_w0,
        input [31:0]   ext_w1,
        input [31:0]   ext_w2,
        input [31:0]   ext_w3,
        input [31:0]   ext_w4
    );
        reg [4:0] opcode;
        reg [15:0] width;
        reg [15:0] height;
        reg [15:0] src_x;
        reg [15:0] src_y;
        reg [15:0] dst_x;
        reg [15:0] dst_y;
        reg [2:0]  src_pixel_format;
        integer tri_x0;
        integer tri_y0;
        integer tri_x1;
        integer tri_y1;
        integer tri_x2;
        integer tri_y2;
        reg [15:0] tri_z0;
        reg [15:0] tri_z1;
        reg [15:0] tri_z2;
        reg [15:0] tri_c0;
        reg [15:0] tri_c1;
        reg [15:0] tri_c2;
        reg [15:0] color565;
        begin
            opcode = cmd_w0[`GRU_CMD0_OPCODE_MSB:`GRU_CMD0_OPCODE_LSB];
            width = cmd_w1[15:0];
            height = cmd_w1[31:16];
            src_x = ext_w2[15:0];
            src_y = ext_w2[31:16];
            dst_x = ext_w3[15:0];
            dst_y = ext_w3[31:16];
            src_pixel_format = ext_w4[2:0];
            tri_x0 = decode_signed_x9(cmd_w0[`GRU_CMD0_X0_MSB:`GRU_CMD0_X0_LSB]);
            tri_y0 = decode_signed_y8(cmd_w0[`GRU_CMD0_Y0_MSB:`GRU_CMD0_Y0_LSB]);
            tri_x1 = decode_signed_x9(cmd_w1[`GRU_CMD1_X1_MSB:`GRU_CMD1_X1_LSB]);
            tri_y1 = decode_signed_y8(cmd_w1[`GRU_CMD1_Y1_MSB:`GRU_CMD1_Y1_LSB]);
            tri_x2 = decode_signed_x9(ext_w0[8:0]);
            tri_y2 = decode_signed_y8(ext_w0[16:9]);
            tri_z0 = ext_w1[15:0];
            tri_z1 = ext_w1[31:16];
            tri_z2 = ext_w2[15:0];
            tri_c0 = ext_w1[15:0];
            tri_c1 = ext_w2[15:0];
            tri_c2 = ext_w3[15:0];
            color565 = color_idx_to_rgb565(cmd_w0[`GRU_CMD0_COLOR_MSB:`GRU_CMD0_COLOR_LSB]);

            case (opcode)
                `GRU_OP_BLIT: begin
                    apply_blit_rgb565(
                        select_b,
                        ext_w0,
                        ext_w1,
                        integer'(src_x),
                        integer'(src_y),
                        integer'(dst_x),
                        integer'(dst_y),
                        integer'(width),
                        integer'(height),
                        src_pixel_format
                    );
                end
                `GRU_OP_TRIANGLE_FLAT: begin
                    apply_triangle_flat(
                        select_b,
                        tri_x0, tri_y0,
                        tri_x1, tri_y1,
                        tri_x2, tri_y2,
                        color565
                    );
                end
                `GRU_OP_TRIANGLE_Z: begin
                    apply_triangle_z(
                        select_b,
                        tri_x0, tri_y0, tri_z0,
                        tri_x1, tri_y1, tri_z1,
                        tri_x2, tri_y2, tri_z2,
                        color565
                    );
                end
                `GRU_OP_TRIANGLE_GOURAUD: begin
                    apply_triangle_gouraud(
                        select_b,
                        tri_x0, tri_y0, tri_c0,
                        tri_x1, tri_y1, tri_c1,
                        tri_x2, tri_y2, tri_c2
                    );
                end
                default: begin
                end
            endcase
        end
    endtask

    integer idx;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            target_select_b = 1'b0;
            target_fb_base  = FB_BASE_A;
            target_depth_base = 32'd0;
            depth_ctrl = 32'd0;
            for (idx = 0; idx < FRAME_PIXELS; idx = idx + 1) begin
                frame_a[idx] = 16'h0000;
                frame_b[idx] = 16'h0000;
                depth_buf[idx] = 16'hffff;
            end
        end else begin
            if (fb_base_write_valid) begin
                target_fb_base  = fb_base_write_data;
                target_select_b = decode_select_b(fb_base_write_data);
            end
            if (depth_base_write_valid) begin
                target_depth_base = depth_base_write_data;
            end
            if (depth_ctrl_write_valid) begin
                depth_ctrl = depth_ctrl_write_data;
            end
            if (cmd_valid) begin
                apply_cmd(target_select_b, cmd_w0, cmd_w1);
            end
            if (ext_cmd_valid) begin
                apply_ext_cmd(target_select_b,
                              ext_cmd_cmd_w0,
                              ext_cmd_cmd_w1,
                              ext_cmd_w0,
                              ext_cmd_w1,
                              ext_cmd_w2,
                              ext_cmd_w3,
                              ext_cmd_w4);
            end
        end
    end

endmodule
