module pixel_fifo #(
    parameter DEPTH = 2048
) (
    input  logic                     clk,
    input  logic                     rstn,
    input  logic                     clr,
    input  logic                     wr_en,
    input  logic [15:0]              wr_data,
    input  logic                     rd_en,
    output logic [15:0]              rd_data,
    output logic                     full,
    output logic                     empty,
    output logic [$clog2(DEPTH):0]   level
);

    localparam PTR_W = $clog2(DEPTH);

    logic [15:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr;
    logic [PTR_W-1:0] rd_ptr;
    logic [PTR_W:0]   count;

    wire wr_fire = wr_en & ~full;
    wire rd_fire = rd_en & ~empty;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign level = count;
    assign rd_data = mem[rd_ptr];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else if (clr) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            if (wr_fire) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_fire) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({wr_fire, rd_fire})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: begin
                end
            endcase
        end
    end

endmodule
