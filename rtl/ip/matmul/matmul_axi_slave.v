module matmul_axi_slave #(
    // The paper-only CPU_MATMUL top enables this registered read response.
    // Leave the legacy path untouched for the existing shared SoC top.
    parameter LATCHED_READ_RESPONSE = 1'b0
) (
    input              clk,
    input              resetn,

    input              s_awvalid,
    output reg         s_awready,
    input      [31:0]  s_awaddr,
    input      [4:0]   s_awid,
    input      [7:0]   s_awlen,
    input      [2:0]   s_awsize,
    input      [1:0]   s_awburst,
    input              s_awlock,
    input      [3:0]   s_awcache,
    input      [2:0]   s_awprot,

    input              s_wvalid,
    output reg         s_wready,
    input      [31:0]  s_wdata,
    input      [3:0]   s_wstrb,
    input              s_wlast,

    output reg         s_bvalid,
    input              s_bready,
    output reg [4:0]   s_bid,
    output reg [1:0]   s_bresp,

    input              s_arvalid,
    output reg         s_arready,
    input      [31:0]  s_araddr,
    input      [4:0]   s_arid,
    input      [7:0]   s_arlen,
    input      [2:0]   s_arsize,
    input      [1:0]   s_arburst,
    input              s_arlock,
    input      [3:0]   s_arcache,
    input      [2:0]   s_arprot,

    output reg         s_rvalid,
    input              s_rready,
    output reg [31:0]  s_rdata,
    output reg [4:0]   s_rid,
    output reg [1:0]   s_rresp,
    output reg         s_rlast
);

localparam CTRL_ADDR         = 8'h00;
localparam STATUS_ADDR       = 8'h04;
localparam VERSION_ADDR      = 8'h08;
localparam A_BASE_ADDR       = 8'h10;
localparam B_BASE_ADDR       = 8'h50;
localparam C_BASE_ADDR       = 8'h90;

localparam CTRL_START_BIT    = 0;
localparam CTRL_SOFT_RST_BIT = 1;
// When set, A and B are signed Q8.8 operands (low 16 bits of each word).
// The first 16 C words then expose signed Q8.8 results, row-major.
localparam CTRL_FIXED_Q8_8_BIT = 2;

localparam STATUS_BUSY_BIT   = 0;
localparam STATUS_DONE_BIT   = 1;
localparam STATUS_ERROR_BIT  = 2;
localparam STATUS_FIXED_Q8_8_BIT = 3;

localparam VERSION_VALUE     = 32'h4d54_4d31;  // "MTM1"

integer i;
integer row;
integer col;
integer k;
integer result_idx;

reg [31:0] a_regs [0:15];
reg [31:0] b_regs [0:15];
reg [31:0] c_regs [0:47];

reg        busy;
reg        done;
reg        error;
reg [31:0] ctrl_shadow;

reg [31:0] awaddr_latched;
reg [4:0]  awid_latched;
reg        aw_pending;
reg [31:0] araddr_latched;
reg [4:0]  arid_latched;
reg        ar_pending;

reg [65:0] acc66;
reg [63:0] mul64;
reg signed [15:0] fixed_a16;
reg signed [15:0] fixed_b16;
reg signed [31:0] fixed_mul32;
reg signed [33:0] fixed_acc34;
reg signed [33:0] fixed_shift34;
reg              fixed_overflow;
reg [31:0] reg_rdata;
reg [31:0] merged_wdata;
wire [7:0] ar_word_addr = LATCHED_READ_RESPONSE ? araddr_latched[7:0] : s_araddr[7:0];

function [31:0] apply_wstrb;
    input [31:0] current;
    input [31:0] data;
    input [3:0]  strb;
    begin
        apply_wstrb = current;
        if (strb[0]) apply_wstrb[7:0]   = data[7:0];
        if (strb[1]) apply_wstrb[15:8]  = data[15:8];
        if (strb[2]) apply_wstrb[23:16] = data[23:16];
        if (strb[3]) apply_wstrb[31:24] = data[31:24];
    end
endfunction

always @(*) begin
    reg_rdata = 32'b0;

    if (ar_word_addr == CTRL_ADDR) begin
        reg_rdata = ctrl_shadow;
    end else if (ar_word_addr == STATUS_ADDR) begin
        reg_rdata = {28'b0, ctrl_shadow[CTRL_FIXED_Q8_8_BIT], error, done, busy};
    end else if (ar_word_addr == VERSION_ADDR) begin
        reg_rdata = VERSION_VALUE;
    end else if ((ar_word_addr >= A_BASE_ADDR) && (ar_word_addr < (A_BASE_ADDR + 8'h40))) begin
        reg_rdata = a_regs[(ar_word_addr - A_BASE_ADDR) >> 2];
    end else if ((ar_word_addr >= B_BASE_ADDR) && (ar_word_addr < (B_BASE_ADDR + 8'h40))) begin
        reg_rdata = b_regs[(ar_word_addr - B_BASE_ADDR) >> 2];
    // s_araddr is intentionally decoded on its low byte.  C starts at 0x90;
    // the former 8-bit 0x90 + 0xc0 upper bound wrapped to 0x50, making every
    // C read return zero even though the result registers were populated.
    end else if (ar_word_addr >= C_BASE_ADDR) begin
        reg_rdata = c_regs[(ar_word_addr - C_BASE_ADDR) >> 2];
    end
end

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        s_awready <= 1'b1;
        s_wready  <= 1'b1;
        s_bvalid  <= 1'b0;
        s_bid     <= 5'b0;
        s_bresp   <= 2'b0;
        s_arready <= 1'b1;
        s_rvalid  <= 1'b0;
        s_rdata   <= 32'b0;
        s_rid     <= 5'b0;
        s_rresp   <= 2'b0;
        s_rlast   <= 1'b0;
        awaddr_latched <= 32'b0;
        awid_latched   <= 5'b0;
        aw_pending     <= 1'b0;
        araddr_latched <= 32'b0;
        arid_latched   <= 5'b0;
        ar_pending     <= 1'b0;
        busy           <= 1'b0;
        done           <= 1'b0;
        error          <= 1'b0;
        ctrl_shadow    <= 32'b0;
        for (i = 0; i < 16; i = i + 1) begin
            a_regs[i] <= 32'b0;
            b_regs[i] <= 32'b0;
        end
        for (i = 0; i < 48; i = i + 1) begin
            c_regs[i] <= 32'b0;
        end
    end else begin
        s_awready <= (!aw_pending) && (!s_bvalid);
        s_wready  <= aw_pending && (!s_bvalid);
        s_arready <= LATCHED_READ_RESPONSE ? ((!s_rvalid) && (!ar_pending)) : !s_rvalid;

        if (s_bvalid && s_bready) begin
            s_bvalid <= 1'b0;
        end
        if (s_rvalid && s_rready) begin
            s_rvalid <= 1'b0;
            s_rlast  <= 1'b0;
        end

        if (s_awvalid && s_awready) begin
            awaddr_latched <= s_awaddr;
            awid_latched   <= s_awid;
            aw_pending     <= 1'b1;
            if ((s_awlen != 8'b0) || (s_awsize != 3'b010) || (s_awburst != 2'b01)) begin
                error <= 1'b1;
            end
        end

        if (aw_pending && s_wvalid && s_wready) begin
            aw_pending <= 1'b0;
            s_bvalid   <= 1'b1;
            s_bid      <= awid_latched;
            s_bresp    <= 2'b00;

            if (!s_wlast) begin
                error <= 1'b1;
            end

            if (awaddr_latched[7:0] == CTRL_ADDR) begin
                merged_wdata = apply_wstrb(ctrl_shadow, s_wdata, s_wstrb);
                ctrl_shadow  <= merged_wdata & 32'h0000_0007;

                if (merged_wdata[CTRL_SOFT_RST_BIT]) begin
                    busy  <= 1'b0;
                    done  <= 1'b0;
                    error <= 1'b0;
                    for (i = 0; i < 48; i = i + 1) begin
                        c_regs[i] <= 32'b0;
                    end
                end else if (merged_wdata[CTRL_START_BIT]) begin
                    if (busy) begin
                        error <= 1'b1;
                    end else begin
                        busy <= 1'b1;
                        done <= 1'b0;
                        fixed_overflow = 1'b0;
                        for (row = 0; row < 4; row = row + 1) begin
                            for (col = 0; col < 4; col = col + 1) begin
                                if (merged_wdata[CTRL_FIXED_Q8_8_BIT]) begin
                                    fixed_acc34 = 34'sd0;
                                    for (k = 0; k < 4; k = k + 1) begin
                                        fixed_a16 = $signed(a_regs[row * 4 + k][15:0]);
                                        fixed_b16 = $signed(b_regs[k * 4 + col][15:0]);
                                        fixed_mul32 = fixed_a16 * fixed_b16;
                                        fixed_acc34 = fixed_acc34 + fixed_mul32;
                                    end
                                    // Q16.16 accumulator to Q8.8 result.
                                    fixed_shift34 = fixed_acc34 >>> 8;
                                    if ((fixed_shift34 > 34'sd2147483647) ||
                                        (fixed_shift34 < -34'sd2147483648)) begin
                                        fixed_overflow = 1'b1;
                                    end
                                    c_regs[row * 4 + col] <= fixed_shift34[31:0];
                                end else begin
                                    // Legacy unsigned 66-bit result format.
                                    acc66 = 66'b0;
                                    for (k = 0; k < 4; k = k + 1) begin
                                        mul64 = a_regs[row * 4 + k] * b_regs[k * 4 + col];
                                        acc66 = acc66 + {2'b00, mul64};
                                    end
                                    result_idx = (row * 4 + col) * 3;
                                    c_regs[result_idx + 0] <= acc66[31:0];
                                    c_regs[result_idx + 1] <= acc66[63:32];
                                    c_regs[result_idx + 2] <= {30'b0, acc66[65:64]};
                                end
                            end
                        end
                        if (fixed_overflow)
                            error <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end
            end else if ((awaddr_latched[7:0] >= A_BASE_ADDR) && (awaddr_latched[7:0] < (A_BASE_ADDR + 8'h40))) begin
                a_regs[(awaddr_latched[7:0] - A_BASE_ADDR) >> 2] <=
                    apply_wstrb(a_regs[(awaddr_latched[7:0] - A_BASE_ADDR) >> 2], s_wdata, s_wstrb);
            end else if ((awaddr_latched[7:0] >= B_BASE_ADDR) && (awaddr_latched[7:0] < (B_BASE_ADDR + 8'h40))) begin
                b_regs[(awaddr_latched[7:0] - B_BASE_ADDR) >> 2] <=
                    apply_wstrb(b_regs[(awaddr_latched[7:0] - B_BASE_ADDR) >> 2], s_wdata, s_wstrb);
            end else if ((awaddr_latched[7:0] >= C_BASE_ADDR) && (awaddr_latched[7:0] < (C_BASE_ADDR + 8'hc0))) begin
                c_regs[(awaddr_latched[7:0] - C_BASE_ADDR) >> 2] <=
                    apply_wstrb(c_regs[(awaddr_latched[7:0] - C_BASE_ADDR) >> 2], s_wdata, s_wstrb);
            end else begin
                error <= 1'b1;
            end
        end

        if (s_arvalid && s_arready) begin
            if (LATCHED_READ_RESPONSE) begin
                araddr_latched <= s_araddr;
                arid_latched   <= s_arid;
                ar_pending     <= 1'b1;
            end else begin
                s_rvalid <= 1'b1;
                s_rid    <= s_arid;
                s_rresp  <= 2'b00;
                s_rlast  <= 1'b1;
                s_rdata  <= reg_rdata;
            end
            if ((s_arlen != 8'b0) || (s_arsize != 3'b010) || (s_arburst != 2'b01)) error <= 1'b1;
        end
        if (LATCHED_READ_RESPONSE && ar_pending && !s_rvalid) begin
            ar_pending <= 1'b0;
            s_rvalid <= 1'b1;
            s_rid    <= arid_latched;
            s_rresp  <= 2'b00;
            s_rlast  <= 1'b1;
            s_rdata  <= reg_rdata;
        end
    end
end

endmodule
