`include "gru_defs.vh"

module gru_line_engine (
    input  logic                      clk,
    input  logic                      rstn,
    input  logic                      clr,
    input  logic [15:0]               frame_w,
    input  logic [15:0]               frame_h,
    input  logic                      cmd_valid,
    output logic                      cmd_ready,
    input  logic [`GRU_ENGINE_CMD_W-1:0] cmd_data,
    output logic                      span_valid,
    input  logic                      span_ready,
    output logic [`GRU_SPAN_W-1:0]    span_data
);
    logic active;
    logic dummy_pending;
    logic emitted_any;
    logic [`GRU_SEQ_W-1:0]   seq_id;
    logic [`GRU_COLOR_W-1:0] color_idx;
    logic [15:0]             color565;
    logic signed [15:0]      x_cur;
    logic signed [15:0]      y_cur;
    logic signed [15:0]      x_end;
    logic signed [15:0]      y_end;
    logic signed [15:0]      dx_abs;
    logic signed [15:0]      dy_neg_abs;
    logic signed [15:0]      err_acc;
    logic signed [15:0]      sx_step;
    logic signed [15:0]      sy_step;
    logic point_in_bounds;
    logic point_is_last;

    gru_colour_lut u_gru_colour_lut (
        .color_idx (color_idx),
        .rgb565    (color565)
    );

    assign cmd_ready = ~active;

    always_comb begin
        point_in_bounds = (x_cur >= 0) && (y_cur >= 0) &&
                          (x_cur < $signed({1'b0, frame_w})) &&
                          (y_cur < $signed({1'b0, frame_h}));
        point_is_last = (x_cur == x_end) && (y_cur == y_end);
        span_valid = active & (dummy_pending | point_in_bounds);

        span_data = '0;
        span_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] = seq_id;
        span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB] = y_cur[`GRU_Y_W-1:0];
        span_data[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB] = x_cur[`GRU_X_W-1:0];
        span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = 10'd1;
        span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] = color565;
        span_data[`GRU_SPAN_LAST_BIT] = point_is_last;
        if (dummy_pending) begin
            span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB] = '0;
            span_data[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB] = '0;
            span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = '0;
            span_data[`GRU_SPAN_LAST_BIT] = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        logic signed [15:0] next_x;
        logic signed [15:0] next_y;
        logic signed [15:0] next_err;
        logic signed [15:0] e2;
        logic signed [15:0] x0_init;
        logic signed [15:0] y0_init;
        logic signed [15:0] x1_init;
        logic signed [15:0] y1_init;
        logic signed [15:0] dx_init;
        logic signed [15:0] dy_init;

        if (!rstn) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            emitted_any <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            x_cur <= '0;
            y_cur <= '0;
            x_end <= '0;
            y_end <= '0;
            dx_abs <= '0;
            dy_neg_abs <= '0;
            err_acc <= '0;
            sx_step <= '0;
            sy_step <= '0;
        end else if (clr) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            emitted_any <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            x_cur <= '0;
            y_cur <= '0;
            x_end <= '0;
            y_end <= '0;
            dx_abs <= '0;
            dy_neg_abs <= '0;
            err_acc <= '0;
            sx_step <= '0;
            sy_step <= '0;
        end else begin
            if (!active && cmd_valid) begin
                x0_init = $signed({7'd0, cmd_data[`GRU_ECMD_X0_MSB:`GRU_ECMD_X0_LSB]});
                y0_init = $signed({7'd0, cmd_data[`GRU_ECMD_Y0_HI_BIT], cmd_data[`GRU_ECMD_Y0_MSB:`GRU_ECMD_Y0_LSB]});
                x1_init = $signed({7'd0, cmd_data[`GRU_ECMD_X1_MSB:`GRU_ECMD_X1_LSB]});
                y1_init = $signed({7'd0, cmd_data[`GRU_ECMD_Y1_HI_BIT], cmd_data[`GRU_ECMD_Y1_MSB:`GRU_ECMD_Y1_LSB]});
                dx_init = (x1_init >= x0_init) ? (x1_init - x0_init) : (x0_init - x1_init);
                dy_init = (y1_init >= y0_init) ? (y1_init - y0_init) : (y0_init - y1_init);

                active <= 1'b1;
                dummy_pending <= 1'b0;
                emitted_any <= 1'b0;
                seq_id <= cmd_data[`GRU_ECMD_SEQ_MSB:`GRU_ECMD_SEQ_LSB];
                color_idx <= cmd_data[`GRU_ECMD_COLOR_MSB:`GRU_ECMD_COLOR_LSB];
                x_cur <= x0_init;
                y_cur <= y0_init;
                x_end <= x1_init;
                y_end <= y1_init;
                dx_abs <= dx_init;
                dy_neg_abs <= -dy_init;
                sx_step <= (x0_init <= x1_init) ? 16'sd1 : -16'sd1;
                sy_step <= (y0_init <= y1_init) ? 16'sd1 : -16'sd1;
                err_acc <= dx_init - dy_init;
            end else if (active) begin
                if (dummy_pending && span_ready) begin
                    active <= 1'b0;
                    dummy_pending <= 1'b0;
                end else if (point_in_bounds) begin
                    if (span_ready) begin
                        emitted_any <= 1'b1;
                        if (point_is_last) begin
                            active <= 1'b0;
                        end else begin
                            next_x = x_cur;
                            next_y = y_cur;
                            next_err = err_acc;
                            e2 = err_acc <<< 1;
                            if (e2 >= dy_neg_abs) begin
                                next_err = next_err + dy_neg_abs;
                                next_x = next_x + sx_step;
                            end
                            if (e2 <= dx_abs) begin
                                next_err = next_err + dx_abs;
                                next_y = next_y + sy_step;
                            end
                            x_cur <= next_x;
                            y_cur <= next_y;
                            err_acc <= next_err;
                        end
                    end
                end else begin
                    if (point_is_last) begin
                        // If the final line point clips out, still emit a
                        // terminating dummy span so the writer can retire.
                        dummy_pending <= 1'b1;
                    end else begin
                        next_x = x_cur;
                        next_y = y_cur;
                        next_err = err_acc;
                        e2 = err_acc <<< 1;
                        if (e2 >= dy_neg_abs) begin
                            next_err = next_err + dy_neg_abs;
                            next_x = next_x + sx_step;
                        end
                        if (e2 <= dx_abs) begin
                            next_err = next_err + dx_abs;
                            next_y = next_y + sy_step;
                        end
                        x_cur <= next_x;
                        y_cur <= next_y;
                        err_acc <= next_err;
                    end
                end
            end
        end
    end
endmodule
