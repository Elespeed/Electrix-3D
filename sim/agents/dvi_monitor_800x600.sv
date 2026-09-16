`timescale 1ns / 1ps

// Standalone 800x600 monitor for sketch_book.  It intentionally has no
// dependency on the project framebuffer configuration headers.
module dvi_monitor_800x600 #(
    parameter integer FRAME_DUMP_LIMIT = 0,
    parameter [8*64-1:0] TESTCASE = "default_case",
    parameter [8*128-1:0] OUTPUT_ROOT = "../../../sim/frame_output",
    parameter FRAME_END_ON_VSYNC_RISE = 1'b1,
    parameter LINE_END_ON_HSYNC_RISE = 1'b1
)(
    input               video_clk,
    input               resetn,
    input [4:0]         video_red,
    input [5:0]         video_green,
    input [4:0]         video_blue,
    input               video_hsync,
    input               video_vsync,
    input               video_de
);

localparam integer MAX_WIDTH = 800;
localparam integer MAX_HEIGHT = 600;
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
reg [31:0] captured_frame_crc;
integer meta_fd;
integer pixel_index;

reg [8*128-1:0] testcase_name;
reg [8*192-1:0] run_dir;
reg [8*224-1:0] raw_dir;
reg [8*224-1:0] meta_path;
reg [8*224-1:0] frame_path;
time run_stamp;
reg fallback_to_cwd;

wire line_end_edge = LINE_END_ON_HSYNC_RISE ? (~hsync_d & video_hsync) : (hsync_d & ~video_hsync);
wire frame_end_edge = FRAME_END_ON_VSYNC_RISE ? (~vsync_d & video_vsync) : (vsync_d & ~video_vsync);

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

// FNV-1a over the completed display frame in row-major RGB byte order.  The
// monitor stores expanded 8-bit RGB values, so this is independent of the
// source bus packing and is suitable for cross-backend frame equivalence.
function [31:0] fnv1a_byte;
    input [31:0] hash;
    input [7:0] value;
    begin
        fnv1a_byte = (hash ^ value) * 32'h01000193;
    end
endfunction

task compute_captured_crc;
    integer crc_idx;
    reg [31:0] crc_value;
    begin
        crc_value = 32'h811c9dc5;
        for (crc_idx = 0; crc_idx < MAX_PIXELS; crc_idx = crc_idx + 1) begin
            crc_value = fnv1a_byte(crc_value, frame_r[crc_idx]);
            crc_value = fnv1a_byte(crc_value, frame_g[crc_idx]);
            crc_value = fnv1a_byte(crc_value, frame_b[crc_idx]);
        end
        captured_frame_crc = crc_value;
    end
endtask

task init_output_dir;
    integer plusarg_rc;
    integer outdir_plusarg_rc;
    integer meta_fd_try;
    reg dir_found;
    begin
        if (!init_done) begin
            testcase_name = TESTCASE;
            plusarg_rc = $value$plusargs("TESTCASE=%s", testcase_name);
            outdir_plusarg_rc = $value$plusargs("DVI_OUT_DIR=%s", run_dir);

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
                    run_dir = ".";
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
                    $display("[DVI_MON][WARN] fallback to current simulation directory for outputs.");
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
                $display("[DVI_MON][WARN] open meta failed after path probing.");
                $display("[DVI_MON][WARN] Ensure sim/frame_output exists or pass +DVI_OUT_DIR.");
            end

            if ((meta_fd != 0) && fallback_to_cwd) begin
                $display("[DVI_MON]============================================");
                $display("[DVI_MON] Frame output directory (fallback to cwd):");
                $display("[DVI_MON] %0s", raw_dir);
                $display("[DVI_MON]============================================");
            end
            else if (meta_fd != 0) begin
                $display("[DVI_MON]============================================");
                $display("[DVI_MON] Frame output directory:");
                $display("[DVI_MON] %0s", run_dir);
                $display("[DVI_MON]============================================");
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
    integer do_dump;
    begin
        if (!init_done) begin
            init_output_dir();
        end

        if ((frame_width > 0) && (frame_height > 0)) begin
            if ((frame_width != MAX_WIDTH) || (frame_height != MAX_HEIGHT)) begin
                $fatal(1, "[DVI_MON] captured size %0dx%0d, expected %0dx%0d",
                       frame_width, frame_height, MAX_WIDTH, MAX_HEIGHT);
            end
            for (idx = 0; idx < MAX_PIXELS; idx = idx + 1) begin
                captured_frame_r[idx] = frame_r[idx];
                captured_frame_g[idx] = frame_g[idx];
                captured_frame_b[idx] = frame_b[idx];
            end
            captured_frame_id = frame_id;
            captured_frame_width = frame_width;
            captured_frame_height = frame_height;
            compute_captured_crc();
            $display("[DVI_MON][CRC] frame=%0d crc=%08x width=%0d height=%0d", frame_id,
                     captured_frame_crc, frame_width, frame_height);

            do_dump = (FRAME_DUMP_LIMIT == 0) || (frame_id <= FRAME_DUMP_LIMIT);
            if (do_dump) begin
            $sformat(frame_path, "%0s/%0s_%04d.ppm", raw_dir, testcase_name, frame_id);
            ppm_fd = $fopen(frame_path, "w");
            if (ppm_fd == 0) begin
                if (!fallback_to_cwd) begin
                    raw_dir = ".";
                    fallback_to_cwd = 1'b1;
                    $sformat(frame_path, "%0s_%04d.ppm", testcase_name, frame_id);
                    ppm_fd = $fopen(frame_path, "w");
                end
                if (ppm_fd == 0) begin
                    $display("[DVI_MON][WARN] open frame failed: %0s", frame_path);
                    $display("[DVI_MON][WARN] Try +DVI_OUT_DIR=D:/.../sim/frame_output");
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
                $display("[DVI_MON] dumped frame=%0d size=%0dx%0d time=%0t", frame_id, frame_width, frame_height, $time);
                $display("[DVI_MON] file saved to: %0s", frame_path);
            end
            end
            frame_id = frame_id + 1;
        end
    end
endtask

// Save the last completed frame under a stable scenario name.  Testbenches use
// this after their pixel assertions so visual evidence never depends on which
// startup frames happened to be emitted first.
task dump_captured_frame;
    input [8*64-1:0] label;
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
        if ((captured_frame_width <= 0) || (captured_frame_height <= 0)) begin
            $fatal(1, "[DVI_MON] named capture requested before a completed frame");
        end
        $sformat(frame_path, "%0s/%0s.ppm", raw_dir, label);
        ppm_fd = $fopen(frame_path, "w");
        if (ppm_fd == 0) begin
            $fatal(1, "[DVI_MON] unable to write named capture: %0s", frame_path);
        end
        $fwrite(ppm_fd, "P3\n");
        $fwrite(ppm_fd, "%0d %0d\n", captured_frame_width, captured_frame_height);
        $fwrite(ppm_fd, "255\n");
        for (y = 0; y < captured_frame_height; y = y + 1) begin
            for (x = 0; x < captured_frame_width; x = x + 1) begin
                idx = y * MAX_WIDTH + x;
                out_r = ((^captured_frame_r[idx]) === 1'bx) ? 0 : captured_frame_r[idx];
                out_g = ((^captured_frame_g[idx]) === 1'bx) ? 0 : captured_frame_g[idx];
                out_b = ((^captured_frame_b[idx]) === 1'bx) ? 0 : captured_frame_b[idx];
                $fwrite(ppm_fd, "%0d %0d %0d\n", out_r, out_g, out_b);
            end
        end
        $fclose(ppm_fd);
        $display("[DVI_MON] named capture saved to: %0s", frame_path);
        $display("[DVI_MON][CRC] named=%0s frame=%0d crc=%08x width=%0d height=%0d",
                 label, captured_frame_id, captured_frame_crc,
                 captured_frame_width, captured_frame_height);
    end
endtask

// Check that a content region contains rendered pixels.  This deliberately
// operates on the completed-frame copy so it is safe to call after a swap.
task assert_captured_region_nonblack;
    input integer x0;
    input integer y0;
    input integer x1;
    input integer y1;
    input integer minimum_pixels;
    input [8*64-1:0] label;
    integer x;
    integer y;
    integer idx;
    integer nonblack_pixels;
    begin
        if ((captured_frame_width <= 0) || (captured_frame_height <= 0)) begin
            $fatal(1, "[DVI_MON] region check requested before a completed frame");
        end
        nonblack_pixels = 0;
        for (y = y0; (y < y1) && (y < captured_frame_height); y = y + 1) begin
            for (x = x0; (x < x1) && (x < captured_frame_width); x = x + 1) begin
                if ((x >= 0) && (y >= 0)) begin
                    idx = y * MAX_WIDTH + x;
                    if ((captured_frame_r[idx] != 0) || (captured_frame_g[idx] != 0) || (captured_frame_b[idx] != 0)) begin
                        nonblack_pixels = nonblack_pixels + 1;
                    end
                end
            end
        end
        if (nonblack_pixels < minimum_pixels) begin
            $fatal(1, "[DVI_MON] %0s: only %0d non-black pixels in (%0d,%0d)-(%0d,%0d), expected at least %0d", label, nonblack_pixels, x0, y0, x1, y1, minimum_pixels);
        end
        $display("[DVI_MON] %0s: %0d non-black pixels in (%0d,%0d)-(%0d,%0d)", label, nonblack_pixels, x0, y0, x1, y1);
    end
endtask

task flush_and_close;
    begin
        if (line_has_de && ((y_pos + 1) > frame_height)) begin
            frame_height = y_pos + 1;
        end
        if (frame_dirty) begin
            // A test can finish while a new raster is in progress.  That
            // partial raster is not a frame and must not turn an otherwise
            // successful test into a size assertion failure.  Complete
            // frames are captured on v-sync; callers that need final visual
            // evidence use dump_captured_frame().
            if ((frame_width == MAX_WIDTH) && (frame_height == MAX_HEIGHT)) begin
                dump_current_frame();
            end
            else begin
                $display("[DVI_MON] discarding partial frame at shutdown: %0dx%0d", frame_width, frame_height);
            end
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
    captured_frame_crc = 32'h00000000;
    meta_fd = 0;
    testcase_name = TESTCASE;
    run_stamp = 0;
    fallback_to_cwd = 1'b0;
end

always @(posedge video_clk) begin
    if (!resetn) begin
        hsync_d <= video_hsync;
        vsync_d <= video_vsync;
        line_has_de <= 1'b0;
        frame_dirty <= 1'b0;
        x_pos <= 0;
        y_pos <= 0;
        frame_width <= 0;
        frame_height <= 0;
    end
    else begin
        if (!init_done && video_de) begin
            init_output_dir();
        end

        if (video_de) begin
            if ((x_pos < MAX_WIDTH) && (y_pos < MAX_HEIGHT)) begin
                pixel_index = y_pos * MAX_WIDTH + x_pos;
                frame_r[pixel_index] <= ((^video_red) === 1'bx) ? 8'd0 : expand5_to_8(video_red);
                frame_g[pixel_index] <= ((^video_green) === 1'bx) ? 8'd0 : expand6_to_8(video_green);
                frame_b[pixel_index] <= ((^video_blue) === 1'bx) ? 8'd0 : expand5_to_8(video_blue);
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
                frame_height = y_pos + 1;
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

        hsync_d <= video_hsync;
        vsync_d <= video_vsync;
    end
end

endmodule
