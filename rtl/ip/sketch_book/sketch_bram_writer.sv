// RGB332 span writer.  Unit-stride spans are packed into eight-pixel beats;
// strided spans retain precise single-lane semantics.
module sketch_bram_writer #(
    parameter int SRC_W = 400,
    parameter int SRC_H = 300,
    parameter int ADDR_W = $clog2((SRC_W * SRC_H) / 8)
) (
    input  logic clk, input logic resetn, input logic clear, input logic target_page,
    input  logic span_valid, output logic span_ready,
    input  logic [15:0] span_x, input logic [15:0] span_y, input logic [15:0] span_len,
    input  logic [ADDR_W-1:0] span_step, input logic [7:0] span_color, input logic span_last,
    output logic busy, output logic cmd_done,
    output logic gru_we, output logic gru_page, output logic [ADDR_W-1:0] gru_addr,
    output logic [63:0] gru_wdata, output logic [7:0] gru_wstrb
);
    logic active, last_q, packed_q;
    logic [ADDR_W+2:0] pixel_addr_q;
    logic [ADDR_W-1:0] step_q;
    logic [15:0] remaining_q;
    logic [7:0] color_q;
    logic [3:0] lane_q;
    logic [15:0] beat_pixels;

    assign span_ready = !active;
    assign busy = active;
    assign gru_page = target_page;
    assign gru_wdata = {8{color_q}};

    function automatic logic [ADDR_W+2:0] calc_pixel_addr(input logic [15:0] x, input logic [15:0] y);
        begin
            if (SRC_W == 400)
                calc_pixel_addr = (y << 8) + (y << 7) + (y << 4) + x;
            else
                calc_pixel_addr = y * SRC_W + x;
        end
    endfunction

    always_comb begin
        beat_pixels = 16'd1;
        if (packed_q) begin
            beat_pixels = 16'(8 - lane_q);
            if (remaining_q < beat_pixels)
                beat_pixels = remaining_q;
        end
        gru_we = active && (remaining_q != 0);
        gru_addr = pixel_addr_q >> 3;
        gru_wstrb = '0;
        if (gru_we) begin
            if (packed_q) begin
                for (int lane = 0; lane < 8; lane = lane + 1)
                    if ((lane >= lane_q) && (lane < (lane_q + beat_pixels)))
                        gru_wstrb[lane] = 1'b1;
            end else
                gru_wstrb[pixel_addr_q[2:0]] = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            active <= 0; last_q <= 0; packed_q <= 0; pixel_addr_q <= '0;
            step_q <= '0; remaining_q <= '0; color_q <= '0; lane_q <= '0; cmd_done <= 0;
        end else if (clear) begin
            active <= 0; remaining_q <= '0; cmd_done <= 0;
        end else begin
            cmd_done <= 0;
            if (active) begin
                if (remaining_q <= beat_pixels) begin
                    active <= 0;
                    remaining_q <= 0;
                    if (last_q) cmd_done <= 1;
                end else begin
                    remaining_q <= remaining_q - beat_pixels;
                    if (packed_q) begin
                        pixel_addr_q <= pixel_addr_q + beat_pixels;
                        lane_q <= (lane_q + beat_pixels) & 4'h7;
                    end else
                        pixel_addr_q <= pixel_addr_q + step_q;
                end
            end else if (span_valid) begin
                if (span_len == 0) begin
                    if (span_last) cmd_done <= 1;
                end else begin
                    active <= 1; last_q <= span_last;
                    packed_q <= (span_step == ADDR_W'(1));
                    pixel_addr_q <= calc_pixel_addr(span_x, span_y);
                    step_q <= span_step; remaining_q <= span_len; color_q <= span_color;
                    lane_q <= calc_pixel_addr(span_x, span_y) & 3'h7;
                end
            end
        end
    end
endmodule
