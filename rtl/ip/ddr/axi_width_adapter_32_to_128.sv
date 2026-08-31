module axi_width_adapter_32_to_128 (
    input  logic        aclk,
    input  logic        aresetn,

    input  logic [4:0]  s_axi_arid,
    input  logic [31:0] s_axi_araddr,
    input  logic [7:0]  s_axi_arlen,
    input  logic [2:0]  s_axi_arsize,
    input  logic [1:0]  s_axi_arburst,
    input  logic        s_axi_arlock,
    input  logic [3:0]  s_axi_arcache,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [4:0]  s_axi_rid,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rlast,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    input  logic [4:0]  s_axi_awid,
    input  logic [31:0] s_axi_awaddr,
    input  logic [7:0]  s_axi_awlen,
    input  logic [2:0]  s_axi_awsize,
    input  logic [1:0]  s_axi_awburst,
    input  logic        s_axi_awlock,
    input  logic [3:0]  s_axi_awcache,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wlast,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [4:0]  s_axi_bid,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    output logic [4:0]   m_axi_arid,
    output logic [31:0]  m_axi_araddr,
    output logic [7:0]   m_axi_arlen,
    output logic [2:0]   m_axi_arsize,
    output logic [1:0]   m_axi_arburst,
    output logic         m_axi_arlock,
    output logic [3:0]   m_axi_arcache,
    output logic [2:0]   m_axi_arprot,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,
    input  logic [4:0]   m_axi_rid,
    input  logic [127:0] m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rlast,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,

    output logic [4:0]   m_axi_awid,
    output logic [31:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic [2:0]   m_axi_awsize,
    output logic [1:0]   m_axi_awburst,
    output logic         m_axi_awlock,
    output logic [3:0]   m_axi_awcache,
    output logic [2:0]   m_axi_awprot,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,
    output logic [127:0] m_axi_wdata,
    output logic [15:0]  m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,
    input  logic [4:0]   m_axi_bid,
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready
);

    typedef enum logic [1:0] {
        READ_IDLE      = 2'd0,
        READ_REFILL_AR = 2'd1,
        READ_REFILL_R  = 2'd2,
        READ_RESP      = 2'd3
    } read_state_t;

    typedef enum logic [2:0] {
        WRITE_IDLE     = 3'd0,
        WRITE_ACCEPT_W = 3'd1,
        WRITE_SEND_REQ = 3'd2,
        WRITE_WAIT_B   = 3'd3,
        WRITE_RESP     = 3'd4
    } write_state_t;

    read_state_t  read_state;
    write_state_t write_state;

    logic [4:0]  read_id_q;
    logic [31:0] read_addr_q;
    logic [8:0]  read_words_left_q;
    logic        read_lock_q;
    logic [3:0]  read_cache_q;
    logic [2:0]  read_prot_q;
    logic [127:0] read_cache_line_q;
    logic [31:4]  read_cache_line_addr_q;
    logic [1:0]   read_cache_resp_q;
    logic         read_cache_valid_q;

    logic [4:0]  write_id_q;
    logic [31:0] write_addr_q;
    logic [8:0]  write_words_left_q;
    logic [1:0]  write_burst_q;
    logic        write_lock_q;
    logic [3:0]  write_cache_q;
    logic [2:0]  write_prot_q;
    logic [127:0] write_chunk_data_q;
    logic [15:0]  write_chunk_strb_q;
    logic [2:0]   write_chunk_words_q;
    logic [2:0]   write_chunk_limit_q;
    logic [1:0]  write_resp_accum_q;
    logic        write_aw_sent_q;
    logic        write_w_sent_q;

    function automatic [31:0] select_word32(
        input logic [127:0] line_data,
        input logic [1:0]   word_sel
    );
        begin
            case (word_sel)
                2'd0:    select_word32 = line_data[31:0];
                2'd1:    select_word32 = line_data[63:32];
                2'd2:    select_word32 = line_data[95:64];
                default: select_word32 = line_data[127:96];
            endcase
        end
    endfunction

    function automatic [127:0] expand_word128(
        input logic [31:0] word_data,
        input logic [1:0]  word_sel
    );
        begin
            expand_word128 = 128'd0;
            case (word_sel)
                2'd0:    expand_word128[31:0]    = word_data;
                2'd1:    expand_word128[63:32]   = word_data;
                2'd2:    expand_word128[95:64]   = word_data;
                default: expand_word128[127:96]  = word_data;
            endcase
        end
    endfunction

    function automatic [15:0] expand_strb128(
        input logic [3:0] word_strb,
        input logic [1:0] word_sel
    );
        begin
            expand_strb128 = 16'd0;
            case (word_sel)
                2'd0:    expand_strb128[3:0]    = word_strb;
                2'd1:    expand_strb128[7:4]    = word_strb;
                2'd2:    expand_strb128[11:8]   = word_strb;
                default: expand_strb128[15:12]  = word_strb;
            endcase
        end
    endfunction

    wire read_cache_hit = read_cache_valid_q &&
                          (read_cache_line_addr_q == read_addr_q[31:4]);
    wire [31:0] read_word_data = select_word32(read_cache_line_q, read_addr_q[3:2]);
    wire read_last_word = (read_words_left_q == 9'd1);
    wire write_last_chunk = (write_words_left_q == {6'd0, write_chunk_words_q});

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            read_state            <= READ_IDLE;
            read_id_q             <= 5'd0;
            read_addr_q           <= 32'd0;
            read_words_left_q     <= 9'd0;
            read_lock_q           <= 1'b0;
            read_cache_q          <= 4'd0;
            read_prot_q           <= 3'd0;
            read_cache_line_q     <= 128'd0;
            read_cache_line_addr_q <= 28'd0;
            read_cache_resp_q     <= 2'd0;
            read_cache_valid_q    <= 1'b0;
        end else begin
            case (read_state)
                READ_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        read_id_q          <= s_axi_arid;
                        read_addr_q        <= s_axi_araddr;
                        read_words_left_q  <= {1'b0, s_axi_arlen} + 9'd1;
                        read_lock_q        <= s_axi_arlock;
                        read_cache_q       <= s_axi_arcache;
                        read_prot_q        <= s_axi_arprot;
                        read_state         <= read_cache_valid_q &&
                                              (read_cache_line_addr_q == s_axi_araddr[31:4]) ?
                                              READ_RESP : READ_REFILL_AR;
                    end
                end
                READ_REFILL_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        read_state <= READ_REFILL_R;
                    end
                end
                READ_REFILL_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        read_cache_line_q      <= m_axi_rdata;
                        read_cache_line_addr_q <= read_addr_q[31:4];
                        read_cache_resp_q      <= m_axi_rresp;
                        read_cache_valid_q     <= 1'b1;
                        read_state             <= READ_RESP;
                    end
                end
                READ_RESP: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (read_last_word) begin
                            read_state <= READ_IDLE;
                        end else begin
                            read_addr_q       <= read_addr_q + 32'd4;
                            read_words_left_q <= read_words_left_q - 9'd1;
                            if (read_addr_q[3:2] != 2'd3) begin
                                read_state <= READ_RESP;
                            end else begin
                                read_state <= READ_REFILL_AR;
                            end
                        end
                    end
                end
                default: begin
                    read_state <= READ_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            write_state       <= WRITE_IDLE;
            write_id_q        <= 5'd0;
            write_addr_q      <= 32'd0;
            write_words_left_q <= 9'd0;
            write_burst_q     <= 2'd0;
            write_lock_q      <= 1'b0;
            write_cache_q     <= 4'd0;
            write_prot_q      <= 3'd0;
            write_chunk_data_q <= 128'd0;
            write_chunk_strb_q <= 16'd0;
            write_chunk_words_q <= 3'd0;
            write_chunk_limit_q <= 3'd0;
            write_resp_accum_q <= 2'd0;
            write_aw_sent_q   <= 1'b0;
            write_w_sent_q    <= 1'b0;
        end else begin
            case (write_state)
                WRITE_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        write_id_q         <= s_axi_awid;
                        write_addr_q       <= s_axi_awaddr;
                        write_words_left_q <= {1'b0, s_axi_awlen} + 9'd1;
                        write_burst_q      <= s_axi_awburst;
                        write_lock_q       <= s_axi_awlock;
                        write_cache_q      <= s_axi_awcache;
                        write_prot_q       <= s_axi_awprot;
                        write_chunk_data_q <= 128'd0;
                        write_chunk_strb_q <= 16'd0;
                        write_chunk_words_q <= 3'd0;
                        write_chunk_limit_q <= 3'd4 - {1'b0, s_axi_awaddr[3:2]};
                        write_resp_accum_q <= 2'd0;
                        write_aw_sent_q    <= 1'b0;
                        write_w_sent_q     <= 1'b0;
                        write_state        <= WRITE_ACCEPT_W;
                    end
                end
                WRITE_ACCEPT_W: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        write_chunk_data_q <= write_chunk_data_q |
                                              expand_word128(s_axi_wdata, write_addr_q[3:2] + write_chunk_words_q[1:0]);
                        write_chunk_strb_q <= write_chunk_strb_q |
                                              expand_strb128(s_axi_wstrb, write_addr_q[3:2] + write_chunk_words_q[1:0]);
                        write_chunk_words_q <= write_chunk_words_q + 3'd1;
                        write_aw_sent_q <= 1'b0;
                        write_w_sent_q  <= 1'b0;
                        if ((write_words_left_q == ({6'd0, write_chunk_words_q} + 9'd1)) ||
                            ((write_chunk_words_q + 3'd1) == write_chunk_limit_q)) begin
                            write_state <= WRITE_SEND_REQ;
                        end
                    end
                end
                WRITE_SEND_REQ: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        write_aw_sent_q <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        write_w_sent_q <= 1'b1;
                    end
                    if (((m_axi_awvalid && m_axi_awready) || write_aw_sent_q) &&
                        ((m_axi_wvalid && m_axi_wready) || write_w_sent_q)) begin
                        write_state <= WRITE_WAIT_B;
                    end
                end
                WRITE_WAIT_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (write_resp_accum_q == 2'b00 && m_axi_bresp != 2'b00) begin
                            write_resp_accum_q <= m_axi_bresp;
                        end
                        if (write_last_chunk) begin
                            write_state <= WRITE_RESP;
                        end else begin
                            write_addr_q        <= write_addr_q + ({29'd0, write_chunk_words_q} << 2);
                            write_words_left_q  <= write_words_left_q - {6'd0, write_chunk_words_q};
                            write_chunk_data_q  <= 128'd0;
                            write_chunk_strb_q  <= 16'd0;
                            write_chunk_words_q <= 3'd0;
                            write_chunk_limit_q <= 3'd4 - ((write_addr_q[3:2] + write_chunk_words_q[1:0]) & 2'b11);
                            write_state        <= WRITE_ACCEPT_W;
                        end
                    end
                end
                WRITE_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        write_state <= WRITE_IDLE;
                    end
                end
                default: begin
                    write_state <= WRITE_IDLE;
                end
            endcase
        end
    end

    always_comb begin
        s_axi_arready = (read_state == READ_IDLE);
        s_axi_rid     = read_id_q;
        s_axi_rdata   = read_word_data;
        s_axi_rresp   = read_cache_resp_q;
        s_axi_rlast   = read_last_word;
        s_axi_rvalid  = (read_state == READ_RESP);

        m_axi_arid    = read_id_q;
        m_axi_araddr  = {read_addr_q[31:4], 4'b0000};
        m_axi_arlen   = 8'd0;
        m_axi_arsize  = 3'd4;
        m_axi_arburst = 2'b01;
        m_axi_arlock  = read_lock_q;
        m_axi_arcache = read_cache_q;
        m_axi_arprot  = read_prot_q;
        m_axi_arvalid = (read_state == READ_REFILL_AR);
        m_axi_rready  = (read_state == READ_REFILL_R);

        s_axi_awready = (write_state == WRITE_IDLE);
        s_axi_wready  = (write_state == WRITE_ACCEPT_W);
        s_axi_bid     = write_id_q;
        s_axi_bresp   = write_resp_accum_q;
        s_axi_bvalid  = (write_state == WRITE_RESP);

        m_axi_awid    = write_id_q;
        m_axi_awaddr  = {write_addr_q[31:4], 4'b0000};
        m_axi_awlen   = 8'd0;
        m_axi_awsize  = 3'd4;
        m_axi_awburst = write_burst_q;
        m_axi_awlock  = write_lock_q;
        m_axi_awcache = write_cache_q;
        m_axi_awprot  = write_prot_q;
        m_axi_awvalid = (write_state == WRITE_SEND_REQ) && !write_aw_sent_q;
        m_axi_wdata   = write_chunk_data_q;
        m_axi_wstrb   = write_chunk_strb_q;
        m_axi_wlast   = 1'b1;
        m_axi_wvalid  = (write_state == WRITE_SEND_REQ) && !write_w_sent_q;
        m_axi_bready  = (write_state == WRITE_WAIT_B);
    end

endmodule
