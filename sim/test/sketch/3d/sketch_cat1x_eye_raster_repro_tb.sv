`timescale 1ns / 1ps

module sketch_cat1x_eye_raster_repro_tb;
    localparam integer FRAME_W = 400;
    localparam integer FRAME_H = 300;
    localparam integer ADDR_W = $clog2(FRAME_W * FRAME_H);
    localparam logic [7:0] HEAD_COLOR = 8'hcc;
    localparam logic [7:0] EYE_COLOR = 8'h00;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic clear = 1'b0;
    logic start = 1'b0;
    logic gouraud_en = 1'b0;
    logic signed [15:0] x0 = '0, y0 = '0;
    logic signed [15:0] x1 = '0, y1 = '0;
    logic signed [15:0] x2 = '0, y2 = '0;
    logic [7:0] c0_rgb332 = '0, c1_rgb332 = '0, c2_rgb332 = '0;
    logic [15:0] frame_w = FRAME_W;
    logic [15:0] frame_h = FRAME_H;
    logic tri_busy, span_valid, span_ready;
    logic [63:0] span_data;
    logic [15:0] span_x, span_y, span_len;
    logic [7:0] span_color;
    logic [ADDR_W-1:0] span_step;
    logic span_last;
    logic writer_busy, writer_done, writer_we, writer_page;
    logic [ADDR_W-1:0] writer_addr;
    logic [63:0] writer_wdata;
    logic [7:0] writer_wstrb;
    logic [7:0] fb [0:FRAME_W * FRAME_H - 1];

    always #10 clk = ~clk;

    sketch_triangle_lite_adapter dut (
        .clk(clk),
        .resetn(resetn),
        .clear(clear),
        .start(start),
        .gouraud_en(gouraud_en),
        .x0(x0), .y0(y0),
        .x1(x1), .y1(y1),
        .x2(x2), .y2(y2),
        .c0_rgb332(c0_rgb332),
        .c1_rgb332(c1_rgb332),
        .c2_rgb332(c2_rgb332),
        .frame_w(frame_w),
        .frame_h(frame_h),
        .busy(tri_busy),
        .span_valid(span_valid),
        .span_ready(span_ready),
        .span_data(span_data)
    );

    sketch_span_adapter #(.ADDR_W(ADDR_W)) u_span_adapter (
        .in_span(span_data),
        .span_x(span_x),
        .span_y(span_y),
        .span_len(span_len),
        .span_step(span_step),
        .span_color(span_color),
        .span_last(span_last)
    );

    sketch_bram_writer #(
        .SRC_W(FRAME_W),
        .SRC_H(FRAME_H),
        .ADDR_W(ADDR_W)
    ) u_writer (
        .clk(clk),
        .resetn(resetn),
        .clear(clear),
        .target_page(1'b0),
        .span_valid(span_valid),
        .span_ready(span_ready),
        .span_x(span_x),
        .span_y(span_y),
        .span_len(span_len),
        .span_step(span_step),
        .span_color(span_color),
        .span_last(span_last),
        .busy(writer_busy),
        .cmd_done(writer_done),
        .gru_we(writer_we),
        .gru_page(writer_page),
        .gru_addr(writer_addr),
        .gru_wdata(writer_wdata),
        .gru_wstrb(writer_wstrb)
    );

    function automatic integer fb_index(input integer px, input integer py);
        begin
            fb_index = py * FRAME_W + px;
        end
    endfunction

    task automatic clear_fb;
        integer idx;
        begin
            for (idx = 0; idx < FRAME_W * FRAME_H; idx = idx + 1)
                fb[idx] = 8'h00;
        end
    endtask

    task automatic launch_flat_triangle(
        input integer ix0, input integer iy0,
        input integer ix1, input integer iy1,
        input integer ix2, input integer iy2,
        input logic [7:0] color
    );
        integer wait_cycles;
        begin
            @(negedge clk);
            x0 = ix0; y0 = iy0;
            x1 = ix1; y1 = iy1;
            x2 = ix2; y2 = iy2;
            c0_rgb332 = color;
            c1_rgb332 = color;
            c2_rgb332 = color;
            start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;

            for (wait_cycles = 0; wait_cycles < 20000; wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                if (!tri_busy && !writer_busy && !span_valid)
                    return;
            end
            $fatal(1, "[eye_repro] triangle did not drain x0=%0d y0=%0d x1=%0d y1=%0d x2=%0d y2=%0d",
                   ix0, iy0, ix1, iy1, ix2, iy2);
        end
    endtask

    task automatic expect_fb_pixel(
        input integer px,
        input integer py,
        input logic [7:0] expected,
        input [8*48-1:0] label
    );
        logic [7:0] got;
        begin
            got = fb[fb_index(px, py)];
            if (got !== expected)
                $fatal(1, "[eye_repro] %0s at (%0d,%0d): got=%02h expected=%02h",
                       label, px, py, got, expected);
        end
    endtask

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
        end else if (clear) begin
            clear_fb();
        end else if (writer_we) begin
            for (integer lane = 0; lane < 8; lane = lane + 1)
                if (writer_wstrb[lane])
                    fb[(writer_addr << 3) + lane] <= writer_wdata[lane*8 +: 8];
        end
    end

    initial begin
        clear_fb();
        #200;
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        // Scene-1 style eye pair: known-good control case.
        launch_flat_triangle(268, 106, 231, 157, 231, 106, HEAD_COLOR);
        launch_flat_triangle(268, 106, 268, 157, 231, 157, HEAD_COLOR);
        launch_flat_triangle(244, 131, 234, 131, 234, 119, EYE_COLOR);
        launch_flat_triangle(244, 131, 234, 119, 244, 119, EYE_COLOR);

        expect_fb_pixel(233, 125, HEAD_COLOR, "head background left");
        expect_fb_pixel(236, 129, EYE_COLOR, "eye lower-left triangle");
        expect_fb_pixel(242, 121, EYE_COLOR, "eye upper-right triangle");
        expect_fb_pixel(245, 125, HEAD_COLOR, "head background right");

        // Scene-0 right eye: this is the geometry that appears triangular in
        // `sketch_cat1x_3d_shade_tb_0002.ppm`.
        clear_fb();
        repeat (2) @(posedge clk);

        launch_flat_triangle(225, 106, 170, 157, 170, 106, HEAD_COLOR);
        launch_flat_triangle(225, 106, 225, 157, 170, 157, HEAD_COLOR);
        // Use the exact scene-core emission order/diagonal from frame-0.
        launch_flat_triangle(205, 131, 219, 119, 205, 119, EYE_COLOR);
        launch_flat_triangle(205, 131, 219, 131, 219, 119, EYE_COLOR);

        expect_fb_pixel(204, 125, HEAD_COLOR, "scene0 head background left");
        expect_fb_pixel(208, 124, EYE_COLOR, "scene0 eye missing-half probe");
        expect_fb_pixel(218, 120, EYE_COLOR, "scene0 eye intact-half probe");
        expect_fb_pixel(220, 125, HEAD_COLOR, "scene0 head background right");

        $display("[SKETCH_EYE_REPRO] PASS");
        #100;
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "[eye_repro] timeout");
    end
endmodule
