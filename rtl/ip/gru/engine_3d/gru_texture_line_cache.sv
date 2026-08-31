module gru_texture_line_cache (
    input  logic         clk,
    input  logic         rstn,
    input  logic         clr,
    input  logic         req_valid,
    output logic         req_ready,
    input  logic [31:0]  req_addr,
    output logic         resp_valid,
    input  logic         resp_ready,
    output logic [127:0] resp_data,
    output logic         resp_error,
    output logic [31:0]  hit_count,
    output logic [31:0]  miss_count,
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
    output logic         m_axi_rready
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_LOOKUP,
        S_WAIT_AR,
        S_WAIT_R,
        S_RESP
    } state_t;

    state_t state_q;
    logic        line_valid_q;
    logic [31:0] line_addr_q;
    logic [127:0] line_data_q;
    logic [31:0] miss_addr_q;
    logic [31:0] lookup_addr_q;
    logic [127:0] resp_data_q;
    logic         resp_error_q;
    logic [31:0] req_line_addr;
    logic        line_hit;

    assign req_line_addr = {req_addr[31:4], 4'b0000};
    assign line_hit = line_valid_q && (line_addr_q == lookup_addr_q);

    assign req_ready = (state_q == S_IDLE);
    assign resp_valid = (state_q == S_RESP);
    assign resp_data = resp_data_q;
    assign resp_error = resp_error_q;

    assign m_axi_arid = 5'd0;
    assign m_axi_araddr = miss_addr_q;
    assign m_axi_arlen = 8'd0;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arvalid = (state_q == S_WAIT_AR);
    assign m_axi_rready = (state_q == S_WAIT_R);

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state_q <= S_IDLE;
            line_valid_q <= 1'b0;
            line_addr_q <= 32'd0;
            line_data_q <= 128'd0;
            miss_addr_q <= 32'd0;
            lookup_addr_q <= 32'd0;
            resp_data_q <= 128'd0;
            resp_error_q <= 1'b0;
            hit_count <= 32'd0;
            miss_count <= 32'd0;
        end else if (clr) begin
            state_q <= S_IDLE;
            line_valid_q <= 1'b0;
            miss_addr_q <= 32'd0;
            lookup_addr_q <= 32'd0;
            resp_data_q <= 128'd0;
            resp_error_q <= 1'b0;
        end else begin
            case (state_q)
                S_IDLE: begin
                    resp_error_q <= 1'b0;
                    if (req_valid) begin
                        lookup_addr_q <= req_line_addr;
                        state_q <= S_LOOKUP;
                    end
                end
                S_LOOKUP: begin
                    if (line_hit) begin
                        resp_data_q <= line_data_q;
                        hit_count <= hit_count + 32'd1;
                        state_q <= S_RESP;
                    end else begin
                        miss_addr_q <= lookup_addr_q;
                        miss_count <= miss_count + 32'd1;
                        state_q <= S_WAIT_AR;
                    end
                end
                S_WAIT_AR: begin
                    if (m_axi_arready) begin
                        state_q <= S_WAIT_R;
                    end
                end
                S_WAIT_R: begin
                    if (m_axi_rvalid && m_axi_rlast) begin
                        line_valid_q <= 1'b1;
                        line_addr_q <= miss_addr_q;
                        line_data_q <= m_axi_rdata;
                        resp_data_q <= m_axi_rdata;
                        resp_error_q <= (m_axi_rresp != 2'b00);
                        state_q <= S_RESP;
                    end
                end
                S_RESP: begin
                    if (resp_ready) begin
                        state_q <= S_IDLE;
                    end
                end
                default: begin
                    state_q <= S_IDLE;
                end
            endcase
        end
    end
endmodule
