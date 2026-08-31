`timescale 1ns / 1ps
`include "../rtl/config_blade2x2sim.h"

// Canonical monitor for Blade 2x2's compact profile.  Its capture envelope is
// deliberately fixed to the scanout geometry (320x240), so a small-profile TB
// cannot accidentally inherit a board-scale framebuffer or monitor setting.
module dvi_monitor_blade2x2sim #(
    parameter integer FRAME_DUMP_LIMIT = 0,
    parameter [8*64-1:0] TESTCASE = "blade2x2sim",
    parameter [8*128-1:0] OUTPUT_ROOT = `DVI_FRAME_OUTPUT_ROOT
)(
    input video_clk, input resetn,
    input [4:0] video_red, input [5:0] video_green, input [4:0] video_blue,
    input video_hsync, input video_vsync, input video_de
);
    localparam integer BLADE2X2SIM_SCAN_W = 320;
    localparam integer BLADE2X2SIM_SCAN_H = 240;

    integer captured_frame_id;
    integer captured_frame_width;
    integer captured_frame_height;
    wire [8*224-1:0] frame_path;

    dvi_monitor #(
        .MAX_WIDTH(BLADE2X2SIM_SCAN_W), .MAX_HEIGHT(BLADE2X2SIM_SCAN_H),
        .EXPECT_WIDTH(BLADE2X2SIM_SCAN_W), .EXPECT_HEIGHT(BLADE2X2SIM_SCAN_H),
        .FRAME_DUMP_LIMIT(FRAME_DUMP_LIMIT), .TESTCASE(TESTCASE),
        .OUTPUT_ROOT(OUTPUT_ROOT)
    ) u_capture (
        .video_clk(video_clk), .resetn(resetn), .video_red(video_red),
        .video_green(video_green), .video_blue(video_blue),
        .video_hsync(video_hsync), .video_vsync(video_vsync), .video_de(video_de)
    );

    always @* begin
        captured_frame_id = u_capture.captured_frame_id;
        captured_frame_width = u_capture.captured_frame_width;
        captured_frame_height = u_capture.captured_frame_height;
    end
    assign frame_path = u_capture.frame_path;

    task flush_and_close;
        begin u_capture.flush_and_close(); end
    endtask
    task dump_captured_frame;
        input [8*64-1:0] label;
        begin u_capture.dump_captured_frame(label); end
    endtask

    task assert_captured_region_nonblack;
        input integer x0;
        input integer y0;
        input integer x1;
        input integer y1;
        input integer minimum_pixels;
        input [8*64-1:0] label;
        begin u_capture.assert_captured_region_nonblack(x0, y0, x1, y1, minimum_pixels, label); end
    endtask
endmodule
