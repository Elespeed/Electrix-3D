`include "gru_defs.vh"

module gru_cmd_buffer_ctrl (
    input  logic        clk,
    input  logic        rstn,
    input  logic        clr,

    input  logic        exec_start_pulse,
    input  logic [31:0] exec_base_addr,
    input  logic [15:0] exec_word_count,

    output logic        fetch_start_pulse,
    output logic [31:0] fetch_base_addr,
    output logic [15:0] fetch_word_count,
    input  logic        fetch_busy,
    input  logic        fetch_done_pulse,
    input  logic        fetch_cfg_error_pulse,
    input  logic        fetch_axi_error_pulse,
    input  logic        fetch_word_valid,
    output logic        fetch_word_ready,
    input  logic [31:0] fetch_word_data,

    input  logic        cmd_fifo_full,
    input  logic        ext_cmd_fifo_full,
    output logic        cmd_push_valid,
    output logic [63:0] cmd_push_data,
    output logic        ext_cmd_push_valid,
    output logic [31:0] ext_cmd_w0,
    output logic [31:0] ext_cmd_w1,
    output logic [31:0] ext_cmd_w2,
    output logic [31:0] ext_cmd_w3,
    output logic [31:0] ext_cmd_w4,
    output logic        present_pulse,

    output logic        cb_busy,
    output logic        cb_done_pulse,
    output logic        cb_cfg_error_pulse,
    output logic        cb_axi_error_pulse
);
    typedef enum logic [1:0] {
        ST_IDLE      = 2'd0,
        ST_HEADER    = 2'd1,
        ST_PAYLOAD   = 2'd2,
        ST_WAIT_PUSH = 2'd3
    } state_t;

    state_t state_q;
    logic [15:0] words_left_q;
    logic [2:0] payload_expected_q;
    logic [2:0] payload_count_q;
    logic [7:0] opcode_q;
    logic [31:0] payload_q [0:6];
    logic error_drain_q;

    function automatic logic is_simple_legacy_opcode(input logic [`GRU_OPCODE_W-1:0] opcode);
        begin
            case (opcode)
                `GRU_OP_CLEAR,
                `GRU_OP_FILL_RECT,
                `GRU_OP_DRAW_LINE,
                `GRU_OP_DRAW_GLYPH,
                `GRU_OP_CLEAR_DEPTH: is_simple_legacy_opcode = 1'b1;
                default: is_simple_legacy_opcode = 1'b0;
            endcase
        end
    endfunction

    function automatic logic is_ext_legacy_opcode(input logic [`GRU_OPCODE_W-1:0] opcode);
        begin
            case (opcode)
                `GRU_OP_BLIT,
                `GRU_OP_TRIANGLE_FLAT,
                `GRU_OP_TRIANGLE_Z,
                `GRU_OP_TRIANGLE_GOURAUD: is_ext_legacy_opcode = 1'b1;
                default: is_ext_legacy_opcode = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [2:0] expected_payload_words(input logic [7:0] opcode);
        begin
            case (opcode)
                `GRU_CB_OP_RAW_CMD: expected_payload_words = 3'd2;
                `GRU_CB_OP_RAW_EXT_CMD: expected_payload_words = 3'd7;
                `GRU_CB_OP_FENCE: expected_payload_words = 3'd0;
                `GRU_CB_OP_PRESENT: expected_payload_words = 3'd0;
                default: expected_payload_words = 3'd0;
            endcase
        end
    endfunction

    function automatic logic opcode_supported(input logic [7:0] opcode);
        begin
            case (opcode)
                `GRU_CB_OP_RAW_CMD,
                `GRU_CB_OP_RAW_EXT_CMD,
                `GRU_CB_OP_FENCE,
                `GRU_CB_OP_PRESENT: opcode_supported = 1'b1;
                default: opcode_supported = 1'b0;
            endcase
        end
    endfunction

    assign fetch_base_addr = exec_base_addr;
    assign fetch_word_count = exec_word_count;
    assign cb_busy = (state_q != ST_IDLE) | fetch_busy;

    always_comb begin
        fetch_word_ready = 1'b0;
        if (state_q == ST_HEADER) begin
            fetch_word_ready = 1'b1;
        end else if (state_q == ST_PAYLOAD) begin
            fetch_word_ready = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        integer idx;
        logic [15:0] header_words;
        logic [2:0] expected_words;
        logic can_push;
        logic payload_valid;

        if (!rstn) begin
            state_q <= ST_IDLE;
            words_left_q <= 16'd0;
            payload_expected_q <= 3'd0;
            payload_count_q <= 3'd0;
            opcode_q <= 8'd0;
            error_drain_q <= 1'b0;
            fetch_start_pulse <= 1'b0;
            cmd_push_valid <= 1'b0;
            cmd_push_data <= 64'd0;
            ext_cmd_push_valid <= 1'b0;
            ext_cmd_w0 <= 32'd0;
            ext_cmd_w1 <= 32'd0;
            ext_cmd_w2 <= 32'd0;
            ext_cmd_w3 <= 32'd0;
            ext_cmd_w4 <= 32'd0;
            present_pulse <= 1'b0;
            cb_done_pulse <= 1'b0;
            cb_cfg_error_pulse <= 1'b0;
            cb_axi_error_pulse <= 1'b0;
            for (idx = 0; idx < 7; idx = idx + 1) begin
                payload_q[idx] <= 32'd0;
            end
        end else begin
            fetch_start_pulse <= 1'b0;
            cmd_push_valid <= 1'b0;
            cmd_push_data <= 64'd0;
            ext_cmd_push_valid <= 1'b0;
            present_pulse <= 1'b0;
            cb_done_pulse <= 1'b0;
            cb_cfg_error_pulse <= 1'b0;
            cb_axi_error_pulse <= 1'b0;

            if (clr) begin
                state_q <= ST_IDLE;
                words_left_q <= 16'd0;
                payload_expected_q <= 3'd0;
                payload_count_q <= 3'd0;
                opcode_q <= 8'd0;
                error_drain_q <= 1'b0;
                ext_cmd_w0 <= 32'd0;
                ext_cmd_w1 <= 32'd0;
                ext_cmd_w2 <= 32'd0;
                ext_cmd_w3 <= 32'd0;
                ext_cmd_w4 <= 32'd0;
            end else begin
                if (fetch_axi_error_pulse) begin
                    cb_axi_error_pulse <= 1'b1;
                    state_q <= ST_IDLE;
                    words_left_q <= 16'd0;
                    payload_expected_q <= 3'd0;
                    payload_count_q <= 3'd0;
                    error_drain_q <= 1'b0;
                end else if (fetch_cfg_error_pulse) begin
                    cb_cfg_error_pulse <= 1'b1;
                    state_q <= ST_IDLE;
                    words_left_q <= 16'd0;
                    payload_expected_q <= 3'd0;
                    payload_count_q <= 3'd0;
                    error_drain_q <= 1'b0;
                end else begin
                    if (exec_start_pulse) begin
                        if (cb_busy || exec_word_count == 16'd0) begin
                            cb_cfg_error_pulse <= 1'b1;
                        end else begin
                            fetch_start_pulse <= 1'b1;
                            state_q <= ST_HEADER;
                            words_left_q <= exec_word_count;
                            payload_expected_q <= 3'd0;
                            payload_count_q <= 3'd0;
                            opcode_q <= 8'd0;
                            error_drain_q <= 1'b0;
                        end
                    end

                    if (fetch_done_pulse && (state_q == ST_HEADER) && (words_left_q == 16'd0) && ~error_drain_q) begin
                        cb_done_pulse <= 1'b1;
                        state_q <= ST_IDLE;
                    end

                    case (state_q)
                        ST_IDLE: begin
                        end
                        ST_HEADER: begin
                            if (fetch_word_valid && fetch_word_ready) begin
                                header_words = fetch_word_data[15:0];
                                expected_words = expected_payload_words(fetch_word_data[31:24]);
                                opcode_q <= fetch_word_data[31:24];
                                if ((words_left_q == 16'd0) ||
                                    (header_words == 16'd0) ||
                                    ~opcode_supported(fetch_word_data[31:24]) ||
                                    (header_words != ({13'd0, expected_words} + 16'd1)) ||
                                    (header_words > words_left_q)) begin
                                    cb_cfg_error_pulse <= 1'b1;
                                    error_drain_q <= 1'b1;
                                    words_left_q <= words_left_q - 16'd1;
                                    if (words_left_q == 16'd1) begin
                                        state_q <= ST_IDLE;
                                    end else begin
                                        state_q <= ST_PAYLOAD;
                                        payload_expected_q <= 3'd0;
                                        payload_count_q <= 3'd0;
                                    end
                                end else begin
                                    words_left_q <= words_left_q - 16'd1;
                                    payload_expected_q <= expected_words;
                                    payload_count_q <= 3'd0;
                                    error_drain_q <= 1'b0;
                                    if (expected_words == 3'd0) begin
                                        state_q <= ST_WAIT_PUSH;
                                    end else begin
                                        state_q <= ST_PAYLOAD;
                                    end
                                end
                            end
                        end
                        ST_PAYLOAD: begin
                            if (fetch_word_valid && fetch_word_ready) begin
                                if (error_drain_q) begin
                                    words_left_q <= words_left_q - 16'd1;
                                    if (words_left_q == 16'd1) begin
                                        state_q <= ST_IDLE;
                                        error_drain_q <= 1'b0;
                                    end
                                end else begin
                                    payload_q[payload_count_q] <= fetch_word_data;
                                    payload_count_q <= payload_count_q + 3'd1;
                                    words_left_q <= words_left_q - 16'd1;
                                    if (payload_count_q + 3'd1 == payload_expected_q) begin
                                        state_q <= ST_WAIT_PUSH;
                                    end
                                end
                            end
                        end
                        ST_WAIT_PUSH: begin
                            if (error_drain_q) begin
                                if (words_left_q == 16'd0) begin
                                    state_q <= ST_IDLE;
                                    error_drain_q <= 1'b0;
                                end else begin
                                    state_q <= ST_HEADER;
                                end
                            end else begin
                                can_push = 1'b0;
                                payload_valid = 1'b1;
                                if (opcode_q == `GRU_CB_OP_RAW_CMD) begin
                                    can_push = ~cmd_fifo_full;
                                    payload_valid = is_simple_legacy_opcode(payload_q[0][`GRU_CMD0_OPCODE_MSB:`GRU_CMD0_OPCODE_LSB]);
                                end else if (opcode_q == `GRU_CB_OP_RAW_EXT_CMD) begin
                                    can_push = ~cmd_fifo_full & ~ext_cmd_fifo_full;
                                    payload_valid = is_ext_legacy_opcode(payload_q[0][`GRU_CMD0_OPCODE_MSB:`GRU_CMD0_OPCODE_LSB]);
                                end else begin
                                    can_push = 1'b1;
                                end

                                if (~payload_valid) begin
                                    cb_cfg_error_pulse <= 1'b1;
                                    state_q <= ST_IDLE;
                                end else if (can_push) begin
                                    case (opcode_q)
                                        `GRU_CB_OP_RAW_CMD: begin
                                            cmd_push_valid <= 1'b1;
                                            cmd_push_data <= {payload_q[1], payload_q[0]};
                                        end
                                        `GRU_CB_OP_RAW_EXT_CMD: begin
                                            cmd_push_valid <= 1'b1;
                                            cmd_push_data <= {payload_q[1], payload_q[0]};
                                            ext_cmd_push_valid <= 1'b1;
                                            ext_cmd_w0 <= payload_q[2];
                                            ext_cmd_w1 <= payload_q[3];
                                            ext_cmd_w2 <= payload_q[4];
                                            ext_cmd_w3 <= payload_q[5];
                                            ext_cmd_w4 <= payload_q[6];
                                        end
                                        `GRU_CB_OP_FENCE: begin
                                            cmd_push_valid <= 1'b1;
                                            cmd_push_data <= {32'd0, {27'd0, `GRU_OP_FENCE}};
                                        end
                                        `GRU_CB_OP_PRESENT: begin
                                            present_pulse <= 1'b1;
                                        end
                                        default: begin
                                            cb_cfg_error_pulse <= 1'b1;
                                        end
                                    endcase

                                    if (words_left_q == 16'd0 && ~fetch_busy) begin
                                        cb_done_pulse <= 1'b1;
                                        state_q <= ST_IDLE;
                                    end else begin
                                        state_q <= ST_HEADER;
                                    end
                                end
                            end
                        end
                        default: begin
                            state_q <= ST_IDLE;
                        end
                    endcase
                end
            end
        end
    end
endmodule
