// SketchBook GRU: a BRAM-native, ordered command processor.  It deliberately
// has no AXI framebuffer address or DDR transaction ports.  Every render
// command is converted into clipped RGB332 spans and committed by
// sketch_bram_writer to the current back page.
module sketch_gru_top #(
    parameter int SRC_W = 400,
    parameter int SRC_H = 300,
    parameter int ADDR_W = $clog2((SRC_W * SRC_H) / 8),
    parameter int CMD_FIFO_DEPTH = 16,
    parameter int ASSET_WORDS = 2048,
    parameter string ASSET_INIT_FILE = "",
    parameter bit ENABLE_GOURAUD = 1'b0
) (
    input  logic              clk,
    input  logic              resetn,
    input  logic              soft_reset,
    input  logic              render_allowed,
    input  logic              target_page,
    input  logic              cmd_push_valid,
    input  logic [31:0]       cmd_push_w0,
    input  logic [31:0]       cmd_push_w1,
    input  logic [31:0]       cmd_push_w2,
    input  logic [31:0]       cmd_push_w3,
    input  logic [31:0]       cmd_push_w4,
    output logic              cmd_push_ready,
    output logic [$clog2(CMD_FIFO_DEPTH + 1)-1:0] cmd_level,
    output logic              cmd_full,
    output logic              busy,
    output logic              idle,
    output logic              frame_closed,
    output logic              present_req,
    output logic              error,
    output logic              write_attempt,
    output logic              gru_we,
    output logic              gru_page,
    output logic [ADDR_W-1:0] gru_addr,
    output logic [63:0]       gru_wdata,
    output logic [7:0]        gru_wstrb
);
    localparam int FIFO_PTR_W = (CMD_FIFO_DEPTH <= 2) ? 1 : $clog2(CMD_FIFO_DEPTH);
    localparam int FIFO_COUNT_W = $clog2(CMD_FIFO_DEPTH + 1);
    localparam logic [4:0] CMD_CLEAR         = 5'd0;
    localparam logic [4:0] CMD_DRAW_PIXEL    = 5'd1;
    localparam logic [4:0] CMD_FILL_RECT     = 5'd2;
    localparam logic [4:0] CMD_DRAW_LINE     = 5'd3;
    localparam logic [4:0] CMD_DRAW_GLYPH    = 5'd4;
    localparam logic [4:0] CMD_TRIANGLE_FLAT = 5'd5;
    localparam logic [4:0] CMD_PRESENT       = 5'd6;
    localparam logic [4:0] CMD_BLIT          = 5'd7;
    localparam logic [4:0] CMD_BLIT_ASSET    = 5'd8;
    localparam logic [4:0] CMD_TRIANGLE_GOURAUD = 5'd9;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_CLEAR,
        ST_RECT,
        ST_LINE,
        ST_GLYPH,
        ST_TRIANGLE,
        ST_BLIT,
        ST_WAIT_DONE
    } state_t;

    typedef enum logic [1:0] {
        LINE_BRESENHAM,
        LINE_HORIZONTAL,
        LINE_VERTICAL
    } line_mode_t;

    typedef enum logic [2:0] {
        GLYPH_LOAD_ROW,
        GLYPH_FIND_RUN,
        GLYPH_EMIT_RUN,
        GLYPH_NEXT_ROW,
        GLYPH_DRAIN
    } glyph_state_t;

    state_t state;
    logic [31:0] fifo_w0 [0:CMD_FIFO_DEPTH-1];
    logic [31:0] fifo_w1 [0:CMD_FIFO_DEPTH-1];
    logic [31:0] fifo_w2 [0:CMD_FIFO_DEPTH-1];
    logic [31:0] fifo_w3 [0:CMD_FIFO_DEPTH-1];
    logic [31:0] fifo_w4 [0:CMD_FIFO_DEPTH-1];
    logic [FIFO_PTR_W-1:0] wr_ptr, rd_ptr;
    logic [FIFO_COUNT_W-1:0] fifo_count;
    logic [31:0] head_w0, head_w1, head_w2, head_w3, head_w4;
    logic push_fire, pop_fire;

    logic [15:0] clear_y;
    logic [7:0] render_color;
    logic [15:0] rect_x0, rect_x1, rect_y, rect_y1;

    logic signed [17:0] line_x, line_y, line_x1, line_y1;
    logic signed [17:0] line_dx, line_dy, line_err, line_sx, line_sy;
    logic signed [17:0] line_e2, line_next_x, line_next_y, line_next_err;
    logic line_in_bounds, line_is_last;
    line_mode_t line_mode;

    logic signed [17:0] glyph_base_x, glyph_base_y;
    logic [3:0] glyph_x, glyph_y;
    logic [1:0] glyph_font;
    logic [7:0] glyph_ascii;
    logic glyph_pixel_on;
    logic [3:0] glyph_w, glyph_h;
    logic [7:0] glyph_row_bits, glyph_row_bits_q;
    logic glyph_empty;
    glyph_state_t glyph_state;
    logic [3:0] glyph_scan_x, glyph_run_start, glyph_run_len;
    logic glyph_find_found;
    logic [3:0] glyph_find_start, glyph_find_len;
    logic signed [17:0] glyph_row_py, glyph_run_x0, glyph_run_x1;
    logic glyph_run_visible;
    logic [15:0] glyph_clip_x, glyph_clip_len;

    logic tri_start, tri_gouraud, tri_busy, tri_span_valid, tri_span_ready;
    logic [63:0] tri_span_data;
    logic [15:0] tri_span_x, tri_span_y, tri_span_len;
    logic [7:0] tri_span_color;
    logic [ADDR_W-1:0] tri_span_step;
    logic tri_span_last;

    logic signed [17:0] blit_base_x, blit_base_y;
    logic [15:0] blit_w, blit_h, blit_x, blit_y;
    logic [7:0] blit_asset_id;
    logic blit_key_enable;
    logic [7:0] blit_key, blit_pixel;
    logic blit_asset_valid, blit_visible, blit_is_last;
    logic signed [17:0] blit_dst_x, blit_dst_y;
    logic [15:0] blit_src_x, blit_src_y, asset_width, asset_height, asset_stride;

    logic span_valid, span_ready, span_last;
    logic [15:0] span_x, span_y, span_len;
    logic [7:0] span_color;
    logic [ADDR_W-1:0] span_step;
    logic writer_busy, writer_done, writer_we, writer_page;
    logic [ADDR_W-1:0] writer_addr;
    logic [63:0] writer_wdata;
    logic [7:0] writer_wstrb;

    function automatic logic [ADDR_W+2:0] calc_addr_int(input integer x, input integer y);
        begin
            if (SRC_W == 400)
                calc_addr_int = (y << 8) + (y << 7) + (y << 4) + x;
            else
                calc_addr_int = y * SRC_W + x;
        end
    endfunction

    function automatic integer clamp_low(input integer value, input integer low);
        begin
            clamp_low = (value < low) ? low : value;
        end
    endfunction

    function automatic integer clamp_high(input integer value, input integer high);
        begin
            clamp_high = (value > high) ? high : value;
        end
    endfunction

    function automatic integer abs_int(input integer value);
        begin
            abs_int = (value < 0) ? -value : value;
        end
    endfunction

    function automatic integer min3(input integer a, input integer b, input integer c);
        begin
            min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
        end
    endfunction

    function automatic integer max3(input integer a, input integer b, input integer c);
        begin
            max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
        end
    endfunction

    assign head_w0 = fifo_w0[rd_ptr];
    assign head_w1 = fifo_w1[rd_ptr];
    assign head_w2 = fifo_w2[rd_ptr];
    assign head_w3 = fifo_w3[rd_ptr];
    assign head_w4 = fifo_w4[rd_ptr];
    assign cmd_level = fifo_count;
    assign cmd_full = (fifo_count == CMD_FIFO_DEPTH);
    assign cmd_push_ready = !frame_closed && render_allowed && !cmd_full;
    assign push_fire = cmd_push_valid && cmd_push_ready;
    assign pop_fire = (state == ST_IDLE) && !writer_busy && (fifo_count != '0);
    assign busy = (state != ST_IDLE) || writer_busy || (fifo_count != '0) || frame_closed;
    assign idle = !busy;
    assign write_attempt = gru_we;

    always_comb begin
        line_e2 = line_err <<< 1;
        line_next_x = line_x;
        line_next_y = line_y;
        line_next_err = line_err;
        if (line_e2 >= line_dy) begin
            line_next_err = line_next_err + line_dy;
            line_next_x = line_next_x + line_sx;
        end
        if (line_e2 <= line_dx) begin
            line_next_err = line_next_err + line_dx;
            line_next_y = line_next_y + line_sy;
        end
        line_in_bounds = (line_x >= 0) && (line_y >= 0) &&
                         (line_x < SRC_W) && (line_y < SRC_H);
        line_is_last = (line_x == line_x1) && (line_y == line_y1);
    end

    gru_font_rom u_font_rom (
        .font_id(glyph_font), .ascii(glyph_ascii), .x(glyph_x), .y(glyph_y),
        .pixel_on(glyph_pixel_on), .glyph_w(glyph_w), .glyph_h(glyph_h),
        .row_bits(glyph_row_bits), .glyph_empty(glyph_empty)
    );

    always_comb begin
        glyph_find_found = 1'b0;
        glyph_find_start = glyph_scan_x;
        glyph_find_len = '0;
        for (int glyph_ix = 0; glyph_ix < 8; glyph_ix = glyph_ix + 1) begin
            if (!glyph_find_found && (glyph_ix >= glyph_scan_x) &&
                (glyph_ix < glyph_w) && glyph_row_bits_q[glyph_ix]) begin
                glyph_find_found = 1'b1;
                glyph_find_start = glyph_ix[3:0];
                for (int glyph_jx = glyph_ix; glyph_jx < 8; glyph_jx = glyph_jx + 1) begin
                    if ((glyph_jx < glyph_w) && glyph_row_bits_q[glyph_jx] &&
                        (glyph_jx == (glyph_ix + glyph_find_len)))
                        glyph_find_len = glyph_find_len + 1'b1;
                end
            end
        end

        glyph_row_py = glyph_base_y + $signed({1'b0, glyph_y});
        glyph_run_x0 = glyph_base_x + $signed({1'b0, glyph_run_start});
        glyph_run_x1 = glyph_run_x0 + $signed({1'b0, glyph_run_len}) - 18'sd1;
        glyph_run_visible = (glyph_run_len != 0) && (glyph_row_py >= 0) &&
                            (glyph_row_py < SRC_H) && (glyph_run_x1 >= 0) &&
                            (glyph_run_x0 < SRC_W);
        glyph_clip_x = '0;
        glyph_clip_len = '0;
        if (glyph_run_visible) begin
            if (glyph_run_x0 < 0)
                glyph_clip_x = 16'd0;
            else
                glyph_clip_x = glyph_run_x0[15:0];
            if (glyph_run_x1 >= SRC_W)
                glyph_clip_len = SRC_W - glyph_clip_x;
            else
                glyph_clip_len = glyph_run_x1 - $signed({1'b0, glyph_clip_x}) + 18'sd1;
        end
    end

    always_comb begin
        blit_dst_x = blit_base_x + $signed({1'b0, blit_x});
        blit_dst_y = blit_base_y + $signed({1'b0, blit_y});
        blit_visible = blit_asset_valid && (blit_dst_x >= 0) && (blit_dst_x < SRC_W) &&
                       (blit_dst_y >= 0) && (blit_dst_y < SRC_H) &&
                       (!blit_key_enable || (blit_pixel != blit_key));
        blit_is_last = (blit_x == blit_w - 1'b1) && (blit_y == blit_h - 1'b1);
    end

    sketch_asset_rom #(.ASSET_WORDS(ASSET_WORDS), .INIT_FILE(ASSET_INIT_FILE)) u_asset_rom (
        .asset_id(blit_asset_id), .src_x(blit_src_x + blit_x), .src_y(blit_src_y + blit_y),
        .asset_valid(blit_asset_valid), .asset_width(asset_width), .asset_height(asset_height),
        .asset_stride(asset_stride), .pixel(blit_pixel)
    );

    assign tri_start = pop_fire && ((head_w0[4:0] == CMD_TRIANGLE_FLAT) ||
                                    (head_w0[4:0] == CMD_TRIANGLE_GOURAUD));
    assign tri_gouraud = (head_w0[4:0] == CMD_TRIANGLE_GOURAUD);
    sketch_triangle_lite_adapter #(.ENABLE_GOURAUD(ENABLE_GOURAUD)) u_triangle_lite (
        .clk(clk), .resetn(resetn), .clear(soft_reset), .start(tri_start), .gouraud_en(tri_gouraud),
        .x0(head_w1[15:0]), .y0(head_w1[31:16]), .x1(head_w2[15:0]), .y1(head_w2[31:16]),
        .x2(head_w3[15:0]), .y2(head_w3[31:16]), .c0_rgb332(head_w0[12:5]),
        .c1_rgb332(head_w4[7:0]), .c2_rgb332(head_w4[15:8]), .frame_w(SRC_W), .frame_h(SRC_H),
        .busy(tri_busy), .span_valid(tri_span_valid), .span_ready(tri_span_ready), .span_data(tri_span_data)
    );
    sketch_span_adapter #(.ADDR_W(ADDR_W)) u_triangle_span_adapter (
        .in_span(tri_span_data), .span_x(tri_span_x), .span_y(tri_span_y), .span_len(tri_span_len),
        .span_step(tri_span_step), .span_color(tri_span_color), .span_last(tri_span_last)
    );

    always_comb begin
        span_valid = 1'b0;
        span_x = '0;
        span_y = '0;
        span_len = '0;
        span_step = 1;
        span_color = render_color;
        span_last = 1'b0;
        case (state)
            ST_CLEAR: begin
                span_valid = 1'b1;
                span_y = clear_y;
                span_len = SRC_W;
                span_last = (clear_y == SRC_H - 1);
            end
            ST_RECT: begin
                span_valid = 1'b1;
                span_x = rect_x0;
                span_y = rect_y;
                span_len = rect_x1 - rect_x0 + 16'd1;
                span_last = (rect_y == rect_y1);
            end
            ST_LINE: begin
                case (line_mode)
                    LINE_HORIZONTAL: begin
                        span_valid = 1'b1;
                        span_x = line_x[15:0];
                        span_y = line_y[15:0];
                        span_len = line_x1 - line_x + 18'sd1;
                        span_last = 1'b1;
                    end
                    LINE_VERTICAL: begin
                        span_valid = 1'b1;
                        span_x = line_x[15:0];
                        span_y = line_y[15:0];
                        span_len = line_y1 - line_y + 18'sd1;
                        span_step = ADDR_W'(SRC_W);
                        span_last = 1'b1;
                    end
                    default: begin
                        span_valid = line_in_bounds;
                        span_x = line_x[15:0];
                        span_y = line_y[15:0];
                        span_len = 16'd1;
                        span_last = line_is_last;
                    end
                endcase
            end
            ST_GLYPH: begin
                span_valid = (glyph_state == GLYPH_EMIT_RUN) && glyph_run_visible;
                span_x = glyph_clip_x;
                span_y = glyph_row_py[15:0];
                span_len = glyph_clip_len;
                // Glyph retirement is handled by GLYPH_DRAIN, so a fully
                // clipped final run cannot strand the writer waiting for last.
                span_last = 1'b0;
            end
            ST_TRIANGLE: begin
                span_valid = tri_span_valid;
                span_x = tri_span_x;
                span_y = tri_span_y;
                span_len = tri_span_len;
                span_step = tri_span_step;
                span_color = tri_span_color;
                span_last = tri_span_last;
            end
            default: ;
        endcase
    end
    assign tri_span_ready = (state == ST_TRIANGLE) && span_ready;

    sketch_bram_writer #(.SRC_W(SRC_W), .SRC_H(SRC_H), .ADDR_W(ADDR_W)) u_writer (
        .clk(clk), .resetn(resetn), .clear(soft_reset), .target_page(target_page),
        .span_valid(span_valid), .span_ready(span_ready), .span_x(span_x), .span_y(span_y),
        .span_len(span_len), .span_step(span_step), .span_color(span_color), .span_last(span_last),
        .busy(writer_busy), .cmd_done(writer_done), .gru_we(writer_we), .gru_page(writer_page),
        .gru_addr(writer_addr), .gru_wdata(writer_wdata), .gru_wstrb(writer_wstrb)
    );

    always_comb begin
        gru_we = writer_we;
        gru_page = writer_page;
        gru_addr = writer_addr;
        gru_wdata = writer_wdata;
        gru_wstrb = writer_wstrb;
        if (state == ST_BLIT) begin
            gru_we = blit_visible;
            gru_page = target_page;
            gru_addr = calc_addr_int(blit_dst_x, blit_dst_y) >> 3;
            gru_wdata = {8{blit_pixel}};
            gru_wstrb = 8'b1 << (calc_addr_int(blit_dst_x, blit_dst_y) & 3'h7);
        end
    end

    always_ff @(posedge clk or negedge resetn) begin : main_seq
        integer sx;
        integer sy;
        integer sw;
        integer sh;
        integer ex;
        integer ey;
        integer x0i;
        integer y0i;
        integer x1i;
        integer y1i;
        integer x2i;
        integer y2i;
        integer min_x_i;
        integer max_x_i;
        integer min_y_i;
        integer max_y_i;
        integer dx_i;
        integer dy_i;
        if (!resetn) begin
            state <= ST_IDLE;
            wr_ptr <= '0;
            rd_ptr <= '0;
            fifo_count <= '0;
            clear_y <= '0;
            render_color <= '0;
            rect_x0 <= '0; rect_x1 <= '0; rect_y <= '0; rect_y1 <= '0;
            line_x <= '0; line_y <= '0; line_x1 <= '0; line_y1 <= '0;
            line_dx <= '0; line_dy <= '0; line_err <= '0; line_sx <= '0; line_sy <= '0;
            line_mode <= LINE_BRESENHAM;
            glyph_base_x <= '0; glyph_base_y <= '0; glyph_x <= '0; glyph_y <= '0;
            glyph_font <= '0; glyph_ascii <= '0;
            glyph_row_bits_q <= '0;
            glyph_state <= GLYPH_LOAD_ROW;
            glyph_scan_x <= '0; glyph_run_start <= '0; glyph_run_len <= '0;
            blit_base_x <= '0; blit_base_y <= '0; blit_w <= '0; blit_h <= '0;
            blit_x <= '0; blit_y <= '0; blit_asset_id <= '0; blit_src_x <= '0; blit_src_y <= '0;
            blit_key_enable <= 1'b0; blit_key <= '0;
            frame_closed <= 1'b0;
            present_req <= 1'b0;
            error <= 1'b0;
        end else if (soft_reset) begin
            state <= ST_IDLE;
            wr_ptr <= '0;
            rd_ptr <= '0;
            fifo_count <= '0;
            frame_closed <= 1'b0;
            present_req <= 1'b0;
            error <= 1'b0;
        end else begin
            present_req <= 1'b0;
            if (frame_closed && render_allowed)
                frame_closed <= 1'b0;

            if (push_fire) begin
                fifo_w0[wr_ptr] <= cmd_push_w0;
                fifo_w1[wr_ptr] <= cmd_push_w1;
                fifo_w2[wr_ptr] <= cmd_push_w2;
                fifo_w3[wr_ptr] <= cmd_push_w3;
                fifo_w4[wr_ptr] <= cmd_push_w4;
                if (wr_ptr == CMD_FIFO_DEPTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end
            if (pop_fire) begin
                if (rd_ptr == CMD_FIFO_DEPTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end
            case ({push_fire, pop_fire})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: ;
            endcase

            case (state)
                ST_IDLE: if (pop_fire) begin
                    render_color <= head_w0[12:5];
                    case (head_w0[4:0])
                        CMD_CLEAR: begin
                            clear_y <= '0;
                            state <= ST_CLEAR;
                        end
                        CMD_DRAW_PIXEL, CMD_FILL_RECT: begin
                            sx = $signed(head_w1[15:0]);
                            sy = $signed(head_w1[31:16]);
                            sw = (head_w0[4:0] == CMD_DRAW_PIXEL) ? 1 : head_w2[15:0];
                            sh = (head_w0[4:0] == CMD_DRAW_PIXEL) ? 1 : head_w2[31:16];
                            ex = sx + sw - 1;
                            ey = sy + sh - 1;
                            if ((sw <= 0) || (sh <= 0) || (ex < 0) || (ey < 0) ||
                                (sx >= SRC_W) || (sy >= SRC_H)) begin
                                state <= ST_IDLE;
                            end else begin
                                rect_x0 <= clamp_low(sx, 0);
                                rect_x1 <= clamp_high(ex, SRC_W - 1);
                                rect_y <= clamp_low(sy, 0);
                                rect_y1 <= clamp_high(ey, SRC_H - 1);
                                state <= ST_RECT;
                            end
                        end
                        CMD_DRAW_LINE: begin
                            x0i = $signed(head_w1[15:0]);
                            y0i = $signed(head_w1[31:16]);
                            x1i = $signed(head_w2[15:0]);
                            y1i = $signed(head_w2[31:16]);
                            if (y0i == y1i) begin
                                min_x_i = (x0i < x1i) ? x0i : x1i;
                                max_x_i = (x0i > x1i) ? x0i : x1i;
                                if ((y0i < 0) || (y0i >= SRC_H) ||
                                    (max_x_i < 0) || (min_x_i >= SRC_W)) begin
                                    state <= ST_IDLE;
                                end else begin
                                    line_x <= clamp_low(min_x_i, 0);
                                    line_x1 <= clamp_high(max_x_i, SRC_W - 1);
                                    line_y <= y0i;
                                    line_mode <= LINE_HORIZONTAL;
                                    state <= ST_LINE;
                                end
                            end else if (x0i == x1i) begin
                                min_y_i = (y0i < y1i) ? y0i : y1i;
                                max_y_i = (y0i > y1i) ? y0i : y1i;
                                if ((x0i < 0) || (x0i >= SRC_W) ||
                                    (max_y_i < 0) || (min_y_i >= SRC_H)) begin
                                    state <= ST_IDLE;
                                end else begin
                                    line_x <= x0i;
                                    line_y <= clamp_low(min_y_i, 0);
                                    line_y1 <= clamp_high(max_y_i, SRC_H - 1);
                                    line_mode <= LINE_VERTICAL;
                                    state <= ST_LINE;
                                end
                            end else begin
                                dx_i = abs_int(x1i - x0i);
                                dy_i = abs_int(y1i - y0i);
                                line_x <= x0i;
                                line_y <= y0i;
                                line_x1 <= x1i;
                                line_y1 <= y1i;
                                line_dx <= dx_i;
                                line_dy <= -dy_i;
                                line_err <= dx_i - dy_i;
                                line_sx <= (x0i < x1i) ? 1 : -1;
                                line_sy <= (y0i < y1i) ? 1 : -1;
                                line_mode <= LINE_BRESENHAM;
                                state <= ST_LINE;
                            end
                        end
                        CMD_DRAW_GLYPH: begin
                            glyph_base_x <= $signed(head_w1[15:0]);
                            glyph_base_y <= $signed(head_w1[31:16]);
                            glyph_ascii <= head_w2[7:0];
                            glyph_font <= head_w2[9:8];
                            glyph_x <= '0;
                            glyph_y <= '0;
                            glyph_state <= GLYPH_LOAD_ROW;
                            state <= ST_GLYPH;
                        end
                        CMD_TRIANGLE_FLAT, CMD_TRIANGLE_GOURAUD: state <= ST_TRIANGLE;
                        CMD_BLIT, CMD_BLIT_ASSET: begin
                            sx = $signed(head_w1[15:0]);
                            sy = $signed(head_w1[31:16]);
                            sw = (head_w0[4:0] == CMD_BLIT) ? head_w2[15:0] : head_w3[15:0];
                            sh = (head_w0[4:0] == CMD_BLIT) ? head_w2[31:16] : head_w3[31:16];
                            if ((sw <= 0) || (sh <= 0) ||
                                ((head_w0[4:0] == CMD_BLIT) && (head_w3[7:0] != 8'd0)) ||
                                ((head_w0[4:0] == CMD_BLIT_ASSET) &&
                                 ((head_w0[29:22] > 8'd1) || ((head_w2[15:0] + sw) > 32) ||
                                  ((head_w2[31:16] + sh) > 32)))) begin
                                error <= 1'b1;
                                state <= ST_IDLE;
                            end else begin
                                blit_base_x <= sx;
                                blit_base_y <= sy;
                                blit_w <= sw;
                                blit_h <= sh;
                                blit_x <= '0;
                                blit_y <= '0;
                                blit_asset_id <= (head_w0[4:0] == CMD_BLIT) ? head_w3[7:0] : head_w0[29:22];
                                blit_src_x <= (head_w0[4:0] == CMD_BLIT) ? 16'd0 : head_w2[15:0];
                                blit_src_y <= (head_w0[4:0] == CMD_BLIT) ? 16'd0 : head_w2[31:16];
                                blit_key_enable <= (head_w0[4:0] == CMD_BLIT) ? head_w3[8] : head_w0[13];
                                blit_key <= head_w0[12:5];
                                state <= ST_BLIT;
                            end
                        end
                        CMD_PRESENT: begin
                            frame_closed <= 1'b1;
                            present_req <= 1'b1;
                        end
                        default: error <= 1'b1;
                    endcase
                end
                ST_CLEAR: if (span_valid && span_ready) begin
                    if (span_last)
                        state <= ST_WAIT_DONE;
                    else
                        clear_y <= clear_y + 16'd1;
                end
                ST_RECT: if (span_valid && span_ready) begin
                    if (span_last)
                        state <= ST_WAIT_DONE;
                    else
                        rect_y <= rect_y + 16'd1;
                end
                ST_LINE: if (line_mode != LINE_BRESENHAM) begin
                    if (span_valid && span_ready)
                        state <= ST_WAIT_DONE;
                end else if (!line_in_bounds || (span_valid && span_ready)) begin
                    if (line_is_last) begin
                        if (line_in_bounds)
                            state <= ST_WAIT_DONE;
                        else
                            state <= ST_IDLE;
                    end else begin
                        line_x <= line_next_x;
                        line_y <= line_next_y;
                        line_err <= line_next_err;
                    end
                end
                ST_GLYPH: begin
                    case (glyph_state)
                        GLYPH_LOAD_ROW: begin
                            if (glyph_empty)
                                state <= ST_IDLE;
                            else begin
                                glyph_row_bits_q <= glyph_row_bits;
                                glyph_scan_x <= '0;
                                glyph_state <= GLYPH_FIND_RUN;
                            end
                        end
                        GLYPH_FIND_RUN: begin
                            if (glyph_find_found) begin
                                glyph_run_start <= glyph_find_start;
                                glyph_run_len <= glyph_find_len;
                                glyph_state <= GLYPH_EMIT_RUN;
                            end else begin
                                glyph_state <= GLYPH_NEXT_ROW;
                            end
                        end
                        GLYPH_EMIT_RUN: begin
                            if (!glyph_run_visible || (span_valid && span_ready)) begin
                                glyph_scan_x <= glyph_run_start + glyph_run_len;
                                glyph_state <= GLYPH_FIND_RUN;
                            end
                        end
                        GLYPH_NEXT_ROW: begin
                            if (glyph_y == glyph_h - 1'b1)
                                glyph_state <= GLYPH_DRAIN;
                            else begin
                                glyph_y <= glyph_y + 1'b1;
                                glyph_state <= GLYPH_LOAD_ROW;
                            end
                        end
                        GLYPH_DRAIN: if (!writer_busy)
                            state <= ST_IDLE;
                        default: glyph_state <= GLYPH_LOAD_ROW;
                    endcase
                end
                ST_TRIANGLE: if (tri_span_valid && tri_span_ready && tri_span_last)
                    state <= (tri_span_len == 0) ? ST_IDLE : ST_WAIT_DONE;
                ST_BLIT: begin
                    if (blit_is_last)
                        state <= ST_IDLE;
                    else if (blit_x == blit_w - 1'b1) begin
                        blit_x <= '0;
                        blit_y <= blit_y + 1'b1;
                    end else begin
                        blit_x <= blit_x + 1'b1;
                    end
                end
                ST_WAIT_DONE: if (writer_done)
                    state <= ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
