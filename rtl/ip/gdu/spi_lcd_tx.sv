module spi_lcd_tx #(
    // Keep the standalone/subsystem simulations fast.  The board top
    // overrides these with the ILI9341-required delays for its 50 MHz aclk.
    parameter logic [31:0] INIT_RESET_DELAY_CYCLES     = 32'd1,
    parameter logic [31:0] INIT_SLEEP_OUT_DELAY_CYCLES = 32'd1,
    parameter logic [7:0]  INIT_MADCTL                 = 8'h48
) (
    input  logic        clk,
    input  logic        rstn,
    input  logic        start,
    input  logic        abort,
    input  logic [15:0] spi_clk_div,
    input  logic [15:0] win_x,
    input  logic [15:0] win_y,
    input  logic [15:0] win_w,
    input  logic [15:0] win_h,
    input  logic [15:0] pixel_data,
    input  logic        pixel_valid,
    output logic        pixel_ready,
    output logic        busy,
    output logic        done,
    output logic        spi_error,
    output logic [31:0] pixel_count,
    output logic [31:0] byte_count,
    output logic        tft_scl,
    output logic        tft_sdi,
    output logic        tft_cs,
    output logic        tft_rs
);

    typedef enum logic [2:0] {
        TX_INIT_SEND = 3'd0,
        TX_INIT_WAIT = 3'd1,
        TX_IDLE      = 3'd2,
        TX_PREAMBLE  = 3'd3,
        TX_PIXEL_WAIT= 3'd4,
        TX_PIXEL_LO  = 3'd5,
        TX_FINISH    = 3'd6
    } tx_state_t;

    tx_state_t state;
    logic [4:0] preamble_idx;
    logic [15:0] x0;
    logic [15:0] x1;
    logic [15:0] y0;
    logic [15:0] y1;
    logic [31:0] total_pixels;
    logic [15:0] latched_pixel;
    logic [2:0]  init_idx;
    logic [31:0] init_delay_count;
    logic        init_done;

    logic sending_byte;
    logic [7:0] cur_byte;
    logic [2:0] bit_idx;
    logic [15:0] scl_div_count;
    logic tft_scl_div;
    logic div_advance_pending;

    wire fast_spi_clk = (spi_clk_div == 16'd0);

    assign tft_scl = fast_spi_clk ? (sending_byte ? ~clk : 1'b0) : tft_scl_div;
    assign pixel_ready = init_done && (state == TX_PIXEL_WAIT) && !sending_byte &&
                         (pixel_count < total_pixels);

    // ILI9341 initialization.  The controller accepts the same command/data
    // SPI framing as the refresh stream, so it deliberately reuses load_byte.
    // A hardware RESET pin is not routed on this board; 0x01 provides the
    // controller reset, followed by the mandatory reset/sleep-out waits.
    function automatic [7:0] init_byte(input [2:0] idx);
        begin
            case (idx)
                3'd0: init_byte = 8'h01;       // SWRESET
                3'd1: init_byte = 8'h11;       // SLPOUT
                3'd2: init_byte = 8'h3a;       // COLMOD
                3'd3: init_byte = 8'h55;       // RGB565
                3'd4: init_byte = 8'h36;       // MADCTL
                3'd5: init_byte = INIT_MADCTL;
                3'd6: init_byte = 8'h29;       // DISPON
                default: init_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic logic init_is_data(input [2:0] idx);
        begin
            init_is_data = (idx == 3'd3) || (idx == 3'd5);
        end
    endfunction

    function automatic [7:0] preamble_byte(input [4:0] idx);
        begin
            case (idx)
                5'd0:  preamble_byte = 8'h2a;
                5'd1:  preamble_byte = x0[15:8];
                5'd2:  preamble_byte = x0[7:0];
                5'd3:  preamble_byte = x1[15:8];
                5'd4:  preamble_byte = x1[7:0];
                5'd5:  preamble_byte = 8'h2b;
                5'd6:  preamble_byte = y0[15:8];
                5'd7:  preamble_byte = y0[7:0];
                5'd8:  preamble_byte = y1[15:8];
                5'd9:  preamble_byte = y1[7:0];
                5'd10: preamble_byte = 8'h2c;
                default: preamble_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic logic preamble_is_data(input [4:0] idx);
        begin
            case (idx)
                5'd1, 5'd2, 5'd3, 5'd4,
                5'd6, 5'd7, 5'd8, 5'd9: preamble_is_data = 1'b1;
                default: preamble_is_data = 1'b0;
            endcase
        end
    endfunction

    task automatic load_byte(input [7:0] b, input logic is_data);
        begin
            cur_byte <= b;
            tft_rs <= is_data;
            tft_sdi <= b[7];
            bit_idx <= 3'd7;
            sending_byte <= 1'b1;
            tft_scl_div <= fast_spi_clk ? 1'b0 : 1'b1;
            scl_div_count <= spi_clk_div;
            div_advance_pending <= 1'b0;
            byte_count <= byte_count + 32'd1;
        end
    endtask

    task automatic advance_bit;
        begin
            if (bit_idx == 3'd0) begin
                sending_byte <= 1'b0;
            end else begin
                tft_sdi <= cur_byte[bit_idx - 3'd1];
                bit_idx <= bit_idx - 3'd1;
            end
        end
    endtask

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= TX_INIT_SEND;
            init_idx <= 3'd0;
            init_delay_count <= 32'd0;
            init_done <= 1'b0;
            preamble_idx <= 5'd0;
            x0 <= 16'd0;
            x1 <= 16'd0;
            y0 <= 16'd0;
            y1 <= 16'd0;
            total_pixels <= 32'd0;
            latched_pixel <= 16'd0;
            sending_byte <= 1'b0;
            cur_byte <= 8'd0;
            bit_idx <= 3'd0;
            scl_div_count <= 16'd0;
            tft_scl_div <= 1'b0;
            div_advance_pending <= 1'b0;
            pixel_count <= 32'd0;
            byte_count <= 32'd0;
            busy <= 1'b0;
            done <= 1'b0;
            spi_error <= 1'b0;
            tft_sdi <= 1'b0;
            tft_cs <= 1'b1;
            tft_rs <= 1'b0;
        end else begin
            done <= 1'b0;

            if (abort && init_done) begin
                state <= TX_IDLE;
                busy <= 1'b0;
                sending_byte <= 1'b0;
                scl_div_count <= 16'd0;
                tft_scl_div <= 1'b0;
                div_advance_pending <= 1'b0;
                tft_cs <= 1'b1;
                tft_rs <= 1'b0;
                tft_sdi <= 1'b0;
            end else if (sending_byte) begin
                if (fast_spi_clk) begin
                    advance_bit();
                end else if (div_advance_pending) begin
                    div_advance_pending <= 1'b0;
                    scl_div_count <= spi_clk_div;
                    advance_bit();
                end else if (tft_scl_div) begin
                    if (scl_div_count == 16'd0) begin
                        tft_scl_div <= 1'b0;
                        div_advance_pending <= 1'b1;
                    end else begin
                        scl_div_count <= scl_div_count - 16'd1;
                    end
                end else begin
                    if (scl_div_count == 16'd0) begin
                        tft_scl_div <= 1'b1;
                        scl_div_count <= spi_clk_div;
                    end else begin
                        scl_div_count <= scl_div_count - 16'd1;
                    end
                end
            end else begin
                case (state)
                    TX_INIT_SEND: begin
                        busy <= 1'b1;
                        tft_cs <= 1'b0;
                        load_byte(init_byte(init_idx), init_is_data(init_idx));
                        if ((init_idx == 3'd0) || (init_idx == 3'd1)) begin
                            init_delay_count <= (init_idx == 3'd0) ?
                                                INIT_RESET_DELAY_CYCLES :
                                                INIT_SLEEP_OUT_DELAY_CYCLES;
                            state <= TX_INIT_WAIT;
                        end else if (init_idx == 3'd6) begin
                            init_done <= 1'b1;
                            state <= TX_IDLE;
                        end else begin
                            init_idx <= init_idx + 3'd1;
                        end
                    end

                    TX_INIT_WAIT: begin
                        busy <= 1'b1;
                        tft_cs <= 1'b1;
                        tft_rs <= 1'b0;
                        tft_sdi <= 1'b0;
                        if (init_delay_count == 32'd0) begin
                            init_idx <= init_idx + 3'd1;
                            state <= TX_INIT_SEND;
                        end else begin
                            init_delay_count <= init_delay_count - 32'd1;
                        end
                    end

                    TX_IDLE: begin
                        busy <= 1'b0;
                        tft_cs <= 1'b1;
                        tft_rs <= 1'b0;
                        tft_sdi <= 1'b0;
                        if (start) begin
                            x0 <= win_x;
                            y0 <= win_y;
                            x1 <= win_x + win_w - 16'd1;
                            y1 <= win_y + win_h - 16'd1;
                            total_pixels <= {16'd0, win_w} * {16'd0, win_h};
                            pixel_count <= 32'd0;
                            byte_count <= 32'd0;
                            preamble_idx <= 5'd0;
                            busy <= 1'b1;
                            tft_cs <= 1'b0;
                            spi_error <= 1'b0;
                            state <= TX_PREAMBLE;
                        end
                    end

                    TX_PREAMBLE: begin
                        tft_cs <= 1'b0;
                        load_byte(preamble_byte(preamble_idx), preamble_is_data(preamble_idx));
                        if (preamble_idx == 5'd10) begin
                            state <= TX_PIXEL_WAIT;
                        end else begin
                            preamble_idx <= preamble_idx + 5'd1;
                        end
                    end

                    TX_PIXEL_WAIT: begin
                        tft_cs <= 1'b0;
                        tft_rs <= 1'b1;
                        if (pixel_count >= total_pixels) begin
                            state <= TX_FINISH;
                        end else if (pixel_valid) begin
                            latched_pixel <= pixel_data;
                            load_byte(pixel_data[15:8], 1'b1);
                            state <= TX_PIXEL_LO;
                        end
                    end

                    TX_PIXEL_LO: begin
                        tft_cs <= 1'b0;
                        load_byte(latched_pixel[7:0], 1'b1);
                        pixel_count <= pixel_count + 32'd1;
                        state <= TX_PIXEL_WAIT;
                    end

                    TX_FINISH: begin
                        tft_cs <= 1'b1;
                        tft_rs <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= TX_IDLE;
                    end

                    default: state <= TX_IDLE;
                endcase
            end
        end
    end

endmodule
