`include "gru_defs.vh"

module gru_glyph_engine (
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
    logic [1:0]              font_id;
    logic [7:0]              ascii;
    logic [`GRU_X_W-1:0]     base_x;
    logic [`GRU_Y_W-1:0]     base_y;
    logic [3:0]              gx;
    logic [3:0]              gy;
    logic                    font_on;
    logic [3:0]              glyph_w;
    logic [3:0]              glyph_h;
    logic signed [15:0]      px;
    logic signed [15:0]      py;
    logic point_in_bounds;
    logic point_is_last;

    gru_font_rom u_gru_font_rom (
        .font_id  (font_id),
        .ascii    (ascii),
        .x        (gx),
        .y        (gy),
        .pixel_on (font_on),
        .glyph_w  (glyph_w),
        .glyph_h  (glyph_h)
    );

    gru_colour_lut u_gru_colour_lut (
        .color_idx (color_idx),
        .rgb565    (color565)
    );

    assign cmd_ready = ~active;

    always_comb begin
        px = $signed({7'd0, base_x}) + $signed({12'd0, gx});
        py = $signed({8'd0, base_y}) + $signed({12'd0, gy});
        point_in_bounds = font_on &&
                          (px >= 0) && (py >= 0) &&
                          (px < $signed({1'b0, frame_w})) &&
                          (py < $signed({1'b0, frame_h}));
        point_is_last = (gx == (glyph_w - 4'd1)) && (gy == (glyph_h - 4'd1));

        span_valid = active & (dummy_pending | point_in_bounds);
        span_data = '0;
        span_data[`GRU_SPAN_SEQ_MSB:`GRU_SPAN_SEQ_LSB] = seq_id;
        span_data[`GRU_SPAN_Y_MSB:`GRU_SPAN_Y_LSB] = py[`GRU_Y_W-1:0];
        span_data[`GRU_SPAN_X_MSB:`GRU_SPAN_X_LSB] = px[`GRU_X_W-1:0];
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
        if (!rstn) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            emitted_any <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            font_id <= '0;
            ascii <= 8'd0;
            base_x <= '0;
            base_y <= '0;
            gx <= '0;
            gy <= '0;
        end else if (clr) begin
            active <= 1'b0;
            dummy_pending <= 1'b0;
            emitted_any <= 1'b0;
            seq_id <= '0;
            color_idx <= '0;
            font_id <= '0;
            ascii <= 8'd0;
            base_x <= '0;
            base_y <= '0;
            gx <= '0;
            gy <= '0;
        end else begin
            if (!active && cmd_valid) begin
                active <= 1'b1;
                dummy_pending <= 1'b0;
                emitted_any <= 1'b0;
                seq_id <= cmd_data[`GRU_ECMD_SEQ_MSB:`GRU_ECMD_SEQ_LSB];
                color_idx <= cmd_data[`GRU_ECMD_COLOR_MSB:`GRU_ECMD_COLOR_LSB];
                font_id <= cmd_data[`GRU_ECMD_FONT_MSB:`GRU_ECMD_FONT_LSB];
                base_x <= cmd_data[`GRU_ECMD_X0_MSB:`GRU_ECMD_X0_LSB];
                base_y <= {cmd_data[`GRU_ECMD_Y0_HI_BIT], cmd_data[`GRU_ECMD_Y0_MSB:`GRU_ECMD_Y0_LSB]};
                ascii <= cmd_data[`GRU_ECMD_X1_LSB +: 8];
                gx <= 4'd0;
                gy <= 4'd0;
            end else if (active) begin
                if (dummy_pending && span_ready) begin
                    active <= 1'b0;
                    dummy_pending <= 1'b0;
                end else if (point_in_bounds) begin
                    if (span_ready) begin
                        emitted_any <= 1'b1;
                        if (point_is_last) begin
                            active <= 1'b0;
                        end else if (gx == (glyph_w - 4'd1)) begin
                            gx <= 4'd0;
                            gy <= gy + 4'd1;
                        end else begin
                            gx <= gx + 4'd1;
                        end
                    end
                end else begin
                    if (point_is_last) begin
                        // If the final glyph point does not emit a visible span,
                        // still send a terminating dummy span so the writer can retire.
                        dummy_pending <= 1'b1;
                    end else if (gx == (glyph_w - 4'd1)) begin
                        gx <= 4'd0;
                        gy <= gy + 4'd1;
                    end else begin
                        gx <= gx + 4'd1;
                    end
                end
            end
        end
    end
endmodule
