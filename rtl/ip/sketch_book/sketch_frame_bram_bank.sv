// Two RGB332 pages, packed as eight pixels per 64-bit word.  Byte write
// enables make clipped/unaligned spans safe without a read-modify-write path.
module sketch_frame_bram_bank #(
    parameter int SRC_W = 400,
    parameter int SRC_H = 300,
    parameter int ADDR_W = $clog2((SRC_W * SRC_H) / 8)
) (
    input  logic              clk,
    input  logic              gru_we,
    input  logic              gru_page,
    input  logic [ADDR_W-1:0] gru_addr,
    input  logic [63:0]       gru_wdata,
    input  logic [7:0]        gru_wstrb,
    input  logic              gdu_page,
    input  logic [ADDR_W-1:0] gdu_addr,
    output logic [63:0]       gdu_rdata
);
    logic [63:0] color_fb0_rdata, color_fb1_rdata;

    sketch_frame_page_bram #(.AW(ADDR_W)) u_color_fb0 (
        .clk(clk), .wr_en(gru_we && !gru_page), .wr_addr(gru_addr),
        .wr_data(gru_wdata), .wr_strb(gru_wstrb), .rd_addr(gdu_addr), .rd_data(color_fb0_rdata)
    );
    sketch_frame_page_bram #(.AW(ADDR_W)) u_color_fb1 (
        .clk(clk), .wr_en(gru_we && gru_page), .wr_addr(gru_addr),
        .wr_data(gru_wdata), .wr_strb(gru_wstrb), .rd_addr(gdu_addr), .rd_data(color_fb1_rdata)
    );

    assign gdu_rdata = gdu_page ? color_fb1_rdata : color_fb0_rdata;
endmodule

module sketch_frame_page_bram #(
    parameter int AW = 14
) (
    input  logic          clk,
    input  logic          wr_en,
    input  logic [AW-1:0] wr_addr,
    input  logic [63:0]   wr_data,
    input  logic [7:0]    wr_strb,
    input  logic [AW-1:0] rd_addr,
    output logic [63:0]   rd_data
);
    localparam int DEPTH = 1 << AW;
    localparam V_STYLE = "block";
    localparam P_STYLE = "block_ram";
    (* ram_style = V_STYLE *) logic [63:0] BRAM [0:DEPTH-1]
        /* synthesis syn_ramstyle = P_STYLE */;
    logic [AW-1:0] rd_addr_q;

    always_ff @(posedge clk) begin
        if (wr_en) begin
            for (int lane = 0; lane < 8; lane = lane + 1)
                if (wr_strb[lane])
                    BRAM[wr_addr][lane*8 +: 8] <= wr_data[lane*8 +: 8];
        end
        rd_addr_q <= rd_addr;
    end

    assign rd_data = BRAM[rd_addr_q];
endmodule
