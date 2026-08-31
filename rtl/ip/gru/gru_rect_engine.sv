`include "gru_defs.vh"

module gru_rect_engine (
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
    logic empty_rect;
    logic [`GRU_SEQ_W-1:0]   seq_id;
    logic [`GRU_COLOR_W-1:0] color_idx;
    logic [15:0]             color565;
    logic [`GRU_X_W-1:0]     clip_x0;
    logic [`GRU_X_W-1:0]     clip_x1;
    logic [`GRU_Y_W-1:0]     clip_y0;
    logic [`GRU_Y_W-1:0]     clip_y1;
    logic [`GRU_Y_W-1:0]     y_cur;

    wire [`GRU_X_W-1:0] clip_calc_x0;
    wire [`GRU_X_W-1:0] clip_calc_x1;
    wire [`GRU_Y_W-1:0] clip_calc_y0;
    wire [`GRU_Y_W-1:0] clip_calc_y1;
    wire clip_empty;

    gru_clipper u_gru_clipper (
        .x0_in    (cmd_data[`GRU_ECMD_X0_MSB:`GRU_ECMD_X0_LSB]),
        .y0_in    ({cmd_data[`GRU_ECMD_Y0_HI_BIT], cmd_data[`GRU_ECMD_Y0_MSB:`GRU_ECMD_Y0_LSB]}),
        .x1_in    (cmd_data[`GRU_ECMD_X1_MSB:`GRU_ECMD_X1_LSB]),
        .y1_in    ({cmd_data[`GRU_ECMD_Y1_HI_BIT], cmd_data[`GRU_ECMD_Y1_MSB:`GRU_ECMD_Y1_LSB]}),
        .frame_w  (frame_w),
        .frame_h  (frame_h),
        .x0_out   (clip_calc_x0),
        .y0_out   (clip_calc_y0),
        .x1_out   (clip_calc_x1),
        .y1_out   (clip_calc_y1),
        .empty    (clip_empty)
    );

    gru_colour_lut u_gru_colour_lut (
        .color_idx (color_idx),
        .rgb565    (color565)
    );

    assign cmd_ready = ~active;

    always_comb begin
        span_data = '0;
        span_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] = seq_id;
        span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB] = y_cur;
        span_data[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB] = clip_x0;
        span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = {1'b0, clip_x1} - {1'b0, clip_x0} + 10'd1;
        span_data[`GRU_SPAN_COLOR_MSB:`GRU_SPAN_COLOR_LSB] = color565;
        span_data[`GRU_SPAN_LAST_BIT] = (y_cur == clip_y1);
        if (empty_rect) begin
            span_data[`GRU_SPAN_LEN_MSB:`GRU_SPAN_LEN_LSB] = '0;
            span_data[`GRU_SPAN_LAST_BIT] = 1'b1;
        end
    end

    assign span_valid = active;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            active <= 1'b0;
            empty_rect <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            clip_x0 <= '0;
            clip_x1 <= '0;
            clip_y0 <= '0;
            clip_y1 <= '0;
            y_cur <= '0;
        end else if (clr) begin
            active <= 1'b0;
            empty_rect <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            clip_x0 <= '0;
            clip_x1 <= '0;
            clip_y0 <= '0;
            clip_y1 <= '0;
            y_cur <= '0;
        end else begin
            if (!active && cmd_valid) begin
                active <= 1'b1;
                seq_id <= cmd_data[`GRU_ECMD_SEQ_MSB:`GRU_ECMD_SEQ_LSB];
                color_idx <= cmd_data[`GRU_ECMD_COLOR_MSB:`GRU_ECMD_COLOR_LSB];
                clip_x0 <= clip_calc_x0;
                clip_x1 <= clip_calc_x1;
                clip_y0 <= clip_calc_y0;
                clip_y1 <= clip_calc_y1;
                y_cur <= clip_calc_y0;
                empty_rect <= clip_empty;
            end else if (active && span_valid && span_ready) begin
                if (empty_rect || (y_cur == clip_y1)) begin
                    active <= 1'b0;
                end else begin
                    y_cur <= y_cur + 1'b1;
                end
            end
        end
    end
endmodule
