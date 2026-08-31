`timescale 1ns / 1ps

module sketch_book_tb;
    localparam integer OUT_W = 800;
    localparam integer OUT_H = 600;
    localparam integer FRAME_PIXELS = OUT_W * OUT_H;
    // The expanded regression deliberately observes several complete 800x600
    // frames (including a display-disable/re-enable interval).
    localparam integer TIMEOUT_CYCLES = 40_000_000;
    localparam [4:0] CMD_CLEAR = 0;
    localparam [4:0] CMD_PIXEL = 1;
    localparam [4:0] CMD_RECT = 2;
    localparam [4:0] CMD_LINE = 3;
    localparam [4:0] CMD_GLYPH = 4;
    localparam [4:0] CMD_TRIANGLE = 5;
    localparam [4:0] CMD_PRESENT = 6;
    localparam [4:0] CMD_BLIT = 7;
    localparam [4:0] CMD_BLIT_ASSET = 8;
    localparam [4:0] CMD_TRIANGLE_GOURAUD = 9;
    localparam [15:0] UI_BG = 16'h18c3;
    localparam [15:0] UI_PANEL = 16'h2945;
    localparam [15:0] UI_ACTIVITY = 16'h001f;
    localparam [15:0] SPRITE_KEY = 16'hf81f;
    localparam integer BENCH_UI_RENDER_BASELINE = 223661;
    localparam integer BENCH_UI_RENDER_CAP = 246028;
    localparam integer BENCH_UI_PRESENT_BASELINE = 499137;
    // Packed rendering reaches PRESENT at a different phase of the 800x600
    // timing generator.  A swap may therefore wait almost one full frame.
    localparam integer BENCH_UI_PRESENT_CAP = 800000;
    localparam integer BENCH_STATIC_BLIT_BASELINE = 3087;
    localparam integer BENCH_STATIC_BLIT_CAP = 3396;
    localparam integer BENCH_MOVE_RENDER_BASELINE = 2095;
    localparam integer BENCH_MOVE_RENDER_CAP = 2305;
    localparam integer BENCH_MOVE_PRESENT_BASELINE = 690545;
    localparam integer BENCH_MOVE_PRESENT_CAP = 800000;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic mmio_valid = 1'b0;
    logic mmio_we = 1'b0;
    logic [31:0] mmio_addr = '0;
    logic [31:0] mmio_wdata = '0;
    logic [31:0] mmio_rdata;
    logic mmio_ready;
    logic dvi_clk, dvi_hs, dvi_vs, dvi_de;
    logic [7:0] dvi_d;
    logic irq_done, err_active_write;
    logic done = 1'b0;

    integer de_cycle_count;
    integer front_change_count;
    logic front_idx_q;
    logic frame_boundary_q;
    logic [31:0] frame_counter_q;
    logic [31:0] swap_counter_q;
    logic glyph_perf_enabled = 1'b0;
    integer glyph_perf_cycles;
    integer glyph_render_cycles;
    integer glyph_span_accept_count;
    integer glyph_pixel_write_count;
    logic line_perf_enabled = 1'b0;
    integer line_span_accept_count;
    integer line_pixel_write_count;
    integer bench_cycle;
    integer bench_ui_render, bench_ui_present, bench_static_blit;
    integer bench_move_total, bench_move_max_render, bench_move_max_present;

    always #10 clk = ~clk;
    initial begin
        #200;
        resetn = 1'b1;
    end

    sketch_book_top dut (
        .clk(clk), .resetn(resetn), .mmio_valid(mmio_valid), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready), .dvi_clk(dvi_clk), .dvi_hs(dvi_hs), .dvi_vs(dvi_vs),
        .dvi_de(dvi_de), .dvi_d(dvi_d), .irq_done(irq_done), .err_active_write(err_active_write)
    );

    dvi_monitor_800x600 #(
        .FRAME_DUMP_LIMIT(0),
        .TESTCASE("sketch_book_tb"),
        .OUTPUT_ROOT("../../../sim/frame_output")
    ) mon (
        .video_clk(dvi_clk), .resetn(resetn),
        .video_red({dvi_d[7:5], dvi_d[7:6]}),
        .video_green({dvi_d[4:2], dvi_d[4:2]}),
        .video_blue({dvi_d[1:0], dvi_d[1:0], dvi_d[1]}),
        .video_hsync(dvi_hs), .video_vsync(dvi_vs), .video_de(dvi_de)
    );

    function automatic logic [7:0] color_to_rgb332(input logic [15:0] color);
        color_to_rgb332 = {color[15:13], color[10:8], color[4:3]};
    endfunction

    task automatic mmio_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            mmio_valid = 1'b1;
            mmio_we = 1'b1;
            mmio_addr = addr;
            mmio_wdata = data;
            @(posedge clk);
            if (!mmio_ready)
                $fatal(1, "[sketch_book_tb] MMIO write was not accepted at %h", addr);
            @(negedge clk);
            mmio_valid = 1'b0;
            mmio_we = 1'b0;
            mmio_addr = '0;
            mmio_wdata = '0;
        end
    endtask

    task automatic mmio_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(negedge clk);
            mmio_valid = 1'b1;
            mmio_we = 1'b0;
            mmio_addr = addr;
            @(posedge clk);
            if (!mmio_ready)
                $fatal(1, "[sketch_book_tb] MMIO read was not accepted at %h", addr);
            data = mmio_rdata;
            @(negedge clk);
            mmio_valid = 1'b0;
            mmio_addr = '0;
        end
    endtask

    task automatic submit_cmd(
        input logic [4:0] opcode,
        input logic [15:0] color,
        input logic [31:0] w1,
        input logic [31:0] w2,
        input logic [31:0] w3
    );
        begin
            mmio_write(32'h008, {19'd0, color_to_rgb332(color), opcode});
            mmio_write(32'h00c, w1);
            mmio_write(32'h010, w2);
            mmio_write(32'h014, w3);
            // A swap releases frame_closed on the following GRU edge.  Normal
            // producers wait through that one-cycle transition; the dedicated
            // expect_push_backpressured task below still verifies rejection.
            while (!dut.u_gru.cmd_push_ready)
                @(posedge clk);
            mmio_write(32'h018, 32'd1);
        end
    endtask

    task automatic clear(input logic [15:0] color);
        submit_cmd(CMD_CLEAR, color, '0, '0, '0);
    endtask

    task automatic pixel(input integer x, input integer y, input logic [15:0] color);
        submit_cmd(CMD_PIXEL, color, {y[15:0], x[15:0]}, '0, '0);
    endtask

    task automatic rect(
        input integer x, input integer y, input integer w, input integer h, input logic [15:0] color
    );
        submit_cmd(CMD_RECT, color, {y[15:0], x[15:0]}, {h[15:0], w[15:0]}, '0);
    endtask

    task automatic line(
        input integer x0, input integer y0, input integer x1, input integer y1, input logic [15:0] color
    );
        submit_cmd(CMD_LINE, color, {y0[15:0], x0[15:0]}, {y1[15:0], x1[15:0]}, '0);
    endtask

    task automatic glyph(
        input integer x, input integer y, input [7:0] ascii, input [1:0] font, input logic [15:0] color
    );
        submit_cmd(CMD_GLYPH, color, {y[15:0], x[15:0]}, {22'd0, font, ascii}, '0);
    endtask

    task automatic triangle(
        input integer x0, input integer y0, input integer x1, input integer y1,
        input integer x2, input integer y2, input logic [15:0] color
    );
        submit_cmd(CMD_TRIANGLE, color, {y0[15:0], x0[15:0]},
                   {y1[15:0], x1[15:0]}, {y2[15:0], x2[15:0]});
    endtask

    task automatic triangle_gouraud(
        input integer x0, input integer y0, input logic [15:0] c0,
        input integer x1, input integer y1, input logic [15:0] c1,
        input integer x2, input integer y2, input logic [15:0] c2
    );
        begin
            mmio_write(32'h02c, {16'd0, color_to_rgb332(c2), color_to_rgb332(c1)});
            submit_cmd(CMD_TRIANGLE_GOURAUD, c0, {y0[15:0], x0[15:0]},
                       {y1[15:0], x1[15:0]}, {y2[15:0], x2[15:0]});
        end
    endtask

    task automatic blit_asset(
        input integer dst_x, input integer dst_y, input integer src_x, input integer src_y,
        input integer width, input integer height, input logic key_enable, input logic [15:0] key
    );
        begin
            mmio_write(32'h008, {2'd0, 8'd1, 8'd0, key_enable, color_to_rgb332(key), CMD_BLIT_ASSET});
            mmio_write(32'h00c, {dst_y[15:0], dst_x[15:0]});
            mmio_write(32'h010, {src_y[15:0], src_x[15:0]});
            mmio_write(32'h014, {height[15:0], width[15:0]});
            mmio_write(32'h02c, '0);
            while (!dut.u_gru.cmd_push_ready)
                @(posedge clk);
            mmio_write(32'h018, 32'd1);
        end
    endtask

    task automatic present;
        submit_cmd(CMD_PRESENT, '0, '0, '0, '0);
    endtask

    task automatic blit_cat(input integer x, input integer y);
        submit_cmd(CMD_BLIT, SPRITE_KEY, {y[15:0], x[15:0]}, {16'd32, 16'd32}, 32'h0000_0100);
    endtask

    task automatic draw_text(
        input integer x, input integer y, input string text, input logic [15:0] color
    );
        integer text_i;
        begin
            for (text_i = 0; text_i < text.len(); text_i = text_i + 1)
                glyph(x + text_i * 6, y, text.getc(text_i), 2'd1, color);
        end
    endtask

    task automatic draw_ui_base;
        begin
            clear(UI_BG);
            rect(8, 8, 384, 28, 16'h07ff);
            rect(12, 42, 112, 150, UI_PANEL);
            rect(132, 42, 256, 62, 16'h39e7);
            rect(132, 112, 256, 80, UI_PANEL);
            rect(16, 54, 104, 22, 16'h07e0);
            rect(16, 82, 104, 22, 16'hf81f);
            rect(16, 110, 104, 22, 16'hffe0);
            rect(16, 138, 104, 22, 16'h07ff);
            rect(8, 232, 384, 60, UI_ACTIVITY);
            line(132, 104, 387, 104, 16'h7bef);
            line(132, 146, 387, 146, 16'h7bef);
            draw_text(18, 18, "SKETCHBOOK UI BENCH", 16'h0000);
            draw_text(28, 61, "START", 16'h0000);
            draw_text(28, 89, "TOOLS", 16'h0000);
            draw_text(28, 117, "ABOUT", 16'h0000);
            draw_text(28, 145, "RESET", 16'h0000);
            draw_text(142, 52, "SYSTEM STATUS: READY", 16'hffff);
            draw_text(142, 76, "RGB332 BRAM GRAPHICS", 16'hffff);
            draw_text(142, 122, "DRAW, TEXT, TRIANGLES", 16'hffff);
            draw_text(142, 138, "DOUBLE BUFFERED OUTPUT", 16'hffff);
            draw_text(18, 242, "CAT PLAYGROUND - BLIT ANIMATION", 16'hffff);
        end
    endtask

    task automatic wait_gru_idle;
        integer attempt;
        logic [31:0] status;
        begin
            for (attempt = 0; attempt < 300_000; attempt = attempt + 1) begin
                mmio_read(32'h004, status);
                if (status[1])
                    return;
            end
            $fatal(1, "[sketch_book_tb] GRU did not become idle");
        end
    endtask

    task automatic expect_pixel(
        input integer x, input integer y,
        input integer expected_r, input integer expected_g, input integer expected_b,
        input [8*64-1:0] label
    );
        integer index;
        begin
            index = y * OUT_W + x;
            if ((mon.captured_frame_r[index] != expected_r) ||
                (mon.captured_frame_g[index] != expected_g) ||
                (mon.captured_frame_b[index] != expected_b)) begin
                $fatal(1, "[sketch_book_tb] %0s at (%0d,%0d): got %0d,%0d,%0d expected %0d,%0d,%0d",
                       label, x, y, mon.captured_frame_r[index], mon.captured_frame_g[index],
                       mon.captured_frame_b[index], expected_r, expected_g, expected_b);
            end
        end
    endtask

    task automatic expect_push_backpressured;
        begin
            @(negedge clk);
            mmio_valid = 1'b1;
            mmio_we = 1'b1;
            mmio_addr = 32'h018;
            mmio_wdata = 32'd1;
            @(posedge clk);
            if (mmio_ready)
                $fatal(1, "[sketch_book_tb] CMD_PUSH accepted while FIFO/frame was closed");
            @(negedge clk);
            mmio_valid = 1'b0;
            mmio_we = 1'b0;
            mmio_addr = '0;
            mmio_wdata = '0;
        end
    endtask

    task automatic present_and_capture(
        input logic [31:0] expected_swap_count,
        input integer expected_front_changes,
        input [8*40-1:0] label
    );
        integer captured_before;
        begin
            captured_before = mon.captured_frame_id;
            present();
            wait(dut.swap_counter == expected_swap_count);
            // Give the front-index monitor its nonblocking update.  The DVI
            // monitor can finish the frame that was already in flight at the
            // swap edge, so skip that capture and inspect the next full one.
            @(posedge clk);
            #1;
            if (front_change_count != expected_front_changes)
                $fatal(1, "[sketch_book_tb] %0s front changes=%0d expected=%0d",
                       label, front_change_count, expected_front_changes);
            wait(mon.captured_frame_id > captured_before + 1);
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            de_cycle_count <= 0;
            front_change_count <= 0;
            front_idx_q <= 1'b0;
            frame_boundary_q <= 1'b0;
            frame_counter_q <= '0;
            swap_counter_q <= '0;
        end else begin
            // frame_counter and swap_counter are registered by frame_ctrl on
            // the prior edge, hence their expected events are delayed by one
            // monitor cycle.  This catches double increments as well as a
            // counter mutation outside its owning event.
            if (dut.frame_counter != frame_counter_q + frame_boundary_q)
                $fatal(1, "[sketch_book_tb] frame_counter changed incorrectly: got=%0d prev=%0d boundary=%0b",
                       dut.frame_counter, frame_counter_q, frame_boundary_q);
            if (dut.swap_counter != swap_counter_q) begin
                if (!dut.swap_done || (dut.swap_counter != swap_counter_q + 1'b1))
                    $fatal(1, "[sketch_book_tb] swap_counter changed incorrectly: got=%0d prev=%0d swap_done=%0b",
                           dut.swap_counter, swap_counter_q, dut.swap_done);
            end
            // Disabling timing can cut a frame short; discard that partial
            // DE count so the first re-enabled frame is checked independently.
            if (!dut.display_enable)
                de_cycle_count <= 0;
            else if (dvi_de)
                de_cycle_count <= de_cycle_count + 1;
            if (dut.front_idx != front_idx_q) begin
                if (!frame_boundary_q)
                    $fatal(1, "[sketch_book_tb] front_idx changed away from frame boundary");
                front_change_count <= front_change_count + 1;
            end
            if (dut.frame_boundary) begin
                if (de_cycle_count != FRAME_PIXELS)
                    $fatal(1, "[sketch_book_tb] DE cycles=%0d expected=%0d", de_cycle_count, FRAME_PIXELS);
                de_cycle_count <= 0;
            end
            front_idx_q <= dut.front_idx;
            frame_boundary_q <= dut.frame_boundary;
            frame_counter_q <= dut.frame_counter;
            swap_counter_q <= dut.swap_counter;
        end
    end

    always @(posedge clk) begin
        if (!resetn)
            bench_cycle <= 0;
        else
            bench_cycle <= bench_cycle + 1;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            glyph_perf_cycles <= 0;
            glyph_render_cycles <= 0;
            glyph_span_accept_count <= 0;
            glyph_pixel_write_count <= 0;
        end else if (glyph_perf_enabled) begin
            glyph_perf_cycles <= glyph_perf_cycles + 1;
            if ((dut.u_gru.state == 4'd4) || (dut.u_gru.state == 4'd6))
                glyph_render_cycles <= glyph_render_cycles + 1;
            if ((dut.u_gru.state == 4'd4) && dut.u_gru.span_valid && dut.u_gru.span_ready)
                glyph_span_accept_count <= glyph_span_accept_count + 1;
            if ((dut.u_gru.state == 4'd4) && dut.u_gru.gru_we)
                glyph_pixel_write_count <= glyph_pixel_write_count + 1;
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            line_span_accept_count <= 0;
            line_pixel_write_count <= 0;
        end else if (line_perf_enabled) begin
            if ((dut.u_gru.state == 4'd3) && dut.u_gru.span_valid && dut.u_gru.span_ready)
                line_span_accept_count <= line_span_accept_count + 1;
            if (dut.u_gru.gru_we)
                line_pixel_write_count <= line_pixel_write_count + 1;
        end
    end

    always @(posedge clk) begin
        if (resetn && err_active_write)
            $fatal(1, "[sketch_book_tb] attempted to write the active display page");
    end

    initial begin : test_main
        integer i;
        integer captured_before_swap;
        integer perf_cycles_before;
        integer render_cycles_before;
        integer bench_start;
        integer bench_render_start;
        integer move_render;
        integer move_present;
        integer visible_cat_x;
        integer visible_cat_y;
        integer target_cat_x;
        integer target_cat_y;
        integer old_cat_x;
        integer old_cat_y;
        integer next_cat_x;
        integer captured_before_bench;
        logic [31:0] status;
        logic [31:0] frame_counter_before;
        logic [31:0] swap_counter_before;
        logic front_idx_before;
        logic back_idx_before;
        logic front_valid_before;
        wait(resetn);

        // A long clear holds the engine busy while sixteen commands fill the
        // FIFO.  A seventeenth push must be backpressured rather than dropped.
        clear(16'h0000);
        for (i = 0; i < 16; i = i + 1)
            pixel(390, 299, 16'h0000);
        // CMD_PUSH is registered in the MMIO shell and reaches the GRU FIFO
        // on the following clock edge.
        @(negedge clk);
        if (dut.u_gru.cmd_level != 16)
            $fatal(1, "[sketch_book_tb] command FIFO level=%0d expected 16", dut.u_gru.cmd_level);
        expect_push_backpressured();
        wait_gru_idle();

        // Illegal commands retire without blocking later rendering and set the
        // sticky error status.
        submit_cmd(5'd31, 16'h0000, '0, '0, '0);
        wait_gru_idle();
        mmio_read(32'h004, status);
        if (!status[6])
            $fatal(1, "[sketch_book_tb] illegal opcode did not set sticky error");

        // Font 1 uses the native 5x7 glyph.  Count the exact number of
        // generated spans and BRAM writes for 80 printable ASCII characters.
        // Commands are intentionally retired one at a time so this measures the
        // renderer, rather than command FIFO occupancy or MMIO write latency.
        glyph_perf_cycles = 0;
        glyph_render_cycles = 0;
        glyph_span_accept_count = 0;
        glyph_pixel_write_count = 0;
        glyph_perf_enabled = 1'b1;
        for (i = 0; i < 80; i = i + 1) begin
            glyph(10 + ((i % 20) * 6), 20 + ((i / 20) * 8), 8'd32 + (i % 95), 2'd1, 16'hffff);
            wait_gru_idle();
        end
        @(posedge clk);
        glyph_perf_enabled = 1'b0;
        perf_cycles_before = glyph_perf_cycles;
        render_cycles_before = glyph_render_cycles;
        if (glyph_span_accept_count != 679)
            $fatal(1, "[sketch_book_tb] glyph spans=%0d expected=679", glyph_span_accept_count);
        if (glyph_pixel_write_count != 714)
            $fatal(1, "[sketch_book_tb] glyph beat writes=%0d expected=714", glyph_pixel_write_count);
        // Legacy 5x7 point rendering spends one scan cycle per cell plus two
        // writer-stall cycles per lit pixel: 80*5*7 + 2*980 = 4760 cycles.
        if (render_cycles_before > 3808)
            $fatal(1, "[sketch_book_tb] glyph renderer cycles=%0d exceeds 80%% legacy baseline", render_cycles_before);
        $display("[perf] glyph80 total_cycles=%0d render_cycles=%0d legacy=4760 spans=%0d pixels=%0d",
                 perf_cycles_before, render_cycles_before, glyph_span_accept_count, glyph_pixel_write_count);

        // Submit a mixed 2D + Flat Triangle frame.  No page can become visible
        // until the final PRESENT retires.
        clear(16'h0000);
        wait_gru_idle();

        // Horizontal and vertical lines use a single span each.  The reverse
        // direction cases must have the same inclusive pixel coverage.
        line_span_accept_count = 0;
        line_pixel_write_count = 0;
        line_perf_enabled = 1'b1;
        line(0, 150, 399, 150, 16'hf81f);
        wait_gru_idle();
        @(posedge clk);
        line_perf_enabled = 1'b0;
        if ((line_span_accept_count != 1) || (line_pixel_write_count != 50))
            $fatal(1, "[sketch_book_tb] horizontal fast path spans=%0d beats=%0d expected=1/50",
                   line_span_accept_count, line_pixel_write_count);

        line(399, 152, 0, 152, 16'h07e0);
        wait_gru_idle();

        line_span_accept_count = 0;
        line_pixel_write_count = 0;
        line_perf_enabled = 1'b1;
        line(360, 0, 360, 299, 16'hffe0);
        wait_gru_idle();
        @(posedge clk);
        line_perf_enabled = 1'b0;
        if ((line_span_accept_count != 1) || (line_pixel_write_count != 300))
            $fatal(1, "[sketch_book_tb] vertical fast path spans=%0d writes=%0d expected=1/300",
                   line_span_accept_count, line_pixel_write_count);

        line(362, 299, 362, 0, 16'h07ff);
        wait_gru_idle();

        // Fast paths clip their axis-aligned extent before submitting a span;
        // fully out-of-range commands still retire without stalling the FIFO.
        line(-8, 240, 8, 240, 16'hf800);
        wait_gru_idle();
        line(390, -8, 390, 8, 16'h001f);
        wait_gru_idle();
        line(10, -1, 20, -1, 16'hffff);
        wait_gru_idle();
        line(-1, 10, -1, 20, 16'hffff);
        wait_gru_idle();

        // A non-axis-aligned line remains on the original Bresenham path.
        line(10, 180, 20, 190, 16'hffff);

        rect(20, 60, 60, 60, 16'hf800);
        rect(140, 60, 60, 60, 16'h07e0);
        rect(260, 60, 60, 60, 16'h001f);
        pixel(5, 5, 16'hffe0);
        line(100, 20, 130, 20, 16'hf81f);
        glyph(200, 20, "A", 2'd1, 16'hffff);
        glyph(30, 20, " ", 2'd1, 16'h07e0);
        glyph(-2, 140, "A", 2'd1, 16'h07e0);
        glyph(398, 140, "E", 2'd1, 16'hffe0);
        glyph(100, 293, "A", 2'd1, 16'h07ff);
        glyph(410, 140, "A", 2'd1, 16'hf800);
        triangle(300, 180, 340, 180, 320, 220, 16'h07ff);
        rect(-10, 260, 20, 20, 16'hf800);
        rect(350, 20, 8, 8, 16'h001f);
        pixel(350, 20, 16'hf800);
        if (dut.front_valid || (front_change_count != 0))
            $fatal(1, "[sketch_book_tb] frame became visible before PRESENT");
        present();
        wait(dut.u_gru.frame_closed);
        expect_push_backpressured();

        wait(dut.swap_counter == 32'd1);
        if (!dut.front_valid || !irq_done)
            $fatal(1, "[sketch_book_tb] PRESENT did not produce a valid frame-done swap");
        // swap_done is generated by frame_ctrl; the top-level sticky status
        // samples that pulse on the next clock.
        @(posedge clk);
        mmio_read(32'h004, status);
        if (!status[5])
            $fatal(1, "[sketch_book_tb] frame_done sticky status was not set");
        captured_before_swap = mon.captured_frame_id;
        wait(mon.captured_frame_id > captured_before_swap);

        if ((mon.captured_frame_width != OUT_W) || (mon.captured_frame_height != OUT_H))
            $fatal(1, "[sketch_book_tb] capture is %0dx%0d, expected %0dx%0d",
                   mon.captured_frame_width, mon.captured_frame_height, OUT_W, OUT_H);
        if (front_change_count != 1)
            $fatal(1, "[sketch_book_tb] expected one front-page swap, got %0d", front_change_count);

        expect_pixel(10, 10, 255, 255, 0, "draw pixel");
        expect_pixel(40, 120, 255, 0, 0, "red rectangle origin");
        expect_pixel(159, 239, 255, 0, 0, "red rectangle extent");
        expect_pixel(280, 120, 0, 255, 0, "green rectangle origin");
        expect_pixel(520, 120, 0, 0, 255, "blue rectangle origin");
        expect_pixel(640, 380, 0, 255, 255, "flat triangle interior");
        expect_pixel(0, 520, 255, 0, 0, "clipped rectangle");
        expect_pixel(700, 40, 255, 0, 0, "ordered pixel over rectangle");
        expect_pixel(220, 40, 255, 0, 255, "line start");
        expect_pixel(404, 40, 255, 255, 255, "glyph A top");
        expect_pixel(60, 40, 0, 0, 0, "blank glyph retires without writes");
        expect_pixel(0, 280, 0, 255, 0, "negative-x glyph is left-clipped");
        expect_pixel(796, 280, 255, 255, 0, "right-edge glyph is clipped");
        expect_pixel(200, 598, 0, 255, 255, "glyph final row is rendered");
        expect_pixel(640, 120, 0, 0, 0, "background remains black");
        expect_pixel(0, 300, 255, 0, 255, "horizontal fast line origin");
        expect_pixel(400, 300, 255, 0, 255, "horizontal fast line interior");
        expect_pixel(798, 300, 255, 0, 255, "horizontal fast line extent");
        expect_pixel(0, 304, 0, 255, 0, "reversed horizontal line origin");
        expect_pixel(798, 304, 0, 255, 0, "reversed horizontal line extent");
        expect_pixel(720, 0, 255, 255, 0, "vertical fast line origin");
        expect_pixel(720, 300, 255, 255, 0, "vertical fast line interior");
        expect_pixel(720, 598, 255, 255, 0, "vertical fast line extent");
        expect_pixel(724, 0, 0, 255, 255, "reversed vertical line origin");
        expect_pixel(724, 598, 0, 255, 255, "reversed vertical line extent");
        expect_pixel(0, 480, 255, 0, 0, "clipped horizontal line origin");
        expect_pixel(16, 480, 255, 0, 0, "clipped horizontal line extent");
        expect_pixel(18, 480, 0, 0, 0, "clipped horizontal adjacent background");
        expect_pixel(780, 0, 0, 0, 255, "clipped vertical line origin");
        expect_pixel(780, 16, 0, 0, 255, "clipped vertical line extent");
        expect_pixel(780, 18, 0, 0, 0, "clipped vertical adjacent background");
        expect_pixel(40, 2, 0, 0, 0, "fully clipped lines leave background");
        expect_pixel(20, 360, 255, 255, 255, "Bresenham line origin");
        expect_pixel(30, 370, 255, 255, 255, "Bresenham line interior");
        expect_pixel(40, 380, 255, 255, 255, "Bresenham line extent");

        mmio_write(32'h004, 32'h20);
        mmio_read(32'h004, status);
        if (status[5])
            $fatal(1, "[sketch_book_tb] frame_done W1C did not clear");

        // CTRL.display_enable stops timing, holds both counters at zero and
        // must not manufacture a vblank swap while the display is paused.
        front_idx_before = dut.front_idx;
        frame_counter_before = dut.frame_counter;
        swap_counter_before = dut.swap_counter;
        captured_before_swap = mon.captured_frame_id;
        mmio_write(32'h000, 32'h0000_0000);
        repeat (4) @(posedge clk); // timing + DVI output pipeline drain
        if ((dut.u_gdu.h_cnt != 0) || (dut.u_gdu.v_cnt != 0) || dvi_de || dut.frame_boundary)
            $fatal(1, "[sketch_book_tb] display disable did not quiesce timing/de");
        repeat (1000) @(posedge clk);
        if ((dut.front_idx != front_idx_before) ||
            (dut.frame_counter != frame_counter_before) ||
            (dut.swap_counter != swap_counter_before))
            $fatal(1, "[sketch_book_tb] display disable changed page or frame state");
        mmio_write(32'h000, 32'h0000_0001);
        repeat (4) @(posedge clk);
        if (dut.u_gdu.h_cnt == 0)
            $fatal(1, "[sketch_book_tb] display enable did not restart timing");
        wait(mon.captured_frame_id > captured_before_swap);
        expect_pixel(10, 10, 255, 255, 0, "display enable retains front page");

        // Soft reset clears GRU/FIFO state and sticky GRU error only.  It must
        // leave the current front page and frame-controller ownership intact.
        mmio_read(32'h004, status);
        if (!status[6])
            $fatal(1, "[sketch_book_tb] expected pre-reset sticky GRU error");
        front_idx_before = dut.front_idx;
        back_idx_before = dut.back_idx;
        front_valid_before = dut.front_valid;
        swap_counter_before = dut.swap_counter;
        clear(16'h0000);
        pixel(1, 1, 16'hffff);
        repeat (2) @(posedge clk);
        if ((dut.u_gru.cmd_level == 0) && !dut.u_gru.busy)
            $fatal(1, "[sketch_book_tb] could not establish GRU work before soft reset");
        mmio_write(32'h000, 32'h0000_0003);
        repeat (3) @(posedge clk);
        mmio_read(32'h004, status);
        if ((dut.u_gru.cmd_level != 0) || dut.u_gru.frame_closed || status[6])
            $fatal(1, "[sketch_book_tb] soft reset did not clear FIFO/frame_closed/error");
        if ((dut.front_idx != front_idx_before) || (dut.back_idx != back_idx_before) ||
            (dut.front_valid != front_valid_before) || (dut.swap_counter != swap_counter_before))
            $fatal(1, "[sketch_book_tb] soft reset disturbed the displayed front page");
        expect_pixel(10, 10, 255, 255, 0, "soft reset retains front pixels");

        // Aggressive clipping: two rectangles, a Bresenham line entering and
        // leaving the viewport, then partial/offscreen/degenerate triangles.
        clear(16'h0000);
        wait_gru_idle();
        rect(-100, -100, 200, 200, 16'hf800);
        rect(390, 290, 50, 50, 16'h07e0);
        line(-20, -20, 420, 320, 16'hffff);
        triangle(-20, 150, 80, 180, 20, 260, 16'h07ff);
        triangle(420, 20, 460, 60, 440, 100, 16'hffe0);
        triangle(200, 280, 220, 280, 240, 280, 16'hf81f);
        wait_gru_idle();
        present_and_capture(32'd2, 2, "clipping stress frame");
        expect_pixel(100, 100, 255, 0, 0, "large negative rectangle interior");
        expect_pixel(198, 198, 255, 0, 0, "large negative rectangle extent");
        expect_pixel(200, 200, 0, 0, 0, "large negative rectangle adjacent background");
        expect_pixel(780, 580, 0, 255, 0, "bottom-right rectangle origin");
        expect_pixel(798, 598, 0, 255, 0, "bottom-right rectangle extent");
        expect_pixel(12, 0, 255, 255, 255, "clipped diagonal line entry");
        expect_pixel(786, 598, 255, 255, 255, "clipped diagonal line exit");
        // GRU Lite rejects triangles with out-of-range vertices before raster.
        expect_pixel(20, 400, 0, 0, 0, "Lite rejects partial triangle");
        expect_pixel(20, 300, 0, 0, 0, "partial triangle exterior remains background");
        expect_pixel(720, 100, 0, 0, 0, "fully offscreen triangle is a no-op");
        expect_pixel(400, 560, 0, 0, 0, "degenerate triangle is a no-op");

        // Consecutive PRESENT coverage: every page is cleared before the
        // glyph is drawn, making residue from any older back/front page visible.
        clear(16'hf800);
        wait_gru_idle();
        glyph(20, 20, "A", 2'd1, 16'hffff);
        wait_gru_idle();
        present_and_capture(32'd3, 3, "red A frame");
        expect_pixel(600, 400, 255, 0, 0, "red frame background");
        expect_pixel(44, 40, 255, 255, 255, "red frame A glyph");
        expect_pixel(720, 0, 255, 0, 0, "red frame has no old line residue");

        clear(16'h07e0);
        wait_gru_idle();
        glyph(60, 20, "B", 2'd1, 16'hffff);
        wait_gru_idle();
        present_and_capture(32'd4, 4, "green B frame");
        expect_pixel(600, 400, 0, 255, 0, "green frame background");
        expect_pixel(120, 40, 255, 255, 255, "green frame B glyph");
        expect_pixel(44, 40, 0, 255, 0, "green frame clears A residue");

        clear(16'h001f);
        wait_gru_idle();
        glyph(100, 20, "C", 2'd1, 16'hffff);
        wait_gru_idle();
        present_and_capture(32'd5, 5, "blue C frame");
        expect_pixel(600, 400, 0, 0, 255, "blue frame background");
        expect_pixel(202, 40, 255, 255, 255, "blue frame C glyph");
        expect_pixel(120, 40, 0, 0, 255, "blue frame clears B residue");

        // Full UI benchmark.  It builds a realistic text-heavy UI once on
        // each page, then moves a transparent RGB332 cat without redrawing
        // the rest of the screen.  The target page's previous cat position is
        // restored before every BLIT, which keeps both page histories clean.
        bench_render_start = bench_cycle;
        draw_ui_base();
        wait_gru_idle();
        bench_ui_render = bench_cycle - bench_render_start;
        if (bench_ui_render > BENCH_UI_RENDER_CAP)
            $fatal(1, "[SKETCH_BENCH] ui_initial_render=%0d exceeds cap=%0d",
                   bench_ui_render, BENCH_UI_RENDER_CAP);
        bench_start = bench_cycle;
        present();
        wait(dut.swap_counter == 32'd6);
        bench_ui_present = bench_cycle - bench_start;
        if (bench_ui_present > BENCH_UI_PRESENT_CAP)
            $fatal(1, "[SKETCH_BENCH] ui_initial_present=%0d exceeds cap=%0d",
                   bench_ui_present, BENCH_UI_PRESENT_CAP);
        captured_before_bench = mon.captured_frame_id;
        wait(mon.captured_frame_id > captured_before_bench);
        expect_pixel(20, 20, 0, 255, 255, "UI title bar");
        expect_pixel(40, 36, 0, 0, 0, "UI title text");
        expect_pixel(40, 120, 0, 255, 0, "UI START button");
        expect_pixel(40, 480, 0, 0, 255, "UI cat playground");

        // Static BLIT pressure includes a normal, a left-clipped and a
        // bottom-right-clipped cat.  This back page is rebuilt below.
        bench_start = bench_cycle;
        blit_cat(340, 250);
        blit_cat(-12, 250);
        blit_cat(390, 280);
        wait_gru_idle();
        bench_static_blit = bench_cycle - bench_start;
        if (bench_static_blit > BENCH_STATIC_BLIT_CAP)
            $fatal(1, "[SKETCH_BENCH] cat_blit_static=%0d exceeds cap=%0d",
                   bench_static_blit, BENCH_STATIC_BLIT_CAP);

        draw_ui_base();
        blit_cat(20, 252);
        wait_gru_idle();
        present();
        wait(dut.swap_counter == 32'd7);
        captured_before_bench = mon.captured_frame_id;
        wait(mon.captured_frame_id > captured_before_bench);
        expect_pixel(60, 530, 0, 0, 0, "initial cat eye");

        visible_cat_x = 20;
        visible_cat_y = 252;
        target_cat_x = 20;
        target_cat_y = 252;
        bench_move_total = 0;
        bench_move_max_render = 0;
        bench_move_max_present = 0;
        for (i = 0; i < 32; i = i + 1) begin
            old_cat_x = target_cat_x;
            old_cat_y = target_cat_y;
            next_cat_x = 20 + ((i * 13) % 340);
            bench_render_start = bench_cycle;
            rect(old_cat_x, old_cat_y, 32, 32, UI_ACTIVITY);
            blit_cat(next_cat_x, 252);
            wait_gru_idle();
            move_render = bench_cycle - bench_render_start;
            bench_start = bench_cycle;
            present();
            wait(dut.swap_counter == 32'd8 + i);
            move_present = bench_cycle - bench_start;
            bench_move_total = bench_move_total + move_render;
            if (move_render > bench_move_max_render)
                bench_move_max_render = move_render;
            if (move_present > bench_move_max_present)
                bench_move_max_present = move_present;
            target_cat_x = visible_cat_x;
            target_cat_y = visible_cat_y;
            visible_cat_x = next_cat_x;
            visible_cat_y = 252;
        end
        captured_before_bench = mon.captured_frame_id;
        wait(mon.captured_frame_id > captured_before_bench);
        expect_pixel((visible_cat_x + 10) * 2, (visible_cat_y + 13) * 2,
                     0, 0, 0, "animated cat eye");
        expect_pixel((old_cat_x + 10) * 2, (old_cat_y + 13) * 2,
                     0, 0, 255, "old cat location restored");
        if (bench_move_max_render > BENCH_MOVE_RENDER_CAP)
            $fatal(1, "[SKETCH_BENCH] cat_move max render=%0d exceeds cap=%0d",
                   bench_move_max_render, BENCH_MOVE_RENDER_CAP);
        if (bench_move_max_present > BENCH_MOVE_PRESENT_CAP)
            $fatal(1, "[SKETCH_BENCH] cat_move max present=%0d exceeds cap=%0d",
                   bench_move_max_present, BENCH_MOVE_PRESENT_CAP);
        if (dut.u_gru.error || err_active_write)
            $fatal(1, "[sketch_book_tb] UI/BLIT benchmark raised an error");

        // New GRU-Lite Gouraud and generic Asset-BRAM BLIT coverage.  Asset 0
        // is the legacy cat descriptor; source rectangles exercise the common
        // BLIT path rather than the compatibility wrapper.
        clear(16'h0000);
        triangle_gouraud(40, 40, 16'hf800, 100, 40, 16'h07e0, 40, 100, 16'h001f);
        blit_asset(120, 80, 10, 13, 3, 3, 1'b0, SPRITE_KEY);
        wait_gru_idle();
        captured_before_bench = mon.captured_frame_id;
        present();
        wait(mon.captured_frame_id > captured_before_bench);
        mon.assert_captured_region_nonblack(80, 80, 200, 200, 100, "Gouraud triangle");
        mon.assert_captured_region_nonblack(240, 160, 246, 166, 4, "asset source sub-rectangle");
        if (dut.u_gru.error || err_active_write)
            $fatal(1, "[sketch_book_tb] Gouraud/asset BLIT raised an error");
        $display("[SKETCH_BENCH] category=ui_initial_render render_cycles=%0d baseline=%0d cap=%0d status=PASS",
                 bench_ui_render, BENCH_UI_RENDER_BASELINE, BENCH_UI_RENDER_CAP);
        $display("[SKETCH_BENCH] category=ui_initial_present present_cycles=%0d baseline=%0d cap=%0d status=PASS",
                 bench_ui_present, BENCH_UI_PRESENT_BASELINE, BENCH_UI_PRESENT_CAP);
        $display("[SKETCH_BENCH] category=cat_blit_static render_cycles=%0d baseline=%0d cap=%0d status=PASS",
                 bench_static_blit, BENCH_STATIC_BLIT_BASELINE, BENCH_STATIC_BLIT_CAP);
        $display("[SKETCH_BENCH] category=cat_move_sequence frames=32 avg_render_cycles=%0d max_render_cycles=%0d max_present_cycles=%0d baseline_render=%0d cap_render=%0d baseline_present=%0d cap_present=%0d status=PASS",
                 bench_move_total / 32, bench_move_max_render, bench_move_max_present,
                 BENCH_MOVE_RENDER_BASELINE, BENCH_MOVE_RENDER_CAP,
                 BENCH_MOVE_PRESENT_BASELINE, BENCH_MOVE_PRESENT_CAP);

        mon.dump_captured_frame("sketch_book_mixed_render");
        mon.flush_and_close();
        done = 1'b1;
        $display("[sketch_book_tb] PASS BRAM GRU multi-frame CTRL/reset clipping render");
        $finish;
    end

    initial begin : watchdog
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        if (!done)
            $fatal(1, "[sketch_book_tb] watchdog timeout");
    end
endmodule
