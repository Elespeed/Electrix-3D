`include "gru_defs.vh"

module gru_clear_engine (
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
    logic [`GRU_SEQ_W-1:0]   seq_id;
    logic [`GRU_COLOR_W-1:0] color_idx;
    logic [15:0]             color565;
    logic [15:0]             y_cur;

    gru_colour_lut u_gru_colour_lut (
        .color_idx (color_idx),
        .rgb565    (color565)
    );

    assign cmd_ready = ~active;

    always_comb begin
        span_data = '0;
        span_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] = seq_id;
        span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB] = y_cur[`GRU_Y_W-1:0];
        span_data[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB] = '0;
        span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = frame_w[`GRU_LEN_W-1:0];
        span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] = color565;
        span_data[`GRU_SPAN_LAST_BIT] = (frame_h <= 16'd1) || (y_cur == (frame_h - 16'd1));
        if ((frame_w == 16'd0) || (frame_h == 16'd0)) begin
            span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = '0;
            span_data[`GRU_SPAN_LAST_BIT] = 1'b1;
        end
    end

    assign span_valid = active;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            active <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            y_cur <= 16'd0;
        end else if (clr) begin
            active <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            y_cur <= 16'd0;
        end else begin
            if (!active && cmd_valid) begin
                active <= 1'b1;
                seq_id <= cmd_data[`GRU_ECMD_SEQ_MSB:`GRU_ECMD_SEQ_LSB];
                color_idx <= cmd_data[`GRU_ECMD_COLOR_MSB:`GRU_ECMD_COLOR_LSB];
                y_cur <= 16'd0;
            end else if (active && span_valid && span_ready) begin
                if ((frame_w == 16'd0) || (frame_h == 16'd0) || (y_cur == (frame_h - 16'd1))) begin
                    active <= 1'b0;
                end else begin
                    y_cur <= y_cur + 16'd1;
                end
            end
        end
    end
endmodule
