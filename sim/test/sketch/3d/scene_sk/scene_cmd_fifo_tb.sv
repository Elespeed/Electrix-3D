`timescale 1ns/1ps
// Directed protocol checks for the parameterized Scene command FIFO.
module scene_cmd_fifo_tb;
    logic clk = 0, resetn = 0;
    always #5 clk = ~clk;
    logic push_valid, push_ready, full, locked, frame_start, frame_complete, frame_error, pop, empty;
    logic [127:0] push_data, head;
    logic [5:0] level;

    scene_cmd_fifo #(.DEPTH(32), .WIDTH(128)) dut (.*);

    task automatic push(input logic [127:0] d);
        begin
            @(negedge clk); push_data = d; push_valid = 1'b1;
            if (!push_ready) $fatal(1, "push unexpectedly backpressured at level=%0d", level);
            @(posedge clk); #1;
            @(negedge clk); push_valid = 1'b0;
        end
    endtask

    initial begin
        push_valid = 0; push_data = 0; frame_start = 0; frame_complete = 0;
        frame_error = 0; pop = 0;
        repeat (2) @(posedge clk); resetn = 1;
        #1;
        if (!empty || level != 0 || full || !push_ready || locked)
            $fatal(1, "empty/reset protocol failed level=%0d", level);

        // Fill all 32 entries and prove the 33rd command is backpressured.
        for (int i = 0; i < 32; i++) push(i);
        if (level != 32 || !full || push_ready || empty)
            $fatal(1, "full protocol failed level=%0d full=%b ready=%b", level, full, push_ready);
        push_data = 128'hdead_beef;
        push_valid = 1;
        repeat (2) @(posedge clk);
        if (level != 32 || head !== 0) $fatal(1, "overflow was not rejected level=%0d head=%h", level, head);
        push_valid = 0;

        // FRAME_START closes the frame, including a full frame, until retire.
        @(negedge clk); frame_start = 1;
        @(posedge clk); #1; frame_start = 0;
        if (!locked || push_ready) $fatal(1, "frame lock failed locked=%b ready=%b", locked, push_ready);
        @(negedge clk); frame_complete = 1;
        @(posedge clk); #1; frame_complete = 0;
        if (level != 0 || !empty || locked || !push_ready)
            $fatal(1, "complete did not flush/unlock level=%0d locked=%b", level, locked);

        // Error retirement must have the same flush/unlock semantics.
        push(128'h1234);
        @(negedge clk); frame_start = 1;
        @(posedge clk); #1; frame_start = 0;
        if (!locked) $fatal(1, "second frame did not lock");
        @(negedge clk); frame_error = 1;
        @(posedge clk); #1; frame_error = 0;
        if (level != 0 || locked || !push_ready) $fatal(1, "error did not flush/unlock");
        $display("[SCENE_FIFO] PASS depth=32 empty/full/overflow/lock/complete/error");
        #10 $finish;
    end
endmodule
