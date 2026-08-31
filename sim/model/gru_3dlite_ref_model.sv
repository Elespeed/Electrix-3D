`timescale 1ns / 1ps
`include "../../rtl/ip/gru/gru_defs.vh"

// =============================================================================
// gru_3dlite_ref_model
//
// Phase 2x1 reference model for the 3D-Lite Gouraud rasterizer.  This is a PURE
// function/task collection (docs/3dlite/phase2x1_Gouraud调试.md): no clock, no
// AXI, no DDR, no driver, no agent -- the testbench drives it directly with the
// same vertices/colours it issues to the DUT and then bit-compares the whole
// framebuffer.
//
// It is a line-for-line software port of the Lite rasterizer DATAPATH
// (rtl/ip/gru/engine_3d_lite/): the SAME 2x-signed-area edge function and
// inclusive inside test, the SAME leading-one + 64-entry reciprocal LUT, the
// SAME Q8.8 colour gradients, the SAME 48-bit start-colour accumulation, the
// SAME forward DDA, and the SAME clamp/round/RGB565-pack.  Because every step
// is integer-identical, DUT-vs-reference is bit-exact regardless of the LUT
// approximation (the shared gru_ref_model cannot be reused here: its
// apply_triangle_gouraud uses a real `numer/area2` divider, which the Lite path
// replaced with the LUT and would differ by up to ~0.5 LSB/channel).
//
// All multiplies/divides below live in this sim-only model; the synthesizable
// contract (no `/`/`%` in rtl/.../engine_3d_lite) is checked separately.
// =============================================================================

module gru_3dlite_ref_model #(
    parameter integer FRAME_W = 320,
    parameter integer FRAME_H = 240
)();
    localparam integer FRAME_PIXELS = FRAME_W * FRAME_H;

    // Reference framebuffer mirroring the DUT's FB_BASE_B render target.
    reg [15:0] frame_b [0:FRAME_PIXELS-1];

    // Debug snapshot of the most-recent apply_triangle_gouraud_lite, used by
    // report_pixel() to print the edge / colour-accumulator / LUT values at the
    // first mismatched pixel (phase2x1 调试要求).  Only written inside apply_*.
    integer dbg_min_x, dbg_min_y;
    integer dbg_area2, dbg_recip_m, dbg_shift;
    integer dbg_edge0_dx, dbg_edge1_dx, dbg_edge2_dx;
    integer dbg_edge0_dy, dbg_edge1_dy, dbg_edge2_dy;
    integer dbg_w0_init, dbg_w1_init, dbg_w2_init;     // edge values at corner
    integer dbg_crdx, dbg_crdy, dbg_cgdx, dbg_cgdy, dbg_cbdx, dbg_cbdy;
    integer dbg_start_r, dbg_start_g, dbg_start_b;     // Q8.8 colour at corner

    integer init_i;
    initial begin
        for (init_i = 0; init_i < FRAME_PIXELS; init_i = init_i + 1) begin
            frame_b[init_i] = 16'h0000;
        end
    end

    // ---------------------------------------------------------------------------
    // 8-bit colour_idx -> RGB565.  MUST match gru_colour_lut.sv / gru_ref_model
    // (3:3:2 quantised value expanded by high-bit replication).  Used for CLEAR.
    // ---------------------------------------------------------------------------
    function automatic logic [15:0] color_idx_to_rgb565(input logic [7:0] color_idx);
        begin
            color_idx_to_rgb565 = {
                color_idx[7:5], color_idx[7:6],
                color_idx[4:2], color_idx[4:2],
                color_idx[1:0], color_idx[1:0], color_idx[1]
            };
        end
    endfunction

    function automatic logic [15:0] get_pixel_b(input integer idx);
        begin
            if ((idx < 0) || (idx >= FRAME_PIXELS)) begin
                get_pixel_b = 16'h0000;
            end else begin
                get_pixel_b = frame_b[idx];
            end
        end
    endfunction

    task automatic clear_buffer_b(input logic [15:0] color565);
        integer idx;
        begin
            for (idx = 0; idx < FRAME_PIXELS; idx = idx + 1) begin
                frame_b[idx] = color565;
            end
        end
    endtask

    task automatic write_pixel_b(input integer x, input integer y, input logic [15:0] color565);
        integer idx;
        begin
            if ((x < 0) || (x >= FRAME_W) || (y < 0) || (y >= FRAME_H)) begin
                return;
            end
            idx = y * FRAME_W + x;
            frame_b[idx] = color565;
        end
    endtask

    // ---------------------------------------------------------------------------
    // 64-entry reciprocal-of-mantissa LUT (MUST match gru_lite_recip_area.sv).
    // ---------------------------------------------------------------------------
    function automatic integer recip_lut(input logic [5:0] i);
        begin
            case (i)
                6'd0:  recip_lut = 130056;
                6'd1:  recip_lut = 128070;
                6'd2:  recip_lut = 126144;
                6'd3:  recip_lut = 124276;
                6'd4:  recip_lut = 122461;
                6'd5:  recip_lut = 120699;
                6'd6:  recip_lut = 118987;
                6'd7:  recip_lut = 117323;
                6'd8:  recip_lut = 115705;
                6'd9:  recip_lut = 114131;
                6'd10: recip_lut = 112599;
                6'd11: recip_lut = 111107;
                6'd12: recip_lut = 109655;
                6'd13: recip_lut = 108240;
                6'd14: recip_lut = 106861;
                6'd15: recip_lut = 105517;
                6'd16: recip_lut = 104206;
                6'd17: recip_lut = 102928;
                6'd18: recip_lut = 101680;
                6'd19: recip_lut = 100462;
                6'd20: recip_lut = 99273;
                6'd21: recip_lut = 98112;
                6'd22: recip_lut = 96978;
                6'd23: recip_lut = 95870;
                6'd24: recip_lut = 94787;
                6'd25: recip_lut = 93727;
                6'd26: recip_lut = 92692;
                6'd27: recip_lut = 91679;
                6'd28: recip_lut = 90688;
                6'd29: recip_lut = 89718;
                6'd30: recip_lut = 88768;
                6'd31: recip_lut = 87839;
                6'd32: recip_lut = 86929;
                6'd33: recip_lut = 86037;
                6'd34: recip_lut = 85164;
                6'd35: recip_lut = 84308;
                6'd36: recip_lut = 83469;
                6'd37: recip_lut = 82646;
                6'd38: recip_lut = 81840;
                6'd39: recip_lut = 81049;
                6'd40: recip_lut = 80274;
                6'd41: recip_lut = 79513;
                6'd42: recip_lut = 78766;
                6'd43: recip_lut = 78034;
                6'd44: recip_lut = 77314;
                6'd45: recip_lut = 76608;
                6'd46: recip_lut = 75915;
                6'd47: recip_lut = 75234;
                6'd48: recip_lut = 74565;
                6'd49: recip_lut = 73908;
                6'd50: recip_lut = 73263;
                6'd51: recip_lut = 72629;
                6'd52: recip_lut = 72005;
                6'd53: recip_lut = 71392;
                6'd54: recip_lut = 70790;
                6'd55: recip_lut = 70198;
                6'd56: recip_lut = 69615;
                6'd57: recip_lut = 69042;
                6'd58: recip_lut = 68478;
                6'd59: recip_lut = 67924;
                6'd60: recip_lut = 67378;
                6'd61: recip_lut = 66841;
                6'd62: recip_lut = 66313;
                default: recip_lut = 65793;   // i == 63
            endcase
        end
    endfunction

    // Reciprocal of |area2| via leading-one + LUT (mirrors gru_lite_recip_area).
    // area2 != 0 on the Gouraud path (reject drops area2==0); returns recip_m and
    // shift = 9 + k for the caller's (numer * recip_m) >>> shift.
    task automatic recip_area(
        input  integer area2_signed,
        output integer recip_m,
        output integer shift
    );
        integer area_abs;
        integer k;
        integer norm;
        logic [5:0] idx;
        begin
            area_abs = (area2_signed < 0) ? -area2_signed : area2_signed;
            // k = floor(log2(area_abs)) == leading-one index (0..18 for area<2^19).
            k = 0;
            while (area_abs > 1) begin
                k = k + 1;
                area_abs = area_abs >> 1;
            end
            // Recompute area_abs (the loop consumed it) and normalize.
            area_abs = (area2_signed < 0) ? -area2_signed : area2_signed;
            norm = area_abs << (18 - k);
            idx = (norm >> 12);   // low 6 bits == norm[17:12] (mantissa fraction)
            recip_m = recip_lut(idx);
            shift = 9 + k;
        end
    endtask

    // Edge function E(p,a,b) = (px-ax)(by-ay) - (py-ay)(bx-ax).  Identical to
    // gru_lite_triangle_setup/raster lite_edge; reject bounds coords so the
    // plain-integer result equals the RTL's 24-bit truncated value exactly.
    function automatic integer lite_edge(
        input integer px, input integer py,
        input integer ax, input integer ay,
        input integer bx, input integer by
    );
        begin
            lite_edge = (px - ax) * (by - ay) - (py - ay) * (bx - ax);
        end
    endfunction

    // Q8.8 channel -> RGB565 width, round-half-up + saturate.  Bit-identical to
    // gru_lite_triangle_raster clamp_u5/clamp_u6 (32-bit signed `value+128`,
    // arithmetic `>>>8`, then clamp).
    function automatic logic [4:0] clamp_u5(input integer value);
        integer rounded;
        begin
            rounded = value + 128;            // 32-bit signed wrap, matches RTL
            if (rounded < 0) begin
                clamp_u5 = 5'd0;
            end else if ((rounded >>> 8) > 31) begin
                clamp_u5 = 5'd31;
            end else begin
                clamp_u5 = (rounded >> 8);    // in [0,31] here
            end
        end
    endfunction

    function automatic logic [5:0] clamp_u6(input integer value);
        integer rounded;
        begin
            rounded = value + 128;
            if (rounded < 0) begin
                clamp_u6 = 6'd0;
            end else if ((rounded >>> 8) > 63) begin
                clamp_u6 = 6'd63;
            end else begin
                clamp_u6 = (rounded >> 8);
            end
        end
    endfunction

    // ---------------------------------------------------------------------------
    // apply_triangle_gouraud_lite -- the Gouraud reference, port of the raster.
    //   vx*/vy*: vertex screen coords (integers, already in the engine's
    //            addressable range; out-of-range vertices hit the reject path).
    //   c*_rgb565: per-vertex colour.
    // Draws into frame_b with the same winding/inside/DDA/clamp as the DUT, so a
    // whole-framebuffer compare is bit-exact.
    // ---------------------------------------------------------------------------
    task automatic apply_triangle_gouraud_lite(
        input integer vx0, input integer vy0, input logic [15:0] c0_rgb565,
        input integer vx1, input integer vy1, input logic [15:0] c1_rgb565,
        input integer vx2, input integer vy2, input logic [15:0] c2_rgb565
    );
        // Geometry / reject (mirrors gru_lite_triangle_setup).
        integer area2;
        integer eff_max_x, eff_max_y;
        integer min_x, max_x, min_y, max_y;
        integer vert_oob;

        // Edge increments + accumulators.
        integer edge0_dx, edge1_dx, edge2_dx;   // dE/dx = by-ay
        integer edge0_dy, edge1_dy, edge2_dy;   // dE/dy = ax-bx
        integer row_w0, row_w1, row_w2;         // x=min_x value per row
        integer w0, w1, w2;                      // current pixel

        // Colour setup.
        integer cr0, cr1, cr2, cg0, cg1, cg2, cb0, cb1, cb2;
        integer numer_rx, numer_ry, numer_gx, numer_gy, numer_bx, numer_by;
        integer recip_m, shift;
        integer color_r_dx, color_r_dy, color_g_dx, color_g_dy, color_b_dx, color_b_dy;
        integer corner_dx0, corner_dy0;
        integer row_color_r, row_color_g, row_color_b;
        integer color_r, color_g, color_b;

        // Wide temporaries (the 48-bit start-colour products must not truncate
        // before the add -- see gru_lite_triangle_raster S_G_START / phase2x0
        // GOTCHA; integer (32-bit) context would silently wrap them).
        longint lnumer, lrecip, lprod;
        longint start_r_calc, start_g_calc, start_b_calc;

        integer x, y;
        logic [15:0] pixel565;
        bit pixel_inside;   // NOTE: 'inside' is an SV keyword -- do not use as a name
        begin
            area2 = (vx2 - vx0) * (vy1 - vy0) - (vy2 - vy0) * (vx1 - vx0);

            // eff_max = min(frame-1, 511) (span format caps each axis at 9 bits).
            eff_max_x = ((FRAME_W - 1) < 511) ? (FRAME_W - 1) : 511;
            eff_max_y = ((FRAME_H - 1) < 511) ? (FRAME_H - 1) : 511;

            vert_oob = (vx0 < 0) | (vx0 > eff_max_x) | (vy0 < 0) | (vy0 > eff_max_y) |
                       (vx1 < 0) | (vx1 > eff_max_x) | (vy1 < 0) | (vy1 > eff_max_y) |
                       (vx2 < 0) | (vx2 > eff_max_x) | (vy2 < 0) | (vy2 > eff_max_y);

            // reject -> raster emits only a terminator, framebuffer unchanged.
            if (vert_oob | (area2 == 0) | (FRAME_W == 0) | (FRAME_H == 0)) begin
                return;
            end

            // bbox = vertex min/max (reject already bounds it inside the frame).
            min_x = vx0; if (vx1 < min_x) min_x = vx1; if (vx2 < min_x) min_x = vx2;
            max_x = vx0; if (vx1 > max_x) max_x = vx1; if (vx2 > max_x) max_x = vx2;
            min_y = vy0; if (vy1 < min_y) min_y = vy1; if (vy2 < min_y) min_y = vy2;
            max_y = vy0; if (vy1 > max_y) max_y = vy1; if (vy2 > max_y) max_y = vy2;

            // Edge increments (S_SETUP_EDGE).
            edge0_dx = vy2 - vy1;  edge0_dy = vx1 - vx2;   // edge v1->v2
            edge1_dx = vy0 - vy2;  edge1_dy = vx2 - vx0;   // edge v2->v0
            edge2_dx = vy1 - vy0;  edge2_dy = vx0 - vx1;   // edge v0->v1

            // Edge initials at the bbox corner (S_SETUP_EDGE).
            row_w0 = lite_edge(min_x, min_y, vx1, vy1, vx2, vy2);
            row_w1 = lite_edge(min_x, min_y, vx2, vy2, vx0, vy0);
            row_w2 = lite_edge(min_x, min_y, vx0, vy0, vx1, vy1);
            w0 = row_w0;  w1 = row_w1;  w2 = row_w2;

            // Channel magnitudes (zero-extended signed-positive), S_G_NUMER.
            cr0 = {11'b0, c0_rgb565[15:11]}; cr1 = {11'b0, c1_rgb565[15:11]}; cr2 = {11'b0, c2_rgb565[15:11]};
            cg0 = {10'b0, c0_rgb565[10:5]};  cg1 = {10'b0, c1_rgb565[10:5]};  cg2 = {10'b0, c2_rgb565[10:5]};
            cb0 = {11'b0, c0_rgb565[4:0]};   cb1 = {11'b0, c1_rgb565[4:0]};   cb2 = {11'b0, c2_rgb565[4:0]};

            // 6 gradient numerators (S_G_NUMER): a_i = edge{i}_dx, b_i = edge{i}_dy.
            numer_rx = edge0_dx*cr0 + edge1_dx*cr1 + edge2_dx*cr2;
            numer_gx = edge0_dx*cg0 + edge1_dx*cg1 + edge2_dx*cg2;
            numer_bx = edge0_dx*cb0 + edge1_dx*cb1 + edge2_dx*cb2;
            numer_ry = edge0_dy*cr0 + edge1_dy*cr1 + edge2_dy*cr2;
            numer_gy = edge0_dy*cg0 + edge1_dy*cg1 + edge2_dy*cg2;
            numer_by = edge0_dy*cb0 + edge1_dy*cb1 + edge2_dy*cb2;

            // Shared (numer*recip_m)>>>shift, sign-folded by area2 BEFORE the >>>.
            recip_area(area2, recip_m, shift);
            lrecip = recip_m;                        // always > 0
            lnumer  = (area2 < 0) ? -numer_rx : numer_rx;  lprod = lnumer * lrecip;  color_r_dx = lprod >>> shift;
            lnumer  = (area2 < 0) ? -numer_gx : numer_gx;  lprod = lnumer * lrecip;  color_g_dx = lprod >>> shift;
            lnumer  = (area2 < 0) ? -numer_bx : numer_bx;  lprod = lnumer * lrecip;  color_b_dx = lprod >>> shift;
            lnumer  = (area2 < 0) ? -numer_ry : numer_ry;  lprod = lnumer * lrecip;  color_r_dy = lprod >>> shift;
            lnumer  = (area2 < 0) ? -numer_gy : numer_gy;  lprod = lnumer * lrecip;  color_g_dy = lprod >>> shift;
            lnumer  = (area2 < 0) ? -numer_by : numer_by;  lprod = lnumer * lrecip;  color_b_dy = lprod >>> shift;

            // Start colour at the bbox corner referenced to vertex 0 (S_G_START),
            // accumulated WIDE then stored Q8.8 [31:0] (low half) -- matches RTL.
            corner_dx0 = min_x - vx0;
            corner_dy0 = min_y - vy0;
            start_r_calc = (longint'(cr0) << 8) + longint'(color_r_dx)*corner_dx0 + longint'(color_r_dy)*corner_dy0;
            start_g_calc = (longint'(cg0) << 8) + longint'(color_g_dx)*corner_dx0 + longint'(color_g_dy)*corner_dy0;
            start_b_calc = (longint'(cb0) << 8) + longint'(color_b_dx)*corner_dx0 + longint'(color_b_dy)*corner_dy0;
            row_color_r = start_r_calc;  color_r = start_r_calc;   // truncate to 32-bit signed
            row_color_g = start_g_calc;  color_g = start_g_calc;
            row_color_b = start_b_calc;  color_b = start_b_calc;

            // Debug snapshot (linear DDA -> per-pixel w/colour are direct).
            dbg_min_x = min_x;  dbg_min_y = min_y;
            dbg_area2 = area2;  dbg_recip_m = recip_m;  dbg_shift = shift;
            dbg_edge0_dx = edge0_dx; dbg_edge1_dx = edge1_dx; dbg_edge2_dx = edge2_dx;
            dbg_edge0_dy = edge0_dy; dbg_edge1_dy = edge1_dy; dbg_edge2_dy = edge2_dy;
            dbg_w0_init = row_w0; dbg_w1_init = row_w1; dbg_w2_init = row_w2;
            dbg_crdx = color_r_dx; dbg_crdy = color_r_dy;
            dbg_cgdx = color_g_dx; dbg_cgdy = color_g_dy;
            dbg_cbdx = color_b_dx; dbg_cbdy = color_b_dy;
            dbg_start_r = color_r; dbg_start_g = color_g; dbg_start_b = color_b;

            // Forward DDA over the bbox (S_SCAN / S_EMIT_SPAN).  colour/edge hold
            // the value for the current pixel; both are stepped together, so this
            // is integer-identical to the hardware accumulation (incl. 32-bit wrap).
            for (y = min_y; y <= max_y; y = y + 1) begin
                for (x = min_x; x <= max_x; x = x + 1) begin
                    if (area2 > 0) begin
                        pixel_inside = (w0 >= 0) && (w1 >= 0) && (w2 >= 0);
                    end else begin
                        pixel_inside = (w0 <= 0) && (w1 <= 0) && (w2 <= 0);
                    end
                    if (pixel_inside) begin
                        pixel565 = {clamp_u5(color_r), clamp_u6(color_g), clamp_u5(color_b)};
                        write_pixel_b(x, y, pixel565);
                    end
                    if (x < max_x) begin
                        // +x step.
                        w0 = w0 + edge0_dx;  w1 = w1 + edge1_dx;  w2 = w2 + edge2_dx;
                        color_r = color_r + color_r_dx;
                        color_g = color_g + color_g_dx;
                        color_b = color_b + color_b_dx;
                    end else begin
                        // Row advance: seed x=min_x of the next row.
                        row_w0 = row_w0 + edge0_dy;
                        row_w1 = row_w1 + edge1_dy;
                        row_w2 = row_w2 + edge2_dy;
                        w0 = row_w0;  w1 = row_w1;  w2 = row_w2;
                        row_color_r = row_color_r + color_r_dy;
                        row_color_g = row_color_g + color_g_dy;
                        row_color_b = row_color_b + color_b_dy;
                        color_r = row_color_r;
                        color_g = row_color_g;
                        color_b = row_color_b;
                    end
                end
            end
        end
    endtask

    // Report the reference edge / colour-accumulator / LUT values at one pixel
    // of the most-recent apply_triangle_gouraud_lite, for first-mismatch debug
    // (phase2x1 调试要求).  The DDA is linear, so w(x,y) = w_init + dx*(x-min_x)
    // + dy*(y-min_y) and colour(x,y) = start + dCdx*(x-min_x) + dCdy*(y-min_y),
    // all truncated to the 32-bit signed accumulator width.
    task automatic report_pixel(input integer x, input integer y);
        longint dx, dy;
        longint lw0, lw1, lw2;
        integer ew0, ew1, ew2;
        longint lr, lg, lb;
        integer cr, cg, cb;
        begin
            dx = x - dbg_min_x;
            dy = y - dbg_min_y;
            lw0 = dbg_w0_init + dx*dbg_edge0_dx + dy*dbg_edge0_dy;  ew0 = lw0;
            lw1 = dbg_w1_init + dx*dbg_edge1_dx + dy*dbg_edge1_dy;  ew1 = lw1;
            lw2 = dbg_w2_init + dx*dbg_edge2_dx + dy*dbg_edge2_dy;  ew2 = lw2;
            lr  = dbg_start_r + dx*dbg_crdx + dy*dbg_crdy;  cr = lr;
            lg  = dbg_start_g + dx*dbg_cgdx + dy*dbg_cgdy;  cg = lg;
            lb  = dbg_start_b + dx*dbg_cbdx + dy*dbg_cbdy;  cb = lb;
            $display("[LITE_REF][DBG] pixel(%0d,%0d) area2=%0d recip_m=%0d shift=%0d | w0=%0d w1=%0d w2=%0d | cR_q8.8=%0d cG=%0d cB=%0d | packed=0x%04h",
                     x, y, dbg_area2, dbg_recip_m, dbg_shift,
                     ew0, ew1, ew2, cr, cg, cb,
                     {clamp_u5(cr), clamp_u6(cg), clamp_u5(cb)});
        end
    endtask

endmodule
