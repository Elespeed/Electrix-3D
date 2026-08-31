`timescale 1ns / 1ps
`include "../rtl/config.h"

module lcd_monitor #(
    // 🔧 使用 config.h 中的参数作为默认值
    parameter integer MAX_WIDTH = `FB_WIDTH,
    parameter integer MAX_HEIGHT = `FB_HEIGHT,
    parameter integer FRAME_DUMP_LIMIT = 0,
    parameter [8*64-1:0] TESTCASE = "default_case",
    parameter [8*128-1:0] OUTPUT_ROOT = `DVI_FRAME_OUTPUT_ROOT,
    parameter FRAME_END_ON_VSYNC_RISE = 1'b1,
    parameter LINE_END_ON_HSYNC_RISE = 1'b1
)(
    input               lcd_pclk,
    input               resetn,
    input [15:0]        lcd_rgb,
    input               lcd_hsync,
    input               lcd_vsync,
    input               lcd_de
);

localparam integer MAX_PIXELS = MAX_WIDTH * MAX_HEIGHT;

reg [7:0] frame_r [0:MAX_PIXELS-1];
reg [7:0] frame_g [0:MAX_PIXELS-1];
reg [7:0] frame_b [0:MAX_PIXELS-1];
reg [7:0] captured_frame_r [0:MAX_PIXELS-1];
reg [7:0] captured_frame_g [0:MAX_PIXELS-1];
reg [7:0] captured_frame_b [0:MAX_PIXELS-1];

reg hsync_d;
reg vsync_d;
reg line_has_de;
reg frame_dirty;
reg init_done;

integer x_pos;
integer y_pos;
integer frame_width;
integer frame_height;
integer frame_id;
integer captured_frame_id;
integer captured_frame_width;
integer captured_frame_height;
integer meta_fd;
integer pixel_index;

reg [8*128-1:0] testcase_name;
reg [8*192-1:0] run_dir;
reg [8*224-1:0] raw_dir;
reg [8*224-1:0] meta_path;
reg [8*224-1:0] frame_path;
time run_stamp;
reg fallback_to_cwd;

wire line_end_edge = LINE_END_ON_HSYNC_RISE ? (~hsync_d & lcd_hsync) : (hsync_d & ~lcd_hsync);
wire frame_end_edge = FRAME_END_ON_VSYNC_RISE ? (~vsync_d & lcd_vsync) : (vsync_d & ~lcd_vsync);

function [7:0] expand5_to_8;
    input [4:0] v;
    begin
        expand5_to_8 = {v, v[4:2]};
    end
endfunction

function [7:0] expand6_to_8;
    input [5:0] v;
    begin
        expand6_to_8 = {v, v[5:4]};
    end
endfunction

task init_output_dir;
    integer plusarg_rc;
    integer outdir_plusarg_rc;
    integer meta_fd_try;
    reg dir_found;
    begin
        if (!init_done) begin
            testcase_name = TESTCASE;
            plusarg_rc = $value$plusargs("TESTCASE=%s", testcase_name);
            outdir_plusarg_rc = $value$plusargs("LCD_OUT_DIR=%s", run_dir);

            run_stamp = $time;
            dir_found = 1'b0;
            meta_fd = 0;

            if (outdir_plusarg_rc) begin
                $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                meta_fd_try = $fopen(meta_path, "w");
                if (meta_fd_try != 0) begin
                    meta_fd = meta_fd_try;
                    dir_found = 1'b1;
                end
            end
            else begin
                run_dir = OUTPUT_ROOT;
                $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                meta_fd_try = $fopen(meta_path, "w");
                if (meta_fd_try != 0) begin
                    meta_fd = meta_fd_try;
                    dir_found = 1'b1;
                end

                if (!dir_found) begin
                    run_dir = `DVI_FRAME_OUTPUT_ROOT_FALLBACK_1;
                    $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                    meta_fd_try = $fopen(meta_path, "w");
                    if (meta_fd_try != 0) begin
                        meta_fd = meta_fd_try;
                        dir_found = 1'b1;
                    end
                end

                if (!dir_found) begin
                    run_dir = `DVI_FRAME_OUTPUT_ROOT_FALLBACK_2;
                    $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                    meta_fd_try = $fopen(meta_path, "w");
                    if (meta_fd_try != 0) begin
                        meta_fd = meta_fd_try;
                        dir_found = 1'b1;
                    end
                end

                if (!dir_found) begin
                    run_dir = `DVI_FRAME_OUTPUT_ROOT_FALLBACK_3;
                    $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                    meta_fd_try = $fopen(meta_path, "w");
                    if (meta_fd_try != 0) begin
                        meta_fd = meta_fd_try;
                        dir_found = 1'b1;
                    end
                end

                if (!dir_found) begin
                    run_dir = `DVI_FRAME_OUTPUT_ROOT_FALLBACK_4;
                    $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                    meta_fd_try = $fopen(meta_path, "w");
                    if (meta_fd_try != 0) begin
                        meta_fd = meta_fd_try;
                        dir_found = 1'b1;
                    end
                end

                if (!dir_found) begin
                    run_dir = `DVI_FRAME_OUTPUT_ROOT_FALLBACK_5;
                    $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                    meta_fd_try = $fopen(meta_path, "w");
                    if (meta_fd_try != 0) begin
                        meta_fd = meta_fd_try;
                        dir_found = 1'b1;
                    end
                end

                if (!dir_found) begin
                    run_dir = `DVI_FRAME_OUTPUT_ROOT_FALLBACK_6;
                    $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                    meta_fd_try = $fopen(meta_path, "w");
                    if (meta_fd_try != 0) begin
                        meta_fd = meta_fd_try;
                        dir_found = 1'b1;
                    end
                end

                if (!dir_found) begin
                    run_dir = `DVI_FRAME_OUTPUT_ROOT_FALLBACK_7;
                    $sformat(meta_path, "%0s/meta_%0s_t%0t.txt", run_dir, testcase_name, run_stamp);
                    meta_fd_try = $fopen(meta_path, "w");
                    if (meta_fd_try != 0) begin
                        meta_fd = meta_fd_try;
                        dir_found = 1'b1;
                    end
                end
            end

            if (!dir_found) begin
                run_dir = ".";
                $sformat(meta_path, "meta_%0s_t%0t.txt", testcase_name, run_stamp);
                meta_fd = $fopen(meta_path, "w");
                if (meta_fd != 0) begin
                    dir_found = 1'b1;
                    fallback_to_cwd = 1'b1;
                    $display("[LCD_MON][WARN] fallback to current simulation directory for outputs.");
                end
            end

            raw_dir = run_dir;
            if (meta_fd != 0) begin
                $fwrite(meta_fd, "source=sim_raw_capture\n");
                $fwrite(meta_fd, "testcase=%0s\n", testcase_name);
                $fwrite(meta_fd, "run_stamp=%0t\n", run_stamp);
                $fwrite(meta_fd, "columns=frame,width,height,sim_time,path\n");
            end
            else begin
                $display("[LCD_MON][WARN] open meta failed after path probing.");
                $display("[LCD_MON][WARN] Ensure %0s exists or pass +LCD_OUT_DIR.", `DVI_FRAME_OUTPUT_ROOT_REPO_REL);
            end

            if ((meta_fd != 0) && fallback_to_cwd) begin
                $display("[LCD_MON]============================================");
                $display("[LCD_MON] Frame output directory (fallback to cwd):");
                $display("[LCD_MON] %0s", raw_dir);
                $display("[LCD_MON]============================================");
            end
            else if (meta_fd != 0) begin
                $display("[LCD_MON]============================================");
                $display("[LCD_MON] Frame output directory:");
                $display("[LCD_MON] %0s", run_dir);
                $display("[LCD_MON]============================================");
            end
            init_done = 1'b1;
        end
    end
endtask

task dump_current_frame;
    integer ppm_fd;
    integer x;
    integer y;
    integer idx;
    integer out_r;
    integer out_g;
    integer out_b;
    begin
        if (!init_done) begin
            init_output_dir();
        end

        if ((FRAME_DUMP_LIMIT != 0) && (frame_id > FRAME_DUMP_LIMIT)) begin
            frame_id = frame_id + 1;
        end
        else if ((frame_width > 0) && (frame_height > 0)) begin
            for (idx = 0; idx < MAX_PIXELS; idx = idx + 1) begin
                captured_frame_r[idx] = frame_r[idx];
                captured_frame_g[idx] = frame_g[idx];
                captured_frame_b[idx] = frame_b[idx];
            end
            captured_frame_id = frame_id;
            captured_frame_width = frame_width;
            captured_frame_height = frame_height;

            $sformat(frame_path, "%0s/%0s_t%0t_frame_%06d.ppm", raw_dir, testcase_name, run_stamp, frame_id);
            ppm_fd = $fopen(frame_path, "w");
            if (ppm_fd == 0) begin
                if (!fallback_to_cwd) begin
                    raw_dir = ".";
                    fallback_to_cwd = 1'b1;
                    $sformat(frame_path, "%0s_t%0t_frame_%06d.ppm", testcase_name, run_stamp, frame_id);
                    ppm_fd = $fopen(frame_path, "w");
                end
                if (ppm_fd == 0) begin
                    $display("[LCD_MON][WARN] open frame failed: %0s", frame_path);
                    $display("[LCD_MON][WARN] Try +LCD_OUT_DIR=D:/.../%0s", `DVI_FRAME_OUTPUT_ROOT_REPO_REL);
                end
            end
            if (ppm_fd != 0) begin
                $fwrite(ppm_fd, "P3\n");
                $fwrite(ppm_fd, "%0d %0d\n", frame_width, frame_height);
                $fwrite(ppm_fd, "255\n");
                for (y = 0; y < frame_height; y = y + 1) begin
                    for (x = 0; x < frame_width; x = x + 1) begin
                        idx = y * MAX_WIDTH + x;
                        out_r = ((^frame_r[idx]) === 1'bx) ? 0 : frame_r[idx];
                        out_g = ((^frame_g[idx]) === 1'bx) ? 0 : frame_g[idx];
                        out_b = ((^frame_b[idx]) === 1'bx) ? 0 : frame_b[idx];
                        $fwrite(ppm_fd, "%0d %0d %0d\n", out_r, out_g, out_b);
                    end
                end
                $fclose(ppm_fd);
                if (meta_fd != 0) begin
                    $fwrite(meta_fd, "%0d,%0d,%0d,%0t,%0s\n", frame_id, frame_width, frame_height, $time, frame_path);
                end
                $display("[LCD_MON] dumped frame=%0d size=%0dx%0d time=%0t", frame_id, frame_width, frame_height, $time);
                $display("[LCD_MON] file saved to: %0s", frame_path);
            end
            frame_id = frame_id + 1;
        end
    end
endtask

task flush_and_close;
    begin
        if (line_has_de && ((y_pos + 1) > frame_height)) begin
            frame_height = y_pos + 1;
        end
        if (frame_dirty) begin
            dump_current_frame();
            frame_dirty = 1'b0;
            line_has_de = 1'b0;
        end
        if (meta_fd != 0) begin
            $fclose(meta_fd);
            meta_fd = 0;
        end
    end
endtask

initial begin
    hsync_d = 1'b0;
    vsync_d = 1'b0;
    line_has_de = 1'b0;
    frame_dirty = 1'b0;
    init_done = 1'b0;
    x_pos = 0;
    y_pos = 0;
    frame_width = 0;
    frame_height = 0;
    frame_id = 1;
    captured_frame_id = 0;
    captured_frame_width = 0;
    captured_frame_height = 0;
    meta_fd = 0;
    testcase_name = TESTCASE;
    run_stamp = 0;
    fallback_to_cwd = 1'b0;
end

always @(posedge lcd_pclk) begin
    if (!resetn) begin
        hsync_d <= lcd_hsync;
        vsync_d <= lcd_vsync;
        line_has_de <= 1'b0;
        frame_dirty <= 1'b0;
        x_pos <= 0;
        y_pos <= 0;
        frame_width <= 0;
        frame_height <= 0;
    end
    else begin
        if (!init_done && lcd_de) begin
            init_output_dir();
        end

        if (lcd_de) begin
            if ((x_pos < MAX_WIDTH) && (y_pos < MAX_HEIGHT)) begin
                pixel_index = y_pos * MAX_WIDTH + x_pos;
                frame_r[pixel_index] <= ((^lcd_rgb[15:11]) === 1'bx) ? 8'd0 : expand5_to_8(lcd_rgb[15:11]);
                frame_g[pixel_index] <= ((^lcd_rgb[10:5]) === 1'bx) ? 8'd0 : expand6_to_8(lcd_rgb[10:5]);
                frame_b[pixel_index] <= ((^lcd_rgb[4:0]) === 1'bx) ? 8'd0 : expand5_to_8(lcd_rgb[4:0]);
            end
            x_pos <= x_pos + 1;
            if ((x_pos + 1) > frame_width) begin
                frame_width <= x_pos + 1;
            end
            line_has_de <= 1'b1;
            frame_dirty <= 1'b1;
        end

        if (line_end_edge) begin
            if (line_has_de) begin
                if ((y_pos + 1) > frame_height) begin
                    frame_height <= y_pos + 1;
                end
                y_pos <= y_pos + 1;
            end
            x_pos <= 0;
            line_has_de <= 1'b0;
        end

        if (frame_end_edge) begin
            if (line_has_de && ((y_pos + 1) > frame_height)) begin
`ifdef VERILATOR_BUILD
                // BLKANDNBLK: a clocked block must assign frame_height
                // consistently non-blocking. This value only feeds the PPM dump
                // height (dump_current_frame); the captured_frame_* arrays the TB
                // compares are copied in full above regardless. ModelSim keeps
                // the original blocking form so its dump height is unchanged.
                frame_height <= y_pos + 1;
`else
                frame_height = y_pos + 1;
`endif
            end
            if (frame_dirty) begin
                dump_current_frame();
            end
            x_pos <= 0;
            y_pos <= 0;
            frame_width <= 0;
            frame_height <= 0;
            line_has_de <= 1'b0;
            frame_dirty <= 1'b0;
        end

        hsync_d <= lcd_hsync;
        vsync_d <= lcd_vsync;
    end
end

endmodule
