`timescale 1ns / 1ps
`include "../rtl/config.h"

module spi_lcd_monitor #(
    parameter integer MAX_WIDTH = `FB_WIDTH,
    parameter integer MAX_HEIGHT = `FB_HEIGHT,
    parameter integer FRAME_DUMP_LIMIT = 0,
    parameter [8*64-1:0] TESTCASE = "default_case",
    parameter [8*128-1:0] OUTPUT_ROOT = `DVI_FRAME_OUTPUT_ROOT
)(
    input               tft_scl,
    input               resetn,
    input               tft_sdi,
    input               tft_cs,
    input               tft_rs
);

localparam integer MAX_PIXELS = MAX_WIDTH * MAX_HEIGHT;

reg [7:0] frame_r [0:MAX_PIXELS-1];
reg [7:0] frame_g [0:MAX_PIXELS-1];
reg [7:0] frame_b [0:MAX_PIXELS-1];

reg init_done;
reg frame_dirty;
reg [7:0] shift_reg;
reg [2:0] bit_count;
reg [7:0] current_cmd;
reg memory_write_active;
reg pixel_hi_valid;
reg [7:0] pixel_hi_byte;
reg [15:0] col_start;
reg [15:0] col_end;
reg [15:0] page_start;
reg [15:0] page_end;
reg [15:0] cur_x;
reg [15:0] cur_y;
reg [1:0] cmd_data_idx;

integer frame_width;
integer frame_height;
integer frame_id;
integer meta_fd;
integer pixel_index;

reg [8*128-1:0] testcase_name;
reg [8*192-1:0] run_dir;
reg [8*224-1:0] raw_dir;
reg [8*224-1:0] meta_path;
reg [8*224-1:0] frame_path;
time run_stamp;
reg fallback_to_cwd;

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
                    $display("[SPI_LCD_MON][WARN] fallback to current simulation directory for outputs.");
                end
            end

            raw_dir = run_dir;
            if (meta_fd != 0) begin
                $fwrite(meta_fd, "source=sim_spi_capture\n");
                $fwrite(meta_fd, "testcase=%0s\n", testcase_name);
                $fwrite(meta_fd, "run_stamp=%0t\n", run_stamp);
                $fwrite(meta_fd, "columns=frame,width,height,sim_time,path\n");
            end
            else begin
                $display("[SPI_LCD_MON][WARN] open meta failed after path probing.");
                $display("[SPI_LCD_MON][WARN] Ensure %0s exists or pass +LCD_OUT_DIR.", `DVI_FRAME_OUTPUT_ROOT_REPO_REL);
            end

            if ((meta_fd != 0) && fallback_to_cwd) begin
                $display("[SPI_LCD_MON]============================================");
                $display("[SPI_LCD_MON] Frame output directory (fallback to cwd):");
                $display("[SPI_LCD_MON] %0s", raw_dir);
                $display("[SPI_LCD_MON]============================================");
            end
            else if (meta_fd != 0) begin
                $display("[SPI_LCD_MON]============================================");
                $display("[SPI_LCD_MON] Frame output directory:");
                $display("[SPI_LCD_MON] %0s", run_dir);
                $display("[SPI_LCD_MON]============================================");
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
                    $display("[SPI_LCD_MON][WARN] open frame failed: %0s", frame_path);
                    $display("[SPI_LCD_MON][WARN] Try +LCD_OUT_DIR=D:/.../%0s", `DVI_FRAME_OUTPUT_ROOT_REPO_REL);
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
                $display("[SPI_LCD_MON] dumped frame=%0d size=%0dx%0d time=%0t", frame_id, frame_width, frame_height, $time);
                $display("[SPI_LCD_MON] file saved to: %0s", frame_path);
            end
            frame_id = frame_id + 1;
        end
    end
endtask

task automatic commit_pixel(input [15:0] pixel565);
    integer idx;
    begin
        if ((cur_x < MAX_WIDTH) && (cur_y < MAX_HEIGHT)) begin
            idx = cur_y * MAX_WIDTH + cur_x;
            frame_r[idx] = ((^pixel565[15:11]) === 1'bx) ? 8'd0 : expand5_to_8(pixel565[15:11]);
            frame_g[idx] = ((^pixel565[10:5]) === 1'bx) ? 8'd0 : expand6_to_8(pixel565[10:5]);
            frame_b[idx] = ((^pixel565[4:0]) === 1'bx) ? 8'd0 : expand5_to_8(pixel565[4:0]);
            frame_dirty = 1'b1;
        end

        if (cur_x >= col_end) begin
            cur_x = col_start;
            if (cur_y < page_end) begin
                cur_y = cur_y + 16'd1;
            end
        end
        else begin
            cur_x = cur_x + 16'd1;
        end
    end
endtask

task automatic process_rx_byte(
    input [7:0] rx_byte,
    input       is_data
);
    reg [15:0] pixel565;
    begin
        if (!init_done) begin
            init_output_dir();
        end

        if (!is_data) begin
            current_cmd = rx_byte;
            cmd_data_idx = 2'd0;
            pixel_hi_valid = 1'b0;
            memory_write_active = 1'b0;
            if (rx_byte == 8'h2c) begin
                memory_write_active = 1'b1;
                cur_x = col_start;
                cur_y = page_start;
                frame_width = col_end - col_start + 1;
                frame_height = page_end - page_start + 1;
            end
        end
        else begin
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
                    if (!pixel_hi_valid) begin
                        pixel_hi_byte = rx_byte;
                        pixel_hi_valid = 1'b1;
                    end
                    else begin
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
        if (frame_dirty) begin
            dump_current_frame();
            frame_dirty = 1'b0;
        end
        if (meta_fd != 0) begin
            $fclose(meta_fd);
            meta_fd = 0;
        end
    end
endtask

initial begin
    init_done = 1'b0;
    frame_dirty = 1'b0;
    shift_reg = 8'd0;
    bit_count = 3'd0;
    current_cmd = 8'd0;
    memory_write_active = 1'b0;
    pixel_hi_valid = 1'b0;
    pixel_hi_byte = 8'd0;
    col_start = 16'd0;
    col_end = MAX_WIDTH - 1;
    page_start = 16'd0;
    page_end = MAX_HEIGHT - 1;
    cur_x = 16'd0;
    cur_y = 16'd0;
    cmd_data_idx = 2'd0;
    frame_width = 0;
    frame_height = 0;
    frame_id = 1;
    meta_fd = 0;
    testcase_name = TESTCASE;
    run_stamp = 0;
    fallback_to_cwd = 1'b0;
end

// The bridge preloads SDI before SCL rises and updates the next bit on the
// source clock edge that also drops SCL. Sampling on SCL falling edge avoids
// byte-boundary races in simulation and matches the bit that stayed valid
// throughout the preceding high phase.
always @(negedge tft_scl or negedge resetn) begin
    reg [7:0] next_byte;
    if (!resetn) begin
        frame_dirty = 1'b0;
        shift_reg = 8'd0;
        bit_count = 3'd0;
        current_cmd = 8'd0;
        memory_write_active = 1'b0;
        pixel_hi_valid = 1'b0;
        col_start = 16'd0;
        col_end = MAX_WIDTH - 1;
        page_start = 16'd0;
        page_end = MAX_HEIGHT - 1;
        cur_x = 16'd0;
        cur_y = 16'd0;
        cmd_data_idx = 2'd0;
        frame_width = 0;
        frame_height = 0;
    end
    else if (!tft_cs) begin
        next_byte = {shift_reg[6:0], tft_sdi};
        shift_reg = next_byte;
        if (bit_count == 3'd7) begin
            bit_count = 3'd0;
            process_rx_byte(next_byte, tft_rs);
        end
        else begin
            bit_count = bit_count + 3'd1;
        end
    end
end

always @(posedge tft_cs or negedge resetn) begin
    if (!resetn) begin
        shift_reg = 8'd0;
        bit_count = 3'd0;
        memory_write_active = 1'b0;
        pixel_hi_valid = 1'b0;
    end
    else begin
        if (memory_write_active && frame_dirty) begin
            dump_current_frame();
            frame_dirty = 1'b0;
        end
        memory_write_active = 1'b0;
        pixel_hi_valid = 1'b0;
        bit_count = 3'd0;
        shift_reg = 8'd0;
    end
end

endmodule
