`include "gru_defs.vh"

module gru_depth_rw (
    input  logic                        clk,
    input  logic                        rstn,
    input  logic                        clr,
    input  logic [31:0]                 fb_base,
    input  logic [31:0]                 depth_base,
    input  logic [31:0]                 stride,
    input  logic [15:0]                 frame_w,
    input  logic [15:0]                 frame_h,
    input  logic                        cmd_valid,
    output logic                        cmd_ready,
    input  logic [`GRU_DEPTH_CMD_W-1:0] cmd_data,
    output logic                        cmd_done_pulse,
    output logic                        axi_error_pulse,
    output logic                        depth_busy,
    output logic [4:0]                  m_axi_arid,
    output logic [31:0]                 m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,
    output logic                        m_axi_arlock,
    output logic [3:0]                  m_axi_arcache,
    output logic [2:0]                  m_axi_arprot,
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,
    input  logic [4:0]                  m_axi_rid,
    input  logic [127:0]                m_axi_rdata,
    input  logic [1:0]                  m_axi_rresp,
    input  logic                        m_axi_rlast,
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready,
    output logic [4:0]                  m_axi_awid,
    output logic [31:0]                 m_axi_awaddr,
    output logic [7:0]                  m_axi_awlen,
    output logic [2:0]                  m_axi_awsize,
    output logic [1:0]                  m_axi_awburst,
    output logic                        m_axi_awlock,
    output logic [3:0]                  m_axi_awcache,
    output logic [2:0]                  m_axi_awprot,
    output logic                        m_axi_awvalid,
    input  logic                        m_axi_awready,
    output logic [127:0]                m_axi_wdata,
    output logic [15:0]                 m_axi_wstrb,
    output logic                        m_axi_wlast,
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,
    input  logic [4:0]                  m_axi_bid,
    input  logic [1:0]                  m_axi_bresp,
    input  logic                        m_axi_bvalid,
    output logic                        m_axi_bready
);
    typedef enum logic [4:0] {
        S_IDLE,
        S_CLEAR_ISSUE,
        S_CLEAR_WAIT_B,
        S_TRI_SETUP_EDGE,
        S_TRI_SETUP_NUMER,
        S_TRI_SETUP_DEPTH,
        S_TRI_SETUP_DX,
        S_TRI_SETUP_DY,
        S_TRI_SCAN,
        S_TRI_REQ_RD,
        S_TRI_WAIT_RD,
        S_TRI_COMPARE,
        S_TRI_DEPTH_WRITE,
        S_TRI_DEPTH_WAIT_B,
        S_TRI_COLOR_WRITE,
        S_TRI_COLOR_WAIT_B,
        S_DONE
    } state_t;

    state_t state_q;

    logic [`GRU_SEQ_W-1:0]   seq_q;
    logic [`GRU_OPCODE_W-1:0] opcode_q;
    logic [`GRU_COLOR_W-1:0] color_idx_q;
    logic signed [15:0]      x0_q, y0_q, x1_q, y1_q, x2_q, y2_q;
    logic [15:0]             z0_q, z1_q, z2_q;
    logic [15:0]             clear_depth_q;
    logic                    depth_enable_q;
    logic                    depth_write_enable_q;
    logic                    depth_lequal_q;
    logic signed [31:0]      area_q;
    logic [31:0]             area_abs_q;
    logic                    area_neg_q;
    logic signed [15:0]      min_x_q, max_x_q, min_y_q, max_y_q;
    logic signed [15:0]      cur_x_q, cur_y_q;
    logic [15:0]             pixel_depth_q;
    logic [15:0]             old_depth_q;
    logic                    pixel_inside_now;
    logic                    depth_compare_pass;
    logic [15:0]             color565;

    logic [31:0]             depth_addr_row_q;
    logic [31:0]             depth_addr_cur_q;
    logic [31:0]             color_addr_row_q;
    logic [31:0]             color_addr_cur_q;

    logic signed [31:0]      w0_row_q, w1_row_q, w2_row_q;
    logic signed [31:0]      w0_cur_q, w1_cur_q, w2_cur_q;
    logic signed [31:0]      w0_dx_q, w1_dx_q, w2_dx_q;
    logic signed [31:0]      w0_dy_q, w1_dy_q, w2_dy_q;

    logic [31:0]             depth_row_q;
    logic [31:0]             depth_cur_q;
    logic [31:0]             depth_rem_row_q;
    logic [31:0]             depth_rem_cur_q;
    logic signed [31:0]      depth_step_x_q;
    logic signed [31:0]      depth_step_y_q;
    logic [31:0]             depth_rem_x_q;
    logic [31:0]             depth_rem_y_q;

    logic signed [47:0]      numer_row_setup_q;
    logic signed [47:0]      numer_dx_setup_q;
    logic signed [47:0]      numer_dy_setup_q;

    logic [31:0]             beat_addr;
    logic [3:0]              lane_byte;
    logic [127:0]            write_payload;
    logic [15:0]             write_strobe;

    gru_colour_lut u_gru_colour_lut (
        .color_idx (color_idx_q),
        .rgb565    (color565)
    );

    gru_depth_test u_gru_depth_test (
        .old_depth      (old_depth_q),
        .new_depth      (pixel_depth_q),
        .compare_lequal (depth_lequal_q),
        .pass           (depth_compare_pass)
    );

    function automatic logic signed [31:0] edge_value(
        input logic signed [15:0] px,
        input logic signed [15:0] py,
        input logic signed [15:0] ax,
        input logic signed [15:0] ay,
        input logic signed [15:0] bx,
        input logic signed [15:0] by
    );
        begin
            edge_value = ((px - ax) * (by - ay)) - ((py - ay) * (bx - ax));
        end
    endfunction

    function automatic logic signed [47:0] depth_numer_from_weights(
        input logic signed [31:0] w0,
        input logic signed [31:0] w1,
        input logic signed [31:0] w2,
        input logic [15:0]        z0,
        input logic [15:0]        z1,
        input logic [15:0]        z2
    );
        logic signed [47:0] term0;
        logic signed [47:0] term1;
        logic signed [47:0] term2;
        begin
            term0 = $signed({{16{w0[31]}}, w0}) * $signed({1'b0, z0});
            term1 = $signed({{16{w1[31]}}, w1}) * $signed({1'b0, z1});
            term2 = $signed({{16{w2[31]}}, w2}) * $signed({1'b0, z2});
            depth_numer_from_weights = term0 + term1 + term2;
        end
    endfunction

    function automatic logic signed [47:0] normalize_numer(
        input logic signed [47:0] numer,
        input logic               area_neg
    );
        begin
            normalize_numer = area_neg ? -numer : numer;
        end
    endfunction

    function automatic logic pixel_inside_from_weights(
        input logic signed [31:0] w0,
        input logic signed [31:0] w1,
        input logic signed [31:0] w2,
        input logic               area_neg
    );
        begin
            if (area_neg) begin
                pixel_inside_from_weights = (w0 <= 0) && (w1 <= 0) && (w2 <= 0);
            end else begin
                pixel_inside_from_weights = (w0 >= 0) && (w1 >= 0) && (w2 >= 0);
            end
        end
    endfunction

    task automatic advance_clear_pixel;
        begin
            if (cur_x_q == $signed({1'b0, frame_w}) - 16'sd1) begin
                cur_x_q <= 16'sd0;
                cur_y_q <= cur_y_q + 16'sd1;
                depth_addr_row_q <= depth_addr_row_q + stride;
                depth_addr_cur_q <= depth_addr_row_q + stride;
            end else begin
                cur_x_q <= cur_x_q + 16'sd1;
                depth_addr_cur_q <= depth_addr_cur_q + 32'd2;
            end
        end
    endtask

    task automatic advance_triangle_pixel;
        logic [32:0]      rem_sum;
        logic [32:0]      row_rem_sum;
        logic [31:0]      next_row_rem;
        logic signed [31:0] next_row_depth;
        begin
            if (cur_x_q == max_x_q) begin
                row_rem_sum = {1'b0, depth_rem_row_q} + {1'b0, depth_rem_y_q};
                if (row_rem_sum >= {1'b0, area_abs_q}) begin
                    next_row_depth = depth_row_q + depth_step_y_q + 32'sd1;
                    next_row_rem = row_rem_sum[31:0] - area_abs_q;
                end else begin
                    next_row_depth = depth_row_q + depth_step_y_q;
                    next_row_rem = row_rem_sum[31:0];
                end

                cur_x_q <= min_x_q;
                cur_y_q <= cur_y_q + 16'sd1;
                depth_addr_row_q <= depth_addr_row_q + stride;
                depth_addr_cur_q <= depth_addr_row_q + stride;
                color_addr_row_q <= color_addr_row_q + stride;
                color_addr_cur_q <= color_addr_row_q + stride;

                w0_row_q <= w0_row_q + w0_dy_q;
                w1_row_q <= w1_row_q + w1_dy_q;
                w2_row_q <= w2_row_q + w2_dy_q;
                w0_cur_q <= w0_row_q + w0_dy_q;
                w1_cur_q <= w1_row_q + w1_dy_q;
                w2_cur_q <= w2_row_q + w2_dy_q;

                depth_row_q <= next_row_depth;
                depth_cur_q <= next_row_depth;
                depth_rem_row_q <= next_row_rem;
                depth_rem_cur_q <= next_row_rem;
            end else begin
                rem_sum = {1'b0, depth_rem_cur_q} + {1'b0, depth_rem_x_q};
                cur_x_q <= cur_x_q + 16'sd1;
                depth_addr_cur_q <= depth_addr_cur_q + 32'd2;
                color_addr_cur_q <= color_addr_cur_q + 32'd2;
                w0_cur_q <= w0_cur_q + w0_dx_q;
                w1_cur_q <= w1_cur_q + w1_dx_q;
                w2_cur_q <= w2_cur_q + w2_dx_q;
                if (rem_sum >= {1'b0, area_abs_q}) begin
                    depth_cur_q <= depth_cur_q + depth_step_x_q + 32'sd1;
                    depth_rem_cur_q <= rem_sum[31:0] - area_abs_q;
                end else begin
                    depth_cur_q <= depth_cur_q + depth_step_x_q;
                    depth_rem_cur_q <= rem_sum[31:0];
                end
            end
        end
    endtask

    always_comb begin
        pixel_inside_now = pixel_inside_from_weights(w0_cur_q, w1_cur_q, w2_cur_q, area_neg_q);

        beat_addr = 32'd0;
        lane_byte = 4'd0;
        write_payload = 128'd0;
        write_strobe = 16'd0;

        if ((state_q == S_CLEAR_ISSUE) || (state_q == S_CLEAR_WAIT_B) ||
            (state_q == S_TRI_DEPTH_WRITE) || (state_q == S_TRI_DEPTH_WAIT_B)) begin
            beat_addr = depth_addr_cur_q & 32'hffff_fff0;
            lane_byte = depth_addr_cur_q[3:0];
            write_payload[(lane_byte * 8) +: 16] =
                (state_q == S_CLEAR_ISSUE || state_q == S_CLEAR_WAIT_B) ? clear_depth_q : pixel_depth_q;
            write_strobe = 16'h0003 << lane_byte;
        end else if ((state_q == S_TRI_COLOR_WRITE) || (state_q == S_TRI_COLOR_WAIT_B)) begin
            beat_addr = color_addr_cur_q & 32'hffff_fff0;
            lane_byte = color_addr_cur_q[3:0];
            write_payload[(lane_byte * 8) +: 16] = color565;
            write_strobe = 16'h0003 << lane_byte;
        end
    end

    assign cmd_ready = (state_q == S_IDLE);
    assign depth_busy = (state_q != S_IDLE);
    assign cmd_done_pulse = (state_q == S_DONE);

    assign m_axi_arid = 5'd0;
    assign m_axi_araddr = depth_addr_cur_q & 32'hffff_fff0;
    assign m_axi_arlen = 8'd0;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'd0;
    assign m_axi_arprot = 3'd0;
    assign m_axi_arvalid = (state_q == S_TRI_REQ_RD);
    assign m_axi_rready = (state_q == S_TRI_WAIT_RD);

    assign m_axi_awid = 5'd0;
    assign m_axi_awaddr = beat_addr;
    assign m_axi_awlen = 8'd0;
    assign m_axi_awsize = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock = 1'b0;
    assign m_axi_awcache = 4'd0;
    assign m_axi_awprot = 3'd0;
    assign m_axi_awvalid = (state_q == S_CLEAR_ISSUE) || (state_q == S_TRI_DEPTH_WRITE) || (state_q == S_TRI_COLOR_WRITE);
    assign m_axi_wdata = write_payload;
    assign m_axi_wstrb = write_strobe;
    assign m_axi_wlast = 1'b1;
    assign m_axi_wvalid = (state_q == S_CLEAR_ISSUE) || (state_q == S_TRI_DEPTH_WRITE) || (state_q == S_TRI_COLOR_WRITE);
    assign m_axi_bready = (state_q == S_CLEAR_WAIT_B) || (state_q == S_TRI_DEPTH_WAIT_B) || (state_q == S_TRI_COLOR_WAIT_B);

    always_ff @(posedge clk) begin
        logic signed [15:0] min_x;
        logic signed [15:0] max_x;
        logic signed [15:0] min_y;
        logic signed [15:0] max_y;
        logic signed [31:0] area_now;
        logic signed [15:0] x0_v, y0_v, x1_v, y1_v, x2_v, y2_v;
        logic signed [31:0] w0_now, w1_now, w2_now;
        logic signed [31:0] w0_dx_now, w1_dx_now, w2_dx_now;
        logic signed [31:0] w0_dy_now, w1_dy_now, w2_dy_now;
        logic signed [47:0] numer_now;
        logic signed [47:0] div_q;
        logic signed [47:0] div_r;
        logic signed [31:0] step_now;
        logic [31:0]        rem_now;
        logic signed [32:0] area_abs_signed;
        if (!rstn) begin
            state_q <= S_IDLE;
            seq_q <= '0;
            opcode_q <= '0;
            color_idx_q <= '0;
            x0_q <= '0; y0_q <= '0; x1_q <= '0; y1_q <= '0; x2_q <= '0; y2_q <= '0;
            z0_q <= '0; z1_q <= '0; z2_q <= '0;
            clear_depth_q <= 16'hffff;
            depth_enable_q <= 1'b0;
            depth_write_enable_q <= 1'b0;
            depth_lequal_q <= 1'b0;
            area_q <= '0;
            area_abs_q <= '0;
            area_neg_q <= 1'b0;
            min_x_q <= '0; max_x_q <= '0; min_y_q <= '0; max_y_q <= '0;
            cur_x_q <= '0; cur_y_q <= '0;
            pixel_depth_q <= '0;
            old_depth_q <= '0;
            depth_addr_row_q <= '0;
            depth_addr_cur_q <= '0;
            color_addr_row_q <= '0;
            color_addr_cur_q <= '0;
            w0_row_q <= '0; w1_row_q <= '0; w2_row_q <= '0;
            w0_cur_q <= '0; w1_cur_q <= '0; w2_cur_q <= '0;
            w0_dx_q <= '0; w1_dx_q <= '0; w2_dx_q <= '0;
            w0_dy_q <= '0; w1_dy_q <= '0; w2_dy_q <= '0;
            depth_row_q <= '0;
            depth_cur_q <= '0;
            depth_rem_row_q <= '0;
            depth_rem_cur_q <= '0;
            depth_step_x_q <= '0;
            depth_step_y_q <= '0;
            depth_rem_x_q <= '0;
            depth_rem_y_q <= '0;
            numer_row_setup_q <= '0;
            numer_dx_setup_q <= '0;
            numer_dy_setup_q <= '0;
            axi_error_pulse <= 1'b0;
        end else if (clr) begin
            state_q <= S_IDLE;
            cur_x_q <= '0;
            cur_y_q <= '0;
            pixel_depth_q <= '0;
            old_depth_q <= '0;
            depth_addr_row_q <= '0;
            depth_addr_cur_q <= '0;
            color_addr_row_q <= '0;
            color_addr_cur_q <= '0;
            w0_row_q <= '0; w1_row_q <= '0; w2_row_q <= '0;
            w0_cur_q <= '0; w1_cur_q <= '0; w2_cur_q <= '0;
            depth_row_q <= '0;
            depth_cur_q <= '0;
            depth_rem_row_q <= '0;
            depth_rem_cur_q <= '0;
            axi_error_pulse <= 1'b0;
        end else begin
            axi_error_pulse <= 1'b0;
            case (state_q)
                S_IDLE: begin
                    if (cmd_valid) begin
                        x0_v = $signed({{7{cmd_data[`GRU_DEPTH_CMD_X0_MSB]}}, cmd_data[`GRU_DEPTH_CMD_X0_MSB:`GRU_DEPTH_CMD_X0_LSB]});
                        y0_v = $signed({{8{cmd_data[`GRU_DEPTH_CMD_Y0_MSB]}}, cmd_data[`GRU_DEPTH_CMD_Y0_MSB:`GRU_DEPTH_CMD_Y0_LSB]});
                        x1_v = $signed({{7{cmd_data[`GRU_DEPTH_CMD_X1_MSB]}}, cmd_data[`GRU_DEPTH_CMD_X1_MSB:`GRU_DEPTH_CMD_X1_LSB]});
                        y1_v = $signed({{8{cmd_data[`GRU_DEPTH_CMD_Y1_MSB]}}, cmd_data[`GRU_DEPTH_CMD_Y1_MSB:`GRU_DEPTH_CMD_Y1_LSB]});
                        x2_v = $signed({{7{cmd_data[`GRU_DEPTH_CMD_X2_MSB]}}, cmd_data[`GRU_DEPTH_CMD_X2_MSB:`GRU_DEPTH_CMD_X2_LSB]});
                        y2_v = $signed({{8{cmd_data[`GRU_DEPTH_CMD_Y2_MSB]}}, cmd_data[`GRU_DEPTH_CMD_Y2_MSB:`GRU_DEPTH_CMD_Y2_LSB]});
                        seq_q <= cmd_data[`GRU_DEPTH_CMD_SEQ_MSB:`GRU_DEPTH_CMD_SEQ_LSB];
                        opcode_q <= cmd_data[`GRU_DEPTH_CMD_OPCODE_MSB:`GRU_DEPTH_CMD_OPCODE_LSB];
                        color_idx_q <= cmd_data[`GRU_DEPTH_CMD_COLOR_MSB:`GRU_DEPTH_CMD_COLOR_LSB];
                        x0_q <= x0_v;
                        y0_q <= y0_v;
                        x1_q <= x1_v;
                        y1_q <= y1_v;
                        x2_q <= x2_v;
                        y2_q <= y2_v;
                        z0_q <= cmd_data[`GRU_DEPTH_CMD_Z0_MSB:`GRU_DEPTH_CMD_Z0_LSB];
                        z1_q <= cmd_data[`GRU_DEPTH_CMD_Z1_MSB:`GRU_DEPTH_CMD_Z1_LSB];
                        z2_q <= cmd_data[`GRU_DEPTH_CMD_Z2_MSB:`GRU_DEPTH_CMD_Z2_LSB];
                        clear_depth_q <= cmd_data[`GRU_DEPTH_CMD_Z2_MSB:`GRU_DEPTH_CMD_Z2_LSB];
                        depth_enable_q <= cmd_data[`GRU_DEPTH_CMD_DEPTH_EN_BIT];
                        depth_write_enable_q <= cmd_data[`GRU_DEPTH_CMD_DEPTH_WR_BIT];
                        depth_lequal_q <= cmd_data[`GRU_DEPTH_CMD_DEPTH_LEQUAL_BIT];

                        area_now = ((x2_v - x0_v) * (y1_v - y0_v)) - ((y2_v - y0_v) * (x1_v - x0_v));
                        area_q <= area_now;

                        min_x = x0_v;
                        if (x1_v < min_x) min_x = x1_v;
                        if (x2_v < min_x) min_x = x2_v;
                        max_x = x0_v;
                        if (x1_v > max_x) max_x = x1_v;
                        if (x2_v > max_x) max_x = x2_v;
                        min_y = y0_v;
                        if (y1_v < min_y) min_y = y1_v;
                        if (y2_v < min_y) min_y = y2_v;
                        max_y = y0_v;
                        if (y1_v > max_y) max_y = y1_v;
                        if (y2_v > max_y) max_y = y2_v;
                        if (min_x < 0) min_x = 0;
                        if (min_y < 0) min_y = 0;
                        if (max_x > ($signed({1'b0, frame_w}) - 16'sd1)) max_x = $signed({1'b0, frame_w}) - 16'sd1;
                        if (max_y > ($signed({1'b0, frame_h}) - 16'sd1)) max_y = $signed({1'b0, frame_h}) - 16'sd1;
                        min_x_q <= min_x;
                        max_x_q <= max_x;
                        min_y_q <= min_y;
                        max_y_q <= max_y;

                        if (cmd_data[`GRU_DEPTH_CMD_OPCODE_MSB:`GRU_DEPTH_CMD_OPCODE_LSB] == `GRU_OP_CLEAR_DEPTH) begin
                            cur_x_q <= 16'sd0;
                            cur_y_q <= 16'sd0;
                            depth_addr_row_q <= depth_base;
                            depth_addr_cur_q <= depth_base;
                            color_addr_row_q <= fb_base;
                            color_addr_cur_q <= fb_base;
                            state_q <= (frame_w == 16'd0 || frame_h == 16'd0 || depth_base == 32'd0) ? S_DONE : S_CLEAR_ISSUE;
                        end else begin
                            cur_x_q <= min_x;
                            cur_y_q <= min_y;
                            depth_addr_row_q <= depth_base + (min_y * stride) + (min_x <<< 1);
                            depth_addr_cur_q <= depth_base + (min_y * stride) + (min_x <<< 1);
                            color_addr_row_q <= fb_base + (min_y * stride) + (min_x <<< 1);
                            color_addr_cur_q <= fb_base + (min_y * stride) + (min_x <<< 1);
                            if ((depth_base == 32'd0) || (area_now == 0) || (min_x > max_x) || (min_y > max_y)) begin
                                state_q <= S_DONE;
                            end else begin
                                state_q <= S_TRI_SETUP_EDGE;
                            end
                        end
                    end
                end
                S_CLEAR_ISSUE: begin
                    if (m_axi_awready && m_axi_wready) begin
                        state_q <= S_CLEAR_WAIT_B;
                    end
                end
                S_CLEAR_WAIT_B: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) axi_error_pulse <= 1'b1;
                        if ((cur_y_q == $signed({1'b0, frame_h}) - 16'sd1) &&
                            (cur_x_q == $signed({1'b0, frame_w}) - 16'sd1)) begin
                            state_q <= S_DONE;
                        end else begin
                            advance_clear_pixel();
                            state_q <= S_CLEAR_ISSUE;
                        end
                    end
                end
                S_TRI_SETUP_EDGE: begin
                    area_neg_q <= area_q[31];
                    area_abs_q <= area_q[31] ? -area_q : area_q;

                    w0_now = edge_value(min_x_q, min_y_q, x1_q, y1_q, x2_q, y2_q);
                    w1_now = edge_value(min_x_q, min_y_q, x2_q, y2_q, x0_q, y0_q);
                    w2_now = edge_value(min_x_q, min_y_q, x0_q, y0_q, x1_q, y1_q);
                    w0_dx_now = y2_q - y1_q;
                    w1_dx_now = y0_q - y2_q;
                    w2_dx_now = y1_q - y0_q;
                    w0_dy_now = x1_q - x2_q;
                    w1_dy_now = x2_q - x0_q;
                    w2_dy_now = x0_q - x1_q;

                    w0_row_q <= w0_now;
                    w1_row_q <= w1_now;
                    w2_row_q <= w2_now;
                    w0_cur_q <= w0_now;
                    w1_cur_q <= w1_now;
                    w2_cur_q <= w2_now;
                    w0_dx_q <= w0_dx_now;
                    w1_dx_q <= w1_dx_now;
                    w2_dx_q <= w2_dx_now;
                    w0_dy_q <= w0_dy_now;
                    w1_dy_q <= w1_dy_now;
                    w2_dy_q <= w2_dy_now;
                    state_q <= S_TRI_SETUP_NUMER;
                end
                S_TRI_SETUP_NUMER: begin
                    numer_row_setup_q <= normalize_numer(depth_numer_from_weights(w0_row_q, w1_row_q, w2_row_q, z0_q, z1_q, z2_q), area_neg_q);
                    numer_dx_setup_q <= normalize_numer(depth_numer_from_weights(w0_dx_q, w1_dx_q, w2_dx_q, z0_q, z1_q, z2_q), area_neg_q);
                    numer_dy_setup_q <= normalize_numer(depth_numer_from_weights(w0_dy_q, w1_dy_q, w2_dy_q, z0_q, z1_q, z2_q), area_neg_q);
                    state_q <= S_TRI_SETUP_DEPTH;
                end
                S_TRI_SETUP_DEPTH: begin
                    if (area_abs_q == 32'd0) begin
                        depth_row_q <= 32'd0;
                        depth_cur_q <= 32'd0;
                        depth_rem_row_q <= 32'd0;
                        depth_rem_cur_q <= 32'd0;
                    end else begin
                        area_abs_signed = $signed({1'b0, area_abs_q});
                        div_q = numer_row_setup_q / area_abs_signed;
                        div_r = numer_row_setup_q - (div_q * area_abs_signed);
                        depth_row_q <= div_q[31:0];
                        depth_cur_q <= div_q[31:0];
                        depth_rem_row_q <= div_r[31:0];
                        depth_rem_cur_q <= div_r[31:0];
                    end
                    state_q <= S_TRI_SETUP_DX;
                end
                S_TRI_SETUP_DX: begin
                    if (area_abs_q == 32'd0) begin
                        depth_step_x_q <= 32'sd0;
                        depth_rem_x_q <= 32'd0;
                    end else begin
                        area_abs_signed = $signed({1'b0, area_abs_q});
                        div_q = numer_dx_setup_q / area_abs_signed;
                        div_r = numer_dx_setup_q - (div_q * area_abs_signed);
                        if (div_r < 0) begin
                            step_now = div_q[31:0] - 32'sd1;
                            rem_now = div_r[31:0] + area_abs_q;
                        end else begin
                            step_now = div_q[31:0];
                            rem_now = div_r[31:0];
                        end
                        depth_step_x_q <= step_now;
                        depth_rem_x_q <= rem_now;
                    end
                    state_q <= S_TRI_SETUP_DY;
                end
                S_TRI_SETUP_DY: begin
                    if (area_abs_q == 32'd0) begin
                        depth_step_y_q <= 32'sd0;
                        depth_rem_y_q <= 32'd0;
                    end else begin
                        area_abs_signed = $signed({1'b0, area_abs_q});
                        div_q = numer_dy_setup_q / area_abs_signed;
                        div_r = numer_dy_setup_q - (div_q * area_abs_signed);
                        if (div_r < 0) begin
                            step_now = div_q[31:0] - 32'sd1;
                            rem_now = div_r[31:0] + area_abs_q;
                        end else begin
                            step_now = div_q[31:0];
                            rem_now = div_r[31:0];
                        end
                        depth_step_y_q <= step_now;
                        depth_rem_y_q <= rem_now;
                    end
                    state_q <= S_TRI_SCAN;
                end
                S_TRI_SCAN: begin
                    if (cur_y_q > max_y_q) begin
                        state_q <= S_DONE;
                    end else if (!pixel_inside_now) begin
                        if ((cur_y_q == max_y_q) && (cur_x_q == max_x_q)) begin
                            state_q <= S_DONE;
                        end else begin
                            advance_triangle_pixel();
                        end
                    end else begin
                        pixel_depth_q <= depth_cur_q[15:0];
                        if (depth_enable_q) begin
                            state_q <= S_TRI_REQ_RD;
                        end else if (depth_write_enable_q) begin
                            state_q <= S_TRI_DEPTH_WRITE;
                        end else begin
                            state_q <= S_TRI_COLOR_WRITE;
                        end
                    end
                end
                S_TRI_REQ_RD: begin
                    if (m_axi_arready) begin
                        state_q <= S_TRI_WAIT_RD;
                    end
                end
                S_TRI_WAIT_RD: begin
                    if (m_axi_rvalid) begin
                        old_depth_q <= m_axi_rdata[(depth_addr_cur_q[3:0] * 8) +: 16];
                        if (m_axi_rresp != 2'b00) axi_error_pulse <= 1'b1;
                        state_q <= S_TRI_COMPARE;
                    end
                end
                S_TRI_COMPARE: begin
                    if (depth_compare_pass) begin
                        if (depth_write_enable_q) begin
                            state_q <= S_TRI_DEPTH_WRITE;
                        end else begin
                            state_q <= S_TRI_COLOR_WRITE;
                        end
                    end else if ((cur_y_q == max_y_q) && (cur_x_q == max_x_q)) begin
                        state_q <= S_DONE;
                    end else begin
                        advance_triangle_pixel();
                        state_q <= S_TRI_SCAN;
                    end
                end
                S_TRI_DEPTH_WRITE: begin
                    if (m_axi_awready && m_axi_wready) begin
                        state_q <= S_TRI_DEPTH_WAIT_B;
                    end
                end
                S_TRI_DEPTH_WAIT_B: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) axi_error_pulse <= 1'b1;
                        state_q <= S_TRI_COLOR_WRITE;
                    end
                end
                S_TRI_COLOR_WRITE: begin
                    if (m_axi_awready && m_axi_wready) begin
                        state_q <= S_TRI_COLOR_WAIT_B;
                    end
                end
                S_TRI_COLOR_WAIT_B: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) axi_error_pulse <= 1'b1;
                        if ((cur_y_q == max_y_q) && (cur_x_q == max_x_q)) begin
                            state_q <= S_DONE;
                        end else begin
                            advance_triangle_pixel();
                            state_q <= S_TRI_SCAN;
                        end
                    end
                end
                S_DONE: begin
                    state_q <= S_IDLE;
                end
                default: begin
                    state_q <= S_IDLE;
                end
            endcase
        end
    end
endmodule
