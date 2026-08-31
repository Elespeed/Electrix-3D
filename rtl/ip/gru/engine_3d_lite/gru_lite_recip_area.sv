`include "gru_defs.vh"

// gru_lite_recip_area
// ----------------------------------------------------------------------------
// 3D Lite Gouraud setup: reciprocal of the triangle's 2x signed area WITHOUT a
// divider (Phase 2x0).  This replaces the single per-triangle `numerator/area2`
// division that the Full-3D engine (engine_3d/gru_triangle_raster.sv) infers as a
// synthesizable `/`.  Lite is forbidden from inferring a divider, so the division
// is rewritten as:
//
//   area2_abs = |area2| = 2^k * m,   m in [1,2),   k = leading-one index (0..18).
//   1/area2_abs = (1/m) * 2^-k.
//
//   1/m is taken from a small 64-entry LUT indexed by the top 6 fractional bits
//   of m.  After leading-one normalization (norm = area2_abs << (18-k), so the
//   leading one sits at bit 18) the index is simply norm[17:12].
//
//   The table stores  recip_m[idx] = round(2^17 / (1 + (idx+0.5)/64)).
//   The caller (gru_lite_triangle_raster, S_G_GRAD) then computes each colour
//   gradient as
//       grad_q8_8 = (numer_signed * recip_m) >>> shift ,   shift = 9 + k
//   using its shared setup multiplier -- see docs/3dlite/数值格式.md for the full
//   derivation, the table, and the worst-case error.
//
// This module is PURE COMBINATIONAL: leading-one detector + 64-entry LUT.  No
// clock, no divider, no multiply.  reject (gru_lite_triangle_setup) guarantees
// area2 != 0 for any triangle that reaches Gouraud colour setup, so k is always
// well defined; the area2==0 fallback (k=0, idx=0) only affects the rejected
// degenerate path and never reaches the framebuffer.
//
// Worst-case table error vs ideal 1/m is 0.775% (max at the m->1 end of the
// table), which after the full Gouraud interpolation is < 0.5 LSB on every
// channel (green, range 0..63, is the tightest: 63 * 0.00775 = 0.488 LSB).  The
// Phase 2x1 reference model uses the SAME table, so DUT-vs-reference is bit-exact
// regardless of this approximation.
// ----------------------------------------------------------------------------
module gru_lite_recip_area (
    input  logic signed [23:0] area2,
    output logic        [16:0] recip_m,   // ~ round(2^17 / m), m in [1,2); always > 0
    output logic        [4:0]  shift      // = 9 + k; caller does (P >>> shift)
);
    logic [23:0] area_abs;
    logic [4:0]  k;            // leading-one index of area_abs, 0..18
    logic [42:0] norm;         // area_abs << (18-k); leading one lands at bit 18
    logic [5:0]  idx;          // = norm[17:12], the 6 fractional bits of m

    assign area_abs = area2[23] ? ($unsigned(-area2)) : $unsigned(area2);

    // Leading-one index: highest set bit (MSB-first scan).  area2 != 0 on the
    // Gouraud path, so exactly one bit wins; area_abs==0 leaves k=0 (harmless,
    // rejected case).
    always_comb begin
        k = 5'd0;
        for (int i = 23; i >= 0; i--) begin
            if (area_abs[i] && (k == 5'd0)) begin
                k = i[4:0];
            end
        end
    end

    // Left shift only (18-k is in [0,18], always >= 0 since area_abs < 2^19).
    assign norm = {19'd0, area_abs} << (18 - k);
    assign idx  = norm[17:12];

    assign recip_m = recip_lut(idx);
    assign shift   = 5'd9 + k;

    // 64-entry reciprocal-of-mantissa table (see header for the formula).
    // Verified: entries are strictly decreasing, in [65793, 130056], 17-bit.
    function automatic logic [16:0] recip_lut (input logic [5:0] i);
        case (i)
            6'd0:  recip_lut = 17'd130056;
            6'd1:  recip_lut = 17'd128070;
            6'd2:  recip_lut = 17'd126144;
            6'd3:  recip_lut = 17'd124276;
            6'd4:  recip_lut = 17'd122461;
            6'd5:  recip_lut = 17'd120699;
            6'd6:  recip_lut = 17'd118987;
            6'd7:  recip_lut = 17'd117323;
            6'd8:  recip_lut = 17'd115705;
            6'd9:  recip_lut = 17'd114131;
            6'd10: recip_lut = 17'd112599;
            6'd11: recip_lut = 17'd111107;
            6'd12: recip_lut = 17'd109655;
            6'd13: recip_lut = 17'd108240;
            6'd14: recip_lut = 17'd106861;
            6'd15: recip_lut = 17'd105517;
            6'd16: recip_lut = 17'd104206;
            6'd17: recip_lut = 17'd102928;
            6'd18: recip_lut = 17'd101680;
            6'd19: recip_lut = 17'd100462;
            6'd20: recip_lut = 17'd99273;
            6'd21: recip_lut = 17'd98112;
            6'd22: recip_lut = 17'd96978;
            6'd23: recip_lut = 17'd95870;
            6'd24: recip_lut = 17'd94787;
            6'd25: recip_lut = 17'd93727;
            6'd26: recip_lut = 17'd92692;
            6'd27: recip_lut = 17'd91679;
            6'd28: recip_lut = 17'd90688;
            6'd29: recip_lut = 17'd89718;
            6'd30: recip_lut = 17'd88768;
            6'd31: recip_lut = 17'd87839;
            6'd32: recip_lut = 17'd86929;
            6'd33: recip_lut = 17'd86037;
            6'd34: recip_lut = 17'd85164;
            6'd35: recip_lut = 17'd84308;
            6'd36: recip_lut = 17'd83469;
            6'd37: recip_lut = 17'd82646;
            6'd38: recip_lut = 17'd81840;
            6'd39: recip_lut = 17'd81049;
            6'd40: recip_lut = 17'd80274;
            6'd41: recip_lut = 17'd79513;
            6'd42: recip_lut = 17'd78766;
            6'd43: recip_lut = 17'd78034;
            6'd44: recip_lut = 17'd77314;
            6'd45: recip_lut = 17'd76608;
            6'd46: recip_lut = 17'd75915;
            6'd47: recip_lut = 17'd75234;
            6'd48: recip_lut = 17'd74565;
            6'd49: recip_lut = 17'd73908;
            6'd50: recip_lut = 17'd73263;
            6'd51: recip_lut = 17'd72629;
            6'd52: recip_lut = 17'd72005;
            6'd53: recip_lut = 17'd71392;
            6'd54: recip_lut = 17'd70790;
            6'd55: recip_lut = 17'd70198;
            6'd56: recip_lut = 17'd69615;
            6'd57: recip_lut = 17'd69042;
            6'd58: recip_lut = 17'd68478;
            6'd59: recip_lut = 17'd67924;
            6'd60: recip_lut = 17'd67378;
            6'd61: recip_lut = 17'd66841;
            6'd62: recip_lut = 17'd66313;
            default: recip_lut = 17'd65793;   // i == 63
        endcase
    endfunction
endmodule
