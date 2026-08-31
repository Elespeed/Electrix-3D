module lcd_axi_reader (
    input  logic        clk,
    input  logic        rstn,
    input  logic        start,
    input  logic        abort,
    input  logic [31:0] fb_base,
    input  logic [31:0] stride,
    input  logic [15:0] rect_x,
    input  logic [15:0] rect_y,
    input  logic [15:0] rect_w,
    input  logic [15:0] rect_h,

    output logic        pixel_valid,
    input  logic        pixel_ready,
    output logic [15:0] pixel_data,

    output logic        busy,
    output logic        done,
    output logic        axi_error,

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

    typedef enum logic [1:0] {
        RD_IDLE  = 2'd0,
        RD_AR    = 2'd1,
        RD_R     = 2'd2,
        RD_EMIT  = 2'd3
    } rd_state_t;

    rd_state_t state;

    logic [15:0] row_idx;
    logic [15:0] col_idx;
    logic [2:0]  lane_idx;
    logic [3:0]  emit_left;
    logic [127:0] beat_data;
    logic [31:0] byte_addr;
    logic [31:0] aligned_addr;
    logic [15:0] row_left;
    logic [3:0]  lane_room;
    logic [3:0]  issue_pixels;

    assign m_axi_arid    = 5'd1;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'b100;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_rready  = (state == RD_R);

    always_comb begin
        byte_addr = fb_base + (({16'd0, rect_y} + {16'd0, row_idx}) * stride) +
                    (({16'd0, rect_x} + {16'd0, col_idx}) << 1);
        aligned_addr = {byte_addr[31:4], 4'b0000};
        row_left = rect_w - col_idx;
        lane_room = 4'd8 - {1'b0, byte_addr[3:1]};
        issue_pixels = (row_left < {12'd0, lane_room}) ? row_left[3:0] : lane_room;
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state         <= RD_IDLE;
            row_idx       <= 16'd0;
            col_idx       <= 16'd0;
            lane_idx      <= 3'd0;
            emit_left     <= 4'd0;
            beat_data     <= 128'd0;
            pixel_valid   <= 1'b0;
            pixel_data    <= 16'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            axi_error     <= 1'b0;
            m_axi_araddr  <= 32'd0;
            m_axi_arvalid <= 1'b0;
        end else begin
            done <= 1'b0;

            if (abort) begin
                state         <= RD_IDLE;
                busy          <= 1'b0;
                pixel_valid   <= 1'b0;
                m_axi_arvalid <= 1'b0;
                row_idx       <= 16'd0;
                col_idx       <= 16'd0;
                emit_left     <= 4'd0;
            end else begin
                case (state)
                    RD_IDLE: begin
                        pixel_valid   <= 1'b0;
                        m_axi_arvalid <= 1'b0;
                        if (start) begin
                            busy      <= 1'b1;
                            done      <= 1'b0;
                            axi_error <= 1'b0;
                            row_idx   <= 16'd0;
                            col_idx   <= 16'd0;
                            state     <= RD_AR;
                        end else begin
                            busy <= 1'b0;
                        end
                    end

                    RD_AR: begin
                        pixel_valid <= 1'b0;
                        if (!m_axi_arvalid) begin
                            m_axi_araddr  <= aligned_addr;
                            m_axi_arvalid <= 1'b1;
                        end else if (m_axi_arready) begin
                            m_axi_arvalid <= 1'b0;
                            state <= RD_R;
                        end
                    end

                    RD_R: begin
                        if (m_axi_rvalid) begin
                            beat_data <= m_axi_rdata;
                            lane_idx  <= byte_addr[3:1];
                            emit_left <= issue_pixels;
                            if ((m_axi_rresp != 2'b00) || !m_axi_rlast) begin
                                axi_error <= 1'b1;
                            end
                            state <= RD_EMIT;
                        end
                    end

                    RD_EMIT: begin
                        if (!pixel_valid && (emit_left != 4'd0)) begin
                            pixel_data  <= beat_data[{lane_idx, 4'b0000} +: 16];
                            pixel_valid <= 1'b1;
                        end else if (pixel_valid && pixel_ready) begin
                            pixel_valid <= 1'b0;
                            if (emit_left <= 4'd1) begin
                                if ((col_idx + {12'd0, issue_pixels}) >= rect_w) begin
                                    col_idx <= 16'd0;
                                    if ((row_idx + 16'd1) >= rect_h) begin
                                        busy <= 1'b0;
                                        done <= 1'b1;
                                        state <= RD_IDLE;
                                    end else begin
                                        row_idx <= row_idx + 16'd1;
                                        state <= RD_AR;
                                    end
                                end else begin
                                    col_idx <= col_idx + {12'd0, issue_pixels};
                                    state <= RD_AR;
                                end
                            end else begin
                                lane_idx  <= lane_idx + 3'd1;
                                emit_left <= emit_left - 4'd1;
                            end
                        end
                    end

                    default: state <= RD_IDLE;
                endcase
            end
        end
    end

    wire [5:0] _unused_axi = {m_axi_rid[0], byte_addr[0], aligned_addr[0], lane_room[0], row_left[0], issue_pixels[0]};

endmodule
