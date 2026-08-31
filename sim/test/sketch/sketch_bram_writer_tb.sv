`timescale 1ns / 1ps

module sketch_bram_writer_tb;
    localparam int ADDR_W = $clog2((400 * 300) / 8);

    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic clear = 1'b0;
    logic target_page = 1'b1;
    logic span_valid = 1'b0;
    logic span_ready;
    logic [15:0] span_x = '0;
    logic [15:0] span_y = '0;
    logic [15:0] span_len = '0;
    logic [ADDR_W-1:0] span_step = '0;
    logic [7:0] span_color = '0;
    logic span_last = 1'b0;
    logic busy, cmd_done, gru_we, gru_page;
    logic [ADDR_W-1:0] gru_addr;
    logic [63:0] gru_wdata;
    logic [7:0] gru_wstrb;
    logic done = 1'b0;

    always #5 clk = ~clk;

    sketch_bram_writer #(.SRC_W(400), .SRC_H(300), .ADDR_W(ADDR_W)) dut (
        .clk(clk), .resetn(resetn), .clear(clear), .target_page(target_page),
        .span_valid(span_valid), .span_ready(span_ready), .span_x(span_x), .span_y(span_y),
        .span_len(span_len), .span_step(span_step), .span_color(span_color), .span_last(span_last),
        .busy(busy), .cmd_done(cmd_done), .gru_we(gru_we), .gru_page(gru_page),
        .gru_addr(gru_addr), .gru_wdata(gru_wdata), .gru_wstrb(gru_wstrb)
    );

    task automatic submit_span(
        input logic [15:0] x,
        input logic [15:0] y,
        input logic [15:0] len,
        input logic [7:0] color,
        input logic [ADDR_W-1:0] step,
        input logic last
    );
        begin
            @(negedge clk);
            if (!span_ready)
                $fatal(1, "[sketch_bram_writer_tb] writer was not ready for span");
            span_valid = 1'b1;
            span_x = x;
            span_y = y;
            span_len = len;
            span_step = step;
            span_color = color;
            span_last = last;
            @(posedge clk);
            if (!span_ready)
                $fatal(1, "[sketch_bram_writer_tb] span handshake failed");
            @(negedge clk);
            span_valid = 1'b0;
            span_x = '0;
            span_y = '0;
            span_len = '0;
            span_step = '0;
            span_color = '0;
            span_last = 1'b0;
        end
    endtask

    task automatic expect_write(input integer expected_addr, input logic [7:0] expected_mask, input logic [7:0] expected_color);
        begin
            if (!gru_we)
                $fatal(1, "[sketch_bram_writer_tb] expected write at address %0d", expected_addr);
            if (gru_addr != expected_addr[ADDR_W-1:0])
                $fatal(1, "[sketch_bram_writer_tb] addr=%0d expected=%0d", gru_addr, expected_addr);
            if ((gru_wdata != {8{expected_color}}) || (gru_wstrb != expected_mask) || (gru_page != target_page))
                $fatal(1, "[sketch_bram_writer_tb] write metadata mismatch");
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        resetn = 1'b1;

        // A zero-length non-final span neither writes nor completes.
        submit_span(16'd7, 16'd9, 16'd0, 8'h11, 1, 1'b0);
        if (gru_we || cmd_done || busy)
            $fatal(1, "[sketch_bram_writer_tb] zero-length non-final span changed writer state");

        // A zero-length final span completes immediately without a write.
        submit_span(16'd7, 16'd9, 16'd0, 8'h22, 1, 1'b1);
        if (gru_we || !cmd_done || busy)
            $fatal(1, "[sketch_bram_writer_tb] zero-length final span timing incorrect");
        @(posedge clk);
        @(negedge clk);
        if (cmd_done)
            $fatal(1, "[sketch_bram_writer_tb] cmd_done was wider than one clock");

        // A one-pixel final span writes once, then completes only after that write.
        submit_span(16'd399, 16'd2, 16'd1, 8'hcd, 1, 1'b1);
        expect_write(149, 8'h80, 8'hcd);
        if (cmd_done)
            $fatal(1, "[sketch_bram_writer_tb] one-pixel span completed before write");
        @(posedge clk);
        @(negedge clk);
        if (gru_we || !cmd_done || busy)
            $fatal(1, "[sketch_bram_writer_tb] one-pixel final completion timing incorrect");

        // A short unaligned span writes only its occupied byte lanes.
        submit_span(16'd10, 16'd17, 16'd3, 8'haa, 1, 1'b1);
        expect_write(851, 8'h1c, 8'haa);
        @(posedge clk);
        @(negedge clk);
        if (gru_we || !cmd_done || busy)
            $fatal(1, "[sketch_bram_writer_tb] multi-pixel final completion timing incorrect");

        // An unaligned span crosses three 64-bit words: partial head, full word,
        // then partial tail.  This is the packed fast path used by horizontal spans.
        submit_span(16'd5, 16'd3, 16'd12, 8'h5a, 1, 1'b1);
        expect_write(150, 8'he0, 8'h5a);
        @(posedge clk);
        @(negedge clk);
        expect_write(151, 8'hff, 8'h5a);
        @(posedge clk);
        @(negedge clk);
        expect_write(152, 8'h01, 8'h5a);
        @(posedge clk);
        @(negedge clk);
        if (gru_we || !cmd_done || busy)
            $fatal(1, "[sketch_bram_writer_tb] cross-word packed span completion timing incorrect");

        // A vertical span advances one framebuffer row (400 pixels) per write.
        submit_span(16'd12, 16'd2, 16'd3, 8'hfe, 400, 1'b1);
        expect_write(101, 8'h10, 8'hfe);
        @(posedge clk);
        @(negedge clk);
        expect_write(151, 8'h10, 8'hfe);
        @(posedge clk);
        @(negedge clk);
        expect_write(201, 8'h10, 8'hfe);
        @(posedge clk);
        @(negedge clk);
        if (gru_we || !cmd_done || busy)
            $fatal(1, "[sketch_bram_writer_tb] strided final completion timing incorrect");

        done = 1'b1;
        $display("[sketch_bram_writer_tb] PASS zero/unaligned/cross-word/strided span timing");
        $finish;
    end

    initial begin
        repeat (500) @(posedge clk);
        if (!done)
            $fatal(1, "[sketch_bram_writer_tb] watchdog timeout");
    end
endmodule
