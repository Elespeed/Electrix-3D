`include "gru_defs.vh"

module gru_cmd_fetch (
    input  logic        clk,
    input  logic        rstn,
    input  logic        clr,

    input  logic        start_pulse,
    input  logic [31:0] start_addr,
    input  logic [15:0] start_word_count,

    output logic        busy,
    output logic        done_pulse,
    output logic        cfg_error_pulse,
    output logic        axi_error_pulse,

    output logic        word_valid,
    input  logic        word_ready,
    output logic [31:0] word_data,

    output logic [4:0]  m_axi_arid,
    output logic [31:0] m_axi_araddr,
    output logic [7:0]  m_axi_arlen,
    output logic [2:0]  m_axi_arsize,
    output logic [1:0]  m_axi_arburst,
    output logic        m_axi_arlock,
    output logic [3:0]  m_axi_arcache,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [4:0]  m_axi_rid,
    input  logic [127:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rlast,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);
    logic [31:0] cur_addr_q;
    logic [15:0] words_remaining_q;
    logic [127:0] beat_data_q;
    logic [2:0] buf_words_left_q;
    logic [1:0] buf_word_idx_q;
    logic       have_beat_q;
    logic       wait_r_q;

    function automatic [2:0] min_words_in_beat(
        input logic [1:0] start_word_idx,
        input logic [15:0] remaining_words
    );
        logic [2:0] words_to_boundary;
        begin
            words_to_boundary = 3'd4 - {1'b0, start_word_idx};
            if (remaining_words[15:0] < {13'd0, words_to_boundary}) begin
                min_words_in_beat = remaining_words[2:0];
            end else begin
                min_words_in_beat = words_to_boundary;
            end
        end
    endfunction

    always_comb begin
        case (buf_word_idx_q)
            2'd0: word_data = beat_data_q[31:0];
            2'd1: word_data = beat_data_q[63:32];
            2'd2: word_data = beat_data_q[95:64];
            default: word_data = beat_data_q[127:96];
        endcase
    end

    assign word_valid = busy & have_beat_q & (buf_words_left_q != 3'd0);

    assign m_axi_arid = 5'd0;
    assign m_axi_araddr = {cur_addr_q[31:4], 4'b0000};
    assign m_axi_arlen = 8'd0;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'd0;
    assign m_axi_arprot = 3'd0;
    assign m_axi_arvalid = busy & ~have_beat_q & ~wait_r_q;
    assign m_axi_rready = busy & wait_r_q;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            busy <= 1'b0;
            done_pulse <= 1'b0;
            cfg_error_pulse <= 1'b0;
            axi_error_pulse <= 1'b0;
            cur_addr_q <= 32'd0;
            words_remaining_q <= 16'd0;
            beat_data_q <= 128'd0;
            buf_words_left_q <= 3'd0;
            buf_word_idx_q <= 2'd0;
            have_beat_q <= 1'b0;
            wait_r_q <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            cfg_error_pulse <= 1'b0;
            axi_error_pulse <= 1'b0;

            if (clr) begin
                busy <= 1'b0;
                cur_addr_q <= 32'd0;
                words_remaining_q <= 16'd0;
                beat_data_q <= 128'd0;
                buf_words_left_q <= 3'd0;
                buf_word_idx_q <= 2'd0;
                have_beat_q <= 1'b0;
                wait_r_q <= 1'b0;
            end else begin
                if (start_pulse) begin
                    if (busy || start_addr[1:0] != 2'b00 || start_word_count == 16'd0) begin
                        cfg_error_pulse <= 1'b1;
                    end else begin
                        busy <= 1'b1;
                        cur_addr_q <= start_addr;
                        words_remaining_q <= start_word_count;
                        beat_data_q <= 128'd0;
                        buf_words_left_q <= 3'd0;
                        buf_word_idx_q <= 2'd0;
                        have_beat_q <= 1'b0;
                        wait_r_q <= 1'b0;
                    end
                end

                if (busy && m_axi_arvalid && m_axi_arready) begin
                    wait_r_q <= 1'b1;
                end

                if (busy && wait_r_q && m_axi_rvalid && m_axi_rready) begin
                    wait_r_q <= 1'b0;
                    if ((m_axi_rresp != 2'b00) || ~m_axi_rlast) begin
                        busy <= 1'b0;
                        have_beat_q <= 1'b0;
                        buf_words_left_q <= 3'd0;
                        axi_error_pulse <= 1'b1;
                    end else begin
                        beat_data_q <= m_axi_rdata;
                        buf_word_idx_q <= cur_addr_q[3:2];
                        buf_words_left_q <= min_words_in_beat(cur_addr_q[3:2], words_remaining_q);
                        have_beat_q <= 1'b1;
                    end
                end

                if (word_valid && word_ready) begin
                    cur_addr_q <= cur_addr_q + 32'd4;
                    words_remaining_q <= words_remaining_q - 16'd1;
                    buf_word_idx_q <= buf_word_idx_q + 2'd1;
                    buf_words_left_q <= buf_words_left_q - 3'd1;

                    if (words_remaining_q == 16'd1) begin
                        busy <= 1'b0;
                        have_beat_q <= 1'b0;
                        buf_words_left_q <= 3'd0;
                        done_pulse <= 1'b1;
                    end else if (buf_words_left_q == 3'd1) begin
                        have_beat_q <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
