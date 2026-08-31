`timescale 1ns / 1ps

// SketchBook renderer performance benchmark.  It intentionally instantiates
// the GRU directly: no MMIO shell, frame controller, GDU, or DVI monitor can
// add host/display timing noise to the renderer score.
module sketch_perf_tb;
    localparam int SRC_W = 400;
    localparam int SRC_H = 300;
    localparam int ADDR_W = $clog2(SRC_W * SRC_H);
    localparam int GLYPH80_PIXELS = 980;
    localparam int GLYPH80_SPANS = 679;
    localparam int LEGACY_GLYPH80_RENDERER_CYCLES = 4760;
    localparam int MAX_GLYPH80_RENDERER_CYCLES = 3808;
    localparam logic [4:0] CMD_GLYPH = 5'd4;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic soft_reset = 1'b0;
    logic render_allowed = 1'b1;
    logic target_page = 1'b1;
    logic cmd_push_valid = 1'b0;
    logic [31:0] cmd_push_w0 = '0;
    logic [31:0] cmd_push_w1 = '0;
    logic [31:0] cmd_push_w2 = '0;
    logic [31:0] cmd_push_w3 = '0;
    logic cmd_push_ready, cmd_full, busy, idle, frame_closed, present_req, error;
    logic write_attempt, gru_we, gru_page;
    logic [$clog2(16 + 1)-1:0] cmd_level;
    logic [ADDR_W-1:0] gru_addr;
    logic [15:0] gru_wdata;
    logic measure_enable = 1'b0;
    logic renderer_active;
    logic [31:0] total_cycles, renderer_cycles, span_count, pixel_write_count;
    logic done = 1'b0;

    always #5 clk = ~clk;

    sketch_gru_top #(.SRC_W(SRC_W), .SRC_H(SRC_H), .ADDR_W(ADDR_W)) dut (
        .clk(clk), .resetn(resetn), .soft_reset(soft_reset),
        .render_allowed(render_allowed), .target_page(target_page),
        .cmd_push_valid(cmd_push_valid), .cmd_push_w0(cmd_push_w0),
        .cmd_push_w1(cmd_push_w1), .cmd_push_w2(cmd_push_w2), .cmd_push_w3(cmd_push_w3), .cmd_push_w4(32'd0),
        .cmd_push_ready(cmd_push_ready), .cmd_level(cmd_level), .cmd_full(cmd_full),
        .busy(busy), .idle(idle), .frame_closed(frame_closed), .present_req(present_req),
        .error(error), .write_attempt(write_attempt), .gru_we(gru_we),
        .gru_page(gru_page), .gru_addr(gru_addr), .gru_wdata(gru_wdata)
    );

    // State 4 is ST_GLYPH and state 6 is ST_WAIT_DONE.  This is a testbench
    // tap only; the monitor remains reusable because it receives a generic
    // renderer_active signal rather than a DUT hierarchy.
    assign renderer_active = (dut.state == 4'd4) || (dut.state == 4'd6);

    sketch_perf_monitor perf_mon (
        .clk(clk), .resetn(resetn), .measure_enable(measure_enable),
        .renderer_active(renderer_active), .span_valid(dut.span_valid),
        .span_ready(dut.span_ready), .pixel_write(gru_we),
        .total_cycles(total_cycles), .renderer_cycles(renderer_cycles),
        .span_count(span_count), .pixel_write_count(pixel_write_count)
    );

    task automatic push_glyph(
        input integer x,
        input integer y,
        input logic [7:0] ascii,
        input logic [1:0] font
    );
        begin
            while (!cmd_push_ready)
                @(posedge clk);
            @(negedge clk);
            cmd_push_valid = 1'b1;
            cmd_push_w0 = {11'd0, 16'hffff, CMD_GLYPH};
            cmd_push_w1 = {y[15:0], x[15:0]};
            cmd_push_w2 = {22'd0, font, ascii};
            cmd_push_w3 = '0;
            @(posedge clk);
            if (!cmd_push_ready)
                $fatal(1, "[sketch_perf_tb] glyph push was not accepted");
            @(negedge clk);
            cmd_push_valid = 1'b0;
            cmd_push_w0 = '0;
            cmd_push_w1 = '0;
            cmd_push_w2 = '0;
            cmd_push_w3 = '0;
        end
    endtask

    task automatic wait_idle;
        integer cycles;
        begin
            for (cycles = 0; cycles < 100_000; cycles = cycles + 1) begin
                @(posedge clk);
                if (idle)
                    return;
            end
            $fatal(1, "[sketch_perf_tb] renderer did not become idle");
        end
    endtask

    task automatic begin_measurement;
        begin
            @(negedge clk);
            measure_enable = 1'b1;
            @(posedge clk); // Monitor reset edge; the next edge is cycle zero.
        end
    endtask

    task automatic end_measurement;
        begin
            @(negedge clk);
            measure_enable = 1'b0;
        end
    endtask

    task automatic run_single_glyph(
        input string scenario,
        input integer x,
        input integer y,
        input logic [7:0] ascii,
        input integer expected_writes,
        input integer expected_spans
    );
        begin
            begin_measurement();
            push_glyph(x, y, ascii, 2'd1);
            wait_idle();
            end_measurement();
            if (error)
                $fatal(1, "[sketch_perf_tb] %0s raised renderer error", scenario);
            if ((expected_writes >= 0) && (pixel_write_count != expected_writes))
                $fatal(1, "[sketch_perf_tb] %0s pixel_writes=%0d expected=%0d",
                       scenario, pixel_write_count, expected_writes);
            if ((expected_spans >= 0) && (span_count != expected_spans))
                $fatal(1, "[sketch_perf_tb] %0s spans=%0d expected=%0d",
                       scenario, span_count, expected_spans);
            perf_mon.report(scenario, 0);
        end
    endtask

    initial begin : benchmark_main
        integer i;
        repeat (2) @(posedge clk);
        resetn = 1'b1;
        wait_idle();

        // Fixed, version-comparable workload: 80 printable native 5x7 glyphs.
        begin_measurement();
        for (i = 0; i < 80; i = i + 1) begin
            push_glyph(10 + ((i % 20) * 6), 20 + ((i / 20) * 8), 8'd32 + (i % 95), 2'd1);
            wait_idle();
        end
        end_measurement();
        if (pixel_write_count != GLYPH80_PIXELS)
            $fatal(1, "[sketch_perf_tb] glyph80 pixel_writes=%0d expected=%0d",
                   pixel_write_count, GLYPH80_PIXELS);
        if (span_count != GLYPH80_SPANS)
            $fatal(1, "[sketch_perf_tb] glyph80 spans=%0d expected=%0d",
                   span_count, GLYPH80_SPANS);
        if (renderer_cycles > MAX_GLYPH80_RENDERER_CYCLES)
            $fatal(1, "[sketch_perf_tb] glyph80 renderer_cycles=%0d exceeds %0d",
                   renderer_cycles, MAX_GLYPH80_RENDERER_CYCLES);
        perf_mon.report("glyph80_native_5x7", LEGACY_GLYPH80_RENDERER_CYCLES);

        // Functional edge workloads are included here to ensure the benchmark
        // monitor also observes blank, sparse/continuous, and clipped glyphs.
        run_single_glyph("blank", 30, 20, " ", 0, 0);
        run_single_glyph("sparse", 50, 20, "!", -1, -1);
        run_single_glyph("continuous_strokes", 70, 20, "E", -1, -1);
        run_single_glyph("left_clipped", -2, 140, "A", -1, -1);
        run_single_glyph("right_clipped", 398, 140, "E", -1, -1);
        run_single_glyph("top_clipped", 100, -2, "A", -1, -1);
        run_single_glyph("bottom_clipped", 100, 298, "A", -1, -1);
        run_single_glyph("fully_offscreen", 410, 140, "A", 0, 0);

        done = 1'b1;
        $display("[sketch_perf_tb] PASS fixed glyph benchmark and clipping scenarios");
        $finish;
    end

    initial begin : watchdog
        repeat (2_000_000) @(posedge clk);
        if (!done)
            $fatal(1, "[sketch_perf_tb] watchdog timeout");
    end
endmodule
