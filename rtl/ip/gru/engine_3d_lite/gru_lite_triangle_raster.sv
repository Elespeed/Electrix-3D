`include "gru_defs.vh"

// gru_lite_triangle_raster
// ----------------------------------------------------------------------------
// 3D Lite triangle rasterizer (Phase 1x0 flat + Phase 2x0 Gouraud).  Incremental
// edge-function DDA over the triangle's bounding box, emitting one len=1 RGB565
// span per covered pixel into the existing span -> clipper -> FIFO -> arbiter ->
// gru_axi_writer path.
//
// FLAT (Phase 1x0):  colour is a register constant -> per-pixel cost is adds.
// GOURAUD (Phase 2x0): per-vertex RGB565 is interpolated by a SECOND incremental
//   DDA (one per R/G/B channel).  No divider is inferred: the per-triangle
//   `numerator/area2` the Full-3D raster uses is replaced by
//     area2 -> leading-one normalize -> 64-entry reciprocal LUT
//            -> shared setup multiplier (numer * recip_m) >>> shift
//   (gru_lite_recip_area.sv + the S_G_* setup states below).  See
//   docs/3dlite/数值格式.md for the full fixed-point spec and worst-case error.
//
// Per-pixel colour path (the Phase 2x0 algorithm restriction) is EXACTLY:
//     r/g/b += dC/dx            (S_SCAN/S_EMIT_SPAN +x step)
//     row_color += dC/dy        (row advance)
//     clamp + round + RGB565 pack
//   i.e. additions only -- NO multiply, NO divide, NO `%` in the pixel loop.
//   All multiplies live in the one-shot setup states (S_G_NUMER / S_G_GRAD /
//   S_G_START), run once per triangle.
//
// Edge function (same as gru_lite_triangle_setup.lite_edge):
//   E(p, a, b) = (px-ax)(by-ay) - (py-ay)(bx-ax)
//   w0 = E(p, v1, v2),  w1 = E(p, v2, v0),  w2 = E(p, v0, v1),  w0+w1+w2 = area2.
// Inside test adapts to winding (inclusive, NO top-left rule -- matches the flat
// path and the Phase 2x1 reference model, so shared/overlap edges fill
// identically and command order decides the winner).
//
// ---------------------------- bit-width proof ------------------------------
// reject (computed in setup) guarantees every vertex AND bbox pixel lies in the
// engine's addressable range [0, eff_max_x] x [0, eff_max_y], eff_max =
// min(frame-1, 511).  |area2| <= 2*511*479 = 489538 < 2^19, so the 24-bit signed
// edge accumulators never overflow (3 guard bits).  Colour accumulators are
// signed [31:0] Q8.8 (see 数值格式.md); they are wide enough that the only
// overflow possible is on pathological near-zero-area slivers, where the final
// clamp saturates -- and the reference model uses the identical width, so DUT
// and reference stay bit-exact even then.
// ---------------------------------------------------------------------------
module gru_lite_triangle_raster #(
    // Set by a front end that does not need Gouraud.  A parameter (rather than
    // a runtime enable) lets synthesis remove all colour-gradient hardware.
    parameter bit ENABLE_GOURAUD = 1'b1,
    // SketchBook selects this mode so its triangle path stays RGB332 end to end.
    // The default preserves the shared GRU's existing RGB565 ABI.
    parameter bit RGB332_MODE = 1'b0
) (
    input  logic                       clk,
    input  logic                       rstn,
    input  logic                       clr,
    input  logic                       start,          // single-cycle launch
    input  logic [`GRU_SEQ_W-1:0]      seq_id,
    input  logic [15:0]                flat_rgb565,    // constant fill colour (flat)
    input  logic                       gouraud_en,     // 1 = interpolate c0/c1/c2
    input  logic [15:0]                c0_rgb565,      // vertex 0 colour
    input  logic [15:0]                c1_rgb565,      // vertex 1 colour
    input  logic [15:0]                c2_rgb565,      // vertex 2 colour
    input  logic signed [10:0]         x0, input logic signed [9:0]  y0,
    input  logic signed [10:0]         x1, input logic signed [9:0]  y1,
    input  logic signed [10:0]         x2, input logic signed [9:0]  y2,
    input  logic signed [10:0]         bbox_min_x, input logic signed [10:0] bbox_max_x,
    input  logic signed [9:0]          bbox_min_y, input logic signed [9:0]  bbox_max_y,
    input  logic signed [23:0]         area2,
    input  logic                       reject,
    output logic                       busy,
    output logic                       span_valid,
    input  logic                       span_ready,
    output logic [63:0]                span_data
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_SETUP_EDGE,   // edge dE/dx, dE/dy + bbox-corner edge initials
        S_G_NUMER,      // Gouraud: 6 gradient numerators (combinational dot prod)
        S_G_GRAD,       // Gouraud: shared (numer*recip_m)>>>shift, 6 steps
        S_G_START,      // Gouraud: start colour at bbox corner
        S_SCAN,         // evaluate inside / step DDA
        S_EMIT_SPAN     // hold span until span_ready, then step DDA
    } state_t;

    function automatic logic signed [23:0] lite_edge(
        input logic signed [10:0] px,
        input logic signed [9:0]  py,
        input logic signed [10:0] ax,
        input logic signed [9:0]  ay,
        input logic signed [10:0] bx,
        input logic signed [9:0]  by
    );
        logic signed [12:0] px_e, ax_e, bx_e;
        logic signed [11:0] py_e, ay_e, by_e;
        logic signed [12:0] dx_a, dx_b;
        logic signed [11:0] dy_a, dy_b;
        logic signed [25:0] t1, t2;
        begin
            px_e = px;  ax_e = ax;  bx_e = bx;
            py_e = py;  ay_e = ay;  by_e = by;
            dx_a = px_e - ax_e;
            dy_a = py_e - ay_e;
            dx_b = bx_e - ax_e;
            dy_b = by_e - ay_e;
            t1 = dx_a * dy_b;
            t2 = dy_a * dx_b;
            lite_edge = t1 - t2;
        end
    endfunction

    // Round-to-nearest + saturate a Q8.8 channel value to its RGB565 width.
    // (value + 128) >>> 8 rounds half-up; clamp then catches out-of-range
    // gradients.  The reference model uses the identical expression.
    function automatic logic [4:0] clamp_u5(input logic signed [31:0] value_q8_8);
        logic signed [31:0] rounded;
        begin
            rounded = value_q8_8 + 32'sd128;
            if (rounded < 0)              clamp_u5 = 5'd0;
            else if ((rounded >>> 8) > 31) clamp_u5 = 5'd31;
            else                          clamp_u5 = rounded[12:8];
        end
    endfunction
    function automatic logic [5:0] clamp_u6(input logic signed [31:0] value_q8_8);
        logic signed [31:0] rounded;
        begin
            rounded = value_q8_8 + 32'sd128;
            if (rounded < 0)              clamp_u6 = 6'd0;
            else if ((rounded >>> 8) > 63) clamp_u6 = 6'd63;
            else                          clamp_u6 = rounded[13:8];
        end
    endfunction
    function automatic logic [2:0] clamp_u3(input logic signed [31:0] value_q8_8);
        logic signed [31:0] rounded;
        begin
            rounded = value_q8_8 + 32'sd128;
            if (rounded < 0)             clamp_u3 = 3'd0;
            else if ((rounded >>> 8) > 7) clamp_u3 = 3'd7;
            else                         clamp_u3 = rounded[10:8];
        end
    endfunction
    function automatic logic [1:0] clamp_u2(input logic signed [31:0] value_q8_8);
        logic signed [31:0] rounded;
        begin
            rounded = value_q8_8 + 32'sd128;
            if (rounded < 0)             clamp_u2 = 2'd0;
            else if ((rounded >>> 8) > 3) clamp_u2 = 2'd3;
            else                         clamp_u2 = rounded[9:8];
        end
    endfunction

    // Latched command/geometry.
    logic [`GRU_SEQ_W-1:0] seq_q;
    logic [15:0]           flat_rgb565_q;
    logic                  gouraud_q;
    logic [15:0]           c0_q, c1_q, c2_q;
    logic signed [10:0]    x0_q, x1_q, x2_q;
    logic signed [9:0]     y0_q, y1_q, y2_q;
    logic signed [10:0]    min_x_q, max_x_q;
    logic signed [9:0]     min_y_q, max_y_q;
    logic signed [23:0]    area_q;

    // Edge increments and accumulators (per the proof, 24-bit never overflows).
    logic signed [9:0]     edge0_dx_q, edge1_dx_q, edge2_dx_q;  // dE/dx = by-ay
    logic signed [10:0]    edge0_dy_q, edge1_dy_q, edge2_dy_q;  // dE/dy = ax-bx
    logic signed [23:0]    row_w0_q, row_w1_q, row_w2_q;        // x=min_x value per row
    logic signed [23:0]    w0_q, w1_q, w2_q;                     // current pixel

    // ---- Gouraud colour state (Q8.8 signed; see 数值格式.md) -----------------
    // Edge dE/dx (a_i) and dE/dy (b_i) double as the barycentric-weight
    // gradients, so the colour numerators reuse edge{0,1,2}_{dx,dy}_q directly.
    logic signed [31:0]    numer_rx_q, numer_ry_q;  // R gradient numerators (sign-folded)
    logic signed [31:0]    numer_gx_q, numer_gy_q;  // G
    logic signed [31:0]    numer_bx_q, numer_by_q;  // B
    logic signed [31:0]    color_r_dx_q, color_r_dy_q;  // dC/dx, dC/dy (Q8.8)
    logic signed [31:0]    color_g_dx_q, color_g_dy_q;
    logic signed [31:0]    color_b_dx_q, color_b_dy_q;
    logic signed [31:0]    row_color_r_q, row_color_g_q, row_color_b_q;
    logic signed [31:0]    color_r_q, color_g_q, color_b_q;
    logic [2:0]            gcnt_q;                   // S_G_GRAD step 0..5

    logic signed [10:0]    cur_x;
    logic signed [9:0]     cur_y;
    logic                  active;
    logic                  dummy_pending;   // emit one len=0,last=1 terminator
    state_t                state_q;

    // Reciprocal of |area2| via leading-one + LUT (no divider).
    logic [16:0]           recip_m;
    logic [4:0]            recip_shift;
    gru_lite_recip_area u_recip (
        .area2   (area_q),
        .recip_m (recip_m),
        .shift   (recip_shift)
    );

    // ---- Shared setup multiplier (S_G_GRAD): one (numer*recip_m)>>>shift ----
    // per step; gcnt_q selects which of the 6 numerators feeds it.  This is the
    // only multiplier the reciprocal path uses -- the "shared DSP / multi-cycle
    // multiply" the Phase 2x0 spec calls for.
    logic signed [31:0]    gnumer_mux;
    logic signed [31:0]    gnumer_s;       // sign-folded by area2 winding
    logic signed [49:0]    gprod;          // numer(18b) * recip_m(17b) max ~2^35
    always_comb begin
        case (gcnt_q)
            3'd0: gnumer_mux = numer_rx_q;
            3'd1: gnumer_mux = numer_gx_q;
            3'd2: gnumer_mux = numer_bx_q;
            3'd3: gnumer_mux = numer_ry_q;
            3'd4: gnumer_mux = numer_gy_q;
            default: gnumer_mux = numer_by_q;  // 5
        endcase
        // Fold the area2 sign into the numerator BEFORE the >>> (floor): this
        // makes grad == floor(numer/area2 * 2^8) for both windings, matching the
        // reference model exactly (see 数值格式.md).
        gnumer_s  = area_q[23] ? -gnumer_mux : gnumer_mux;
        gprod     = gnumer_s * $signed({1'b0, recip_m});   // recip_m always > 0
    end

    // Combinational scan decisions.
    logic pixel_inside;
    logic pixel_last;
    always_comb begin
        if (area_q > 0) begin
            pixel_inside = (w0_q >= 0) && (w1_q >= 0) && (w2_q >= 0);
        end else if (area_q < 0) begin
            pixel_inside = (w0_q <= 0) && (w1_q <= 0) && (w2_q <= 0);
        end else begin
            pixel_inside = 1'b0;   // area2==0 (degenerate) -> never inside
        end
        pixel_last = (cur_x == max_x_q) && (cur_y == max_y_q);
    end

    // Span assembly.  x/y narrowed to the 9-bit span fields (exact: reject bounds
    // them to <= 511).  Colour = computed Gouraud pixel colour, or the flat
    // constant.  A terminator (dummy) span carries len=0, last=1 so the writer
    // protocol completes even when the triangle covers zero pixels.
    logic [15:0] pixel_color;
    always_comb begin
        pixel_color = RGB332_MODE ? {8'd0, clamp_u3(color_r_q), clamp_u3(color_g_q), clamp_u2(color_b_q)} :
                                    {clamp_u5(color_r_q), clamp_u6(color_g_q), clamp_u5(color_b_q)};
        span_data = '0;
        span_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB]   = seq_q;
        span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB]       = cur_y[8:0];
        span_data[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB]       = cur_x[8:0];
        span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB]   = dummy_pending ? 10'd0 : 10'd1;
        span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] =
            dummy_pending ? 16'd0 :
            (gouraud_q    ? pixel_color : flat_rgb565_q);
        span_data[`GRU_SPAN_LAST_BIT]                     = dummy_pending ? 1'b1 : pixel_last;
    end

    assign busy       = active;
    assign span_valid = active && (dummy_pending || (state_q == S_EMIT_SPAN));

    // ---- Gouraud numerator dot products (combinational, latched in S_G_NUMER).
    // numer_x(ch) = a0*C0 + a1*C1 + a2*C2 with a_i = edge{i}_dx_q (dE/dx),
    // numer_y(ch) = b0*C0 + b1*C1 + b2*C2 with b_i = edge{i}_dy_q (dE/dy).
    // Channels are zero-extended to signed-positive; the area2 sign is folded in
    // later (gnumer_s), so these numerators use raw magnitudes.
    logic signed [15:0] cr0_s, cr1_s, cr2_s;
    logic signed [15:0] cg0_s, cg1_s, cg2_s;
    logic signed [15:0] cb0_s, cb1_s, cb2_s;
    always_comb begin
        if (RGB332_MODE) begin
            cr0_s = $signed({13'b0, c0_q[7:5]}); cr1_s = $signed({13'b0, c1_q[7:5]}); cr2_s = $signed({13'b0, c2_q[7:5]});
            cg0_s = $signed({13'b0, c0_q[4:2]}); cg1_s = $signed({13'b0, c1_q[4:2]}); cg2_s = $signed({13'b0, c2_q[4:2]});
            cb0_s = $signed({14'b0, c0_q[1:0]}); cb1_s = $signed({14'b0, c1_q[1:0]}); cb2_s = $signed({14'b0, c2_q[1:0]});
        end else begin
            cr0_s = $signed({11'b0, c0_q[15:11]}); cr1_s = $signed({11'b0, c1_q[15:11]}); cr2_s = $signed({11'b0, c2_q[15:11]});
            cg0_s = $signed({10'b0, c0_q[10:5]});  cg1_s = $signed({10'b0, c1_q[10:5]});  cg2_s = $signed({10'b0, c2_q[10:5]});
            cb0_s = $signed({11'b0, c0_q[4:0]});   cb1_s = $signed({11'b0, c1_q[4:0]});   cb2_s = $signed({11'b0, c2_q[4:0]});
        end
    end

    // Start colour at the bbox corner, computed in a WIDE accumulator so the
    // grad*(corner-v0) products never truncate before the add (a 32-bit
    // assignment context would silently wrap them; the [31:0] store then takes
    // the low half, matching the longint reference model bit-for-bit).  Max
    // product width ~ (31-bit grad) * (11-bit delta) = 42 bits -> [47:0] is safe.
    logic signed [11:0] corner_dx0, corner_dy0;
    logic signed [47:0] start_r_calc, start_g_calc, start_b_calc;
    always_comb begin
        corner_dx0 = min_x_q - x0_q;
        corner_dy0 = min_y_q - y0_q;
        start_r_calc = (cr0_s <<< 8) + color_r_dx_q*corner_dx0 + color_r_dy_q*corner_dy0;
        start_g_calc = (cg0_s <<< 8) + color_g_dx_q*corner_dx0 + color_g_dy_q*corner_dy0;
        start_b_calc = (cb0_s <<< 8) + color_b_dx_q*corner_dx0 + color_b_dy_q*corner_dy0;
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            seq_q <= '0;
            flat_rgb565_q <= '0;
            gouraud_q <= 1'b0;
            c0_q <= '0; c1_q <= '0; c2_q <= '0;
            x0_q <= '0; y0_q <= '0; x1_q <= '0; y1_q <= '0; x2_q <= '0; y2_q <= '0;
            min_x_q <= '0; max_x_q <= '0; min_y_q <= '0; max_y_q <= '0;
            area_q <= '0;
            edge0_dx_q <= '0; edge1_dx_q <= '0; edge2_dx_q <= '0;
            edge0_dy_q <= '0; edge1_dy_q <= '0; edge2_dy_q <= '0;
            row_w0_q <= '0; row_w1_q <= '0; row_w2_q <= '0;
            w0_q <= '0; w1_q <= '0; w2_q <= '0;
            numer_rx_q <= '0; numer_ry_q <= '0;
            numer_gx_q <= '0; numer_gy_q <= '0;
            numer_bx_q <= '0; numer_by_q <= '0;
            color_r_dx_q <= '0; color_r_dy_q <= '0;
            color_g_dx_q <= '0; color_g_dy_q <= '0;
            color_b_dx_q <= '0; color_b_dy_q <= '0;
            row_color_r_q <= '0; row_color_g_q <= '0; row_color_b_q <= '0;
            color_r_q <= '0; color_g_q <= '0; color_b_q <= '0;
            gcnt_q <= '0;
            cur_x <= '0; cur_y <= '0;
            state_q <= S_IDLE;
        end else if (clr) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            state_q <= S_IDLE;
        end else begin
            if (start) begin
                active <= 1'b1;
                dummy_pending <= reject;
                seq_q <= seq_id;
                flat_rgb565_q <= flat_rgb565;
                gouraud_q <= ENABLE_GOURAUD && gouraud_en;
                c0_q <= c0_rgb565; c1_q <= c1_rgb565; c2_q <= c2_rgb565;
                x0_q <= x0; y0_q <= y0; x1_q <= x1; y1_q <= y1; x2_q <= x2; y2_q <= y2;
                min_x_q <= bbox_min_x; max_x_q <= bbox_max_x;
                min_y_q <= bbox_min_y; max_y_q <= bbox_max_y;
                area_q <= area2;
                cur_x <= bbox_min_x;
                cur_y <= bbox_min_y;
                gcnt_q <= '0;
                state_q <= reject ? S_IDLE : S_SETUP_EDGE;
            end else if (active) begin
                // Terminator (reject, or last bbox pixel was outside): emit one
                // len=0,last=1 span and finish.
                if (dummy_pending && span_ready) begin
                    active <= 1'b0;
                    dummy_pending <= 1'b0;
                    state_q <= S_IDLE;
                end else begin
                    case (state_q)
                        S_IDLE: begin
                        end
                        S_SETUP_EDGE: begin
                            edge0_dx_q <= y2_q - y1_q;  edge0_dy_q <= x1_q - x2_q;
                            edge1_dx_q <= y0_q - y2_q;  edge1_dy_q <= x2_q - x0_q;
                            edge2_dx_q <= y1_q - y0_q;  edge2_dy_q <= x0_q - x1_q;
                            row_w0_q <= lite_edge(min_x_q, min_y_q, x1_q, y1_q, x2_q, y2_q);
                            row_w1_q <= lite_edge(min_x_q, min_y_q, x2_q, y2_q, x0_q, y0_q);
                            row_w2_q <= lite_edge(min_x_q, min_y_q, x0_q, y0_q, x1_q, y1_q);
                            w0_q     <= lite_edge(min_x_q, min_y_q, x1_q, y1_q, x2_q, y2_q);
                            w1_q     <= lite_edge(min_x_q, min_y_q, x2_q, y2_q, x0_q, y0_q);
                            w2_q     <= lite_edge(min_x_q, min_y_q, x0_q, y0_q, x1_q, y1_q);
                            // Flat skips colour setup entirely; Gouraud computes
                            // the 6 colour gradients next.
                            state_q  <= gouraud_q ? S_G_NUMER : S_SCAN;
                        end
                        S_G_NUMER: begin
                            // 6 gradient numerators (channel * pixel), one shot.
                            // Reuses the edge coefficients as barycentric weight
                            // gradients (a_i = edge{i}_dx, b_i = edge{i}_dy).
                            numer_rx_q <= edge0_dx_q*cr0_s + edge1_dx_q*cr1_s + edge2_dx_q*cr2_s;
                            numer_gx_q <= edge0_dx_q*cg0_s + edge1_dx_q*cg1_s + edge2_dx_q*cg2_s;
                            numer_bx_q <= edge0_dx_q*cb0_s + edge1_dx_q*cb1_s + edge2_dx_q*cb2_s;
                            numer_ry_q <= edge0_dy_q*cr0_s + edge1_dy_q*cr1_s + edge2_dy_q*cr2_s;
                            numer_gy_q <= edge0_dy_q*cg0_s + edge1_dy_q*cg1_s + edge2_dy_q*cg2_s;
                            numer_by_q <= edge0_dy_q*cb0_s + edge1_dy_q*cb1_s + edge2_dy_q*cb2_s;
                            gcnt_q <= '0;
                            state_q <= S_G_GRAD;
                        end
                        S_G_GRAD: begin
                            // Shared multiplier: one gradient per cycle, selected
                            // by gcnt_q.  grad_q8_8 = (numer*recip_m) >>> shift.
                            // Order matches gnumer_mux: rx,gx,bx,ry,gy,by.
                            case (gcnt_q)
                                3'd0: color_r_dx_q <= gprod >>> recip_shift;
                                3'd1: color_g_dx_q <= gprod >>> recip_shift;
                                3'd2: color_b_dx_q <= gprod >>> recip_shift;
                                3'd3: color_r_dy_q <= gprod >>> recip_shift;
                                3'd4: color_g_dy_q <= gprod >>> recip_shift;
                                default: color_b_dy_q <= gprod >>> recip_shift;
                            endcase
                            if (gcnt_q == 3'd5) begin
                                gcnt_q <= '0;
                                state_q <= S_G_START;
                            end else begin
                                gcnt_q <= gcnt_q + 3'd1;
                            end
                        end
                        S_G_START: begin
                            // Colour at the bbox corner (min_x,min_y), referenced
                            // to vertex 0.  row_color_* and color_* both seed to
                            // this value so the DDA starts at the corner.  Computed
                            // wide (start_*_calc, [47:0]) and stored Q8.8 [31:0]
                            // (low half), matching the reference model exactly.
                            row_color_r_q <= start_r_calc[31:0];
                            row_color_g_q <= start_g_calc[31:0];
                            row_color_b_q <= start_b_calc[31:0];
                            color_r_q     <= start_r_calc[31:0];
                            color_g_q     <= start_g_calc[31:0];
                            color_b_q     <= start_b_calc[31:0];
                            state_q <= S_SCAN;
                        end
                        S_SCAN: begin
                            if (pixel_inside) begin
                                state_q <= S_EMIT_SPAN;
                            end else if (pixel_last) begin
                                // No pixel left to draw: finish via a terminator.
                                dummy_pending <= 1'b1;
                                state_q <= S_IDLE;
                            end else if (cur_x == max_x_q) begin
                                // Advance to the next row.
                                cur_x <= min_x_q;
                                cur_y <= cur_y + 9'sd1;
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
                            end else begin
                                cur_x <= cur_x + 11'sd1;
                                w0_q <= w0_q + edge0_dx_q;
                                w1_q <= w1_q + edge1_dx_q;
                                w2_q <= w2_q + edge2_dx_q;
                                color_r_q <= color_r_q + color_r_dx_q;
                                color_g_q <= color_g_q + color_g_dx_q;
                                color_b_q <= color_b_q + color_b_dx_q;
                            end
                        end
                        S_EMIT_SPAN: begin
                            if (span_ready) begin
                                if (pixel_last) begin
                                    active <= 1'b0;
                                    state_q <= S_IDLE;
                                end else if (cur_x == max_x_q) begin
                                    cur_x <= min_x_q;
                                    cur_y <= cur_y + 9'sd1;
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
                                    state_q <= S_SCAN;
                                end else begin
                                    cur_x <= cur_x + 11'sd1;
                                    w0_q <= w0_q + edge0_dx_q;
                                    w1_q <= w1_q + edge1_dx_q;
                                    w2_q <= w2_q + edge2_dx_q;
                                    color_r_q <= color_r_q + color_r_dx_q;
                                    color_g_q <= color_g_q + color_g_dx_q;
                                    color_b_q <= color_b_q + color_b_dx_q;
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
