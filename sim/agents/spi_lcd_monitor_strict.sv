`timescale 1ns / 1ps
`include "../rtl/config.h"

module spi_lcd_monitor_strict #(
    parameter integer MAX_WIDTH = `FB_WIDTH,
    parameter integer MAX_HEIGHT = `FB_HEIGHT,
    parameter integer FRAME_DUMP_LIMIT = 0,
    parameter [8*80-1:0] TESTCASE = "spi_lcd_strict",
    parameter [8*128-1:0] OUTPUT_ROOT = `DVI_FRAME_OUTPUT_ROOT
) (
    input logic tft_scl,
    input logic resetn,
    input logic tft_sdi,
    input logic tft_cs,
    input logic tft_rs
);

    localparam integer MAX_PIXELS = MAX_WIDTH * MAX_HEIGHT;

    reg [15:0] gram565 [0:MAX_PIXELS-1];
    reg [7:0]  shift_reg;
    reg [2:0]  bit_count;
    reg [7:0]  current_cmd;
    reg [1:0]  cmd_data_idx;
    reg        memory_write_active;
    reg        pixel_hi_valid;
    reg [7:0]  pixel_hi_byte;
    reg [15:0] col_start;
    reg [15:0] col_end;
    reg [15:0] page_start;
    reg [15:0] page_end;
    reg [15:0] cur_x;
    reg [15:0] cur_y;
    reg        init_done;
    reg        fallback_to_cwd;

    integer refresh_count;
    integer last_pixel_count;
    integer last_byte_count;
    integer last_window_x;
    integer last_window_y;
    integer last_window_w;
    integer last_window_h;
    integer total_pixel_count;
    integer frame_id;
    integer meta_fd;

    reg [8*128-1:0] testcase_name;
    reg [8*192-1:0] run_dir;
    reg [8*224-1:0] raw_dir;
    reg [8*224-1:0] meta_path;
    reg [8*224-1:0] frame_path;
    time run_stamp;

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

    task automatic init_output_dir;
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
                        $display("[SPI_LCD_MON_STRICT][WARN] fallback to current simulation directory for outputs.");
                    end
                end

                raw_dir = run_dir;
                if (meta_fd != 0) begin
                    $fwrite(meta_fd, "source=sim_spi_strict_capture\n");
                    $fwrite(meta_fd, "testcase=%0s\n", testcase_name);
                    $fwrite(meta_fd, "run_stamp=%0t\n", run_stamp);
                    $fwrite(meta_fd, "columns=frame,width,height,sim_time,path\n");
                end else begin
                    $display("[SPI_LCD_MON_STRICT][WARN] open meta failed after path probing.");
                    $display("[SPI_LCD_MON_STRICT][WARN] Ensure %0s exists or pass +LCD_OUT_DIR.", `DVI_FRAME_OUTPUT_ROOT_REPO_REL);
                end

                if ((meta_fd != 0) && fallback_to_cwd) begin
                    $display("[SPI_LCD_MON_STRICT]============================================");
                    $display("[SPI_LCD_MON_STRICT] Frame output directory (fallback to cwd):");
                    $display("[SPI_LCD_MON_STRICT] %0s", raw_dir);
                    $display("[SPI_LCD_MON_STRICT]============================================");
                end else if (meta_fd != 0) begin
                    $display("[SPI_LCD_MON_STRICT]============================================");
                    $display("[SPI_LCD_MON_STRICT] Frame output directory:");
                    $display("[SPI_LCD_MON_STRICT] %0s", run_dir);
                    $display("[SPI_LCD_MON_STRICT]============================================");
                end
                init_done = 1'b1;
            end
        end
    endtask

    task automatic reset_runtime;
        integer i;
        begin
            shift_reg = 8'd0;
            bit_count = 3'd0;
            current_cmd = 8'd0;
            cmd_data_idx = 2'd0;
            memory_write_active = 1'b0;
            pixel_hi_valid = 1'b0;
            pixel_hi_byte = 8'd0;
            col_start = 16'd0;
            col_end = MAX_WIDTH - 1;
            page_start = 16'd0;
            page_end = MAX_HEIGHT - 1;
            cur_x = 16'd0;
            cur_y = 16'd0;
            refresh_count = 0;
            last_pixel_count = 0;
            last_byte_count = 0;
            last_window_x = 0;
            last_window_y = 0;
            last_window_w = 0;
            last_window_h = 0;
            total_pixel_count = 0;
            frame_id = 1;
            meta_fd = 0;
            init_done = 1'b0;
            testcase_name = TESTCASE;
            run_stamp = 0;
            fallback_to_cwd = 1'b0;
            for (i = 0; i < MAX_PIXELS; i = i + 1) begin
                gram565[i] = 16'h0000;
            end
        end
    endtask

    task automatic commit_pixel(input [15:0] pixel565);
        integer idx;
        integer capacity;
        begin
            capacity = (col_end - col_start + 1) * (page_end - page_start + 1);
            if (last_pixel_count >= capacity) begin
                $fatal(1, "[SPI_LCD_MON_STRICT] pixel overflow window=%0dx%0d count=%0d",
                       last_window_w, last_window_h, last_pixel_count);
            end
            if ((cur_x >= MAX_WIDTH) || (cur_y >= MAX_HEIGHT)) begin
                $fatal(1, "[SPI_LCD_MON_STRICT] pixel out of bounds x=%0d y=%0d", cur_x, cur_y);
            end
            idx = cur_y * MAX_WIDTH + cur_x;
            gram565[idx] = pixel565;
            last_pixel_count = last_pixel_count + 1;
            total_pixel_count = total_pixel_count + 1;
            if (cur_x >= col_end) begin
                cur_x = col_start;
                if (cur_y < page_end) begin
                    cur_y = cur_y + 16'd1;
                end
            end else begin
                cur_x = cur_x + 16'd1;
            end
        end
    endtask

    task automatic dump_current_frame;
        integer ppm_fd;
        integer x;
        integer y;
        integer idx;
        reg [15:0] pixel565;
        begin
            if (!init_done) begin
                init_output_dir();
            end

            if ((FRAME_DUMP_LIMIT != 0) && (frame_id > FRAME_DUMP_LIMIT)) begin
                frame_id = frame_id + 1;
            end else begin
                $sformat(frame_path, "%0s/%0s_t%0t_frame_%0d.ppm", raw_dir, testcase_name, run_stamp, frame_id);
                ppm_fd = $fopen(frame_path, "w");
                if (ppm_fd == 0) begin
                    if (!fallback_to_cwd) begin
                        raw_dir = ".";
                        fallback_to_cwd = 1'b1;
                        $sformat(frame_path, "%0s_t%0t_frame_%0d.ppm", testcase_name, run_stamp, frame_id);
                        ppm_fd = $fopen(frame_path, "w");
                    end
                    if (ppm_fd == 0) begin
                        $display("[SPI_LCD_MON_STRICT][WARN] open frame failed: %0s", frame_path);
                        $display("[SPI_LCD_MON_STRICT][WARN] Try +LCD_OUT_DIR=D:/.../%0s", `DVI_FRAME_OUTPUT_ROOT_REPO_REL);
                    end
                end
                if (ppm_fd != 0) begin
                    $fwrite(ppm_fd, "P3\n");
                    $fwrite(ppm_fd, "%0d %0d\n", MAX_WIDTH, MAX_HEIGHT);
                    $fwrite(ppm_fd, "255\n");
                    for (y = 0; y < MAX_HEIGHT; y = y + 1) begin
                        for (x = 0; x < MAX_WIDTH; x = x + 1) begin
                            idx = y * MAX_WIDTH + x;
                            pixel565 = gram565[idx];
                            $fwrite(ppm_fd, "%0d %0d %0d\n",
                                    expand5_to_8(pixel565[15:11]),
                                    expand6_to_8(pixel565[10:5]),
                                    expand5_to_8(pixel565[4:0]));
                        end
                    end
                    $fclose(ppm_fd);
                    if (meta_fd != 0) begin
                        $fwrite(meta_fd, "%0d,%0d,%0d,%0t,%0s\n", frame_id, MAX_WIDTH, MAX_HEIGHT, $time, frame_path);
                    end
                    $display("[SPI_LCD_MON_STRICT] dumped frame=%0d size=%0dx%0d time=%0t",
                             frame_id, MAX_WIDTH, MAX_HEIGHT, $time);
                    $display("[SPI_LCD_MON_STRICT] file saved to: %0s", frame_path);
                end
                frame_id = frame_id + 1;
            end
        end
    endtask

    task automatic start_memory_write;
        begin
            if (!init_done) begin
                init_output_dir();
            end
            if ((col_end < col_start) || (page_end < page_start) ||
                (col_end >= MAX_WIDTH) || (page_end >= MAX_HEIGHT)) begin
                $fatal(1, "[SPI_LCD_MON_STRICT] invalid window x=%0d..%0d y=%0d..%0d",
                       col_start, col_end, page_start, page_end);
            end
            memory_write_active = 1'b1;
            pixel_hi_valid = 1'b0;
            cur_x = col_start;
            cur_y = page_start;
            last_window_x = col_start;
            last_window_y = page_start;
            last_window_w = col_end - col_start + 1;
            last_window_h = page_end - page_start + 1;
            last_pixel_count = 0;
            last_byte_count = 0;
        end
    endtask

    task automatic process_byte(input [7:0] rx_byte, input logic is_data);
        reg [15:0] pixel565;
        begin
            if (!is_data) begin
                current_cmd = rx_byte;
                cmd_data_idx = 2'd0;
                pixel_hi_valid = 1'b0;
                if (rx_byte == 8'h2c) begin
                    start_memory_write();
                end else begin
                    memory_write_active = 1'b0;
                end
            end else begin
                case (current_cmd)
                    8'h2a: begin
                        case (cmd_data_idx)
                            2'd0: col_start[15:8] = rx_byte;
                            2'd1: col_start[7:0]  = rx_byte;
                            2'd2: col_end[15:8]   = rx_byte;
                            2'd3: col_end[7:0]    = rx_byte;
                        endcase
                        cmd_data_idx = cmd_data_idx + 2'd1;
                    end
                    8'h2b: begin
                        case (cmd_data_idx)
                            2'd0: page_start[15:8] = rx_byte;
                            2'd1: page_start[7:0]  = rx_byte;
                            2'd2: page_end[15:8]   = rx_byte;
                            2'd3: page_end[7:0]    = rx_byte;
                        endcase
                        cmd_data_idx = cmd_data_idx + 2'd1;
                    end
                    8'h2c: begin
                        if (!memory_write_active) begin
                            $fatal(1, "[SPI_LCD_MON_STRICT] pixel data before memory write");
                        end
                        last_byte_count = last_byte_count + 1;
                        if (!pixel_hi_valid) begin
                            pixel_hi_byte = rx_byte;
                            pixel_hi_valid = 1'b1;
                        end else begin
                            pixel565 = {pixel_hi_byte, rx_byte};
                            pixel_hi_valid = 1'b0;
                            commit_pixel(pixel565);
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    endtask

    task flush_and_close;
        begin
            if (meta_fd != 0) begin
                $fclose(meta_fd);
                meta_fd = 0;
            end
        end
    endtask

    initial begin
        reset_runtime();
    end

    final begin
        if (meta_fd != 0) begin
            $fclose(meta_fd);
        end
    end

    always @(negedge tft_scl or negedge resetn) begin
        reg [7:0] next_byte;
        if (!resetn) begin
            reset_runtime();
        end else if (!tft_cs) begin
            next_byte = {shift_reg[6:0], tft_sdi};
            shift_reg = next_byte;
            if (bit_count == 3'd7) begin
                bit_count = 3'd0;
                process_byte(next_byte, tft_rs);
            end else begin
                bit_count = bit_count + 3'd1;
            end
        end
    end

    always @(posedge tft_cs or negedge resetn) begin
        integer expected_pixels;
        if (!resetn) begin
            reset_runtime();
        end else begin
            if (memory_write_active) begin
                expected_pixels = last_window_w * last_window_h;
                if (pixel_hi_valid) begin
                    $fatal(1, "[SPI_LCD_MON_STRICT] odd pixel byte count");
                end
                if (last_pixel_count != expected_pixels) begin
                    $fatal(1, "[SPI_LCD_MON_STRICT] pixel count mismatch got=%0d expected=%0d window=%0dx%0d",
                           last_pixel_count, expected_pixels, last_window_w, last_window_h);
                end
                refresh_count = refresh_count + 1;
                dump_current_frame();
                $display("[SPI_LCD_MON_STRICT] refresh=%0d window=(%0d,%0d %0dx%0d) pixels=%0d testcase=%0s t=%0t",
                         refresh_count, last_window_x, last_window_y, last_window_w,
                         last_window_h, last_pixel_count, TESTCASE, $time);
            end
            memory_write_active = 1'b0;
            pixel_hi_valid = 1'b0;
            bit_count = 3'd0;
            shift_reg = 8'd0;
        end
    end

endmodule
