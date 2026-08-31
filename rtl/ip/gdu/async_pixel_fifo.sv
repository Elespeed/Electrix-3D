module async_pixel_fifo #(
    parameter int unsigned DATA_WIDTH = 16,
    parameter int unsigned DEPTH = 2048
) (
    input  logic                            wr_clk,
    input  logic                            wr_resetn,
    input  logic                            wr_en,
    input  logic [DATA_WIDTH-1:0]           wr_data,
    output logic                            wr_full,
    output logic [$clog2(DEPTH):0]          wr_data_count,

    input  logic                            rd_clk,
    input  logic                            rd_resetn,
    input  logic                            rd_en,
    output logic [DATA_WIDTH-1:0]           rd_data,
    output logic                            rd_empty,
    output logic [$clog2(DEPTH):0]          rd_data_count
);
    localparam int unsigned ADDR_W = $clog2(DEPTH);
    localparam int unsigned PTR_W = ADDR_W + 1;

    initial begin
        if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0)) begin
            $fatal(1, "async_pixel_fifo DEPTH must be a power of two and >= 2");
        end
    end

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_W-1:0] wr_bin;
    logic [PTR_W-1:0] wr_bin_next;
    logic [PTR_W-1:0] wr_gray;
    logic [PTR_W-1:0] wr_gray_next;
    logic [PTR_W-1:0] rd_bin;
    logic [PTR_W-1:0] rd_bin_next;
    logic [PTR_W-1:0] rd_gray;
    logic [PTR_W-1:0] rd_gray_next;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic [PTR_W-1:0] rd_gray_wr_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic [PTR_W-1:0] rd_gray_wr_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic [PTR_W-1:0] wr_gray_rd_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic [PTR_W-1:0] wr_gray_rd_sync2;

    logic [PTR_W-1:0] rd_bin_wr;
    logic [PTR_W-1:0] wr_bin_rd;

    function automatic logic [PTR_W-1:0] bin_to_gray(input logic [PTR_W-1:0] bin);
        bin_to_gray = (bin >> 1) ^ bin;
    endfunction

    function automatic logic [PTR_W-1:0] gray_to_bin(input logic [PTR_W-1:0] gray);
        logic [PTR_W-1:0] bin;
        begin
            bin[PTR_W-1] = gray[PTR_W-1];
            for (int i = PTR_W - 2; i >= 0; i--) begin
                bin[i] = bin[i + 1] ^ gray[i];
            end
            gray_to_bin = bin;
        end
    endfunction

    wire wr_fire = wr_en & ~wr_full;
    wire rd_fire = rd_en & ~rd_empty;

    assign wr_bin_next = wr_bin + {{(PTR_W-1){1'b0}}, wr_fire};
    assign wr_gray_next = bin_to_gray(wr_bin_next);
    assign rd_bin_next = rd_bin + {{(PTR_W-1){1'b0}}, rd_fire};
    assign rd_gray_next = bin_to_gray(rd_bin_next);

    assign rd_bin_wr = gray_to_bin(rd_gray_wr_sync2);
    assign wr_bin_rd = gray_to_bin(wr_gray_rd_sync2);

    // Full describes the current FIFO state.  Using wr_gray_next here makes
    // wr_full depend on wr_fire while wr_fire already depends on wr_full,
    // forming a zero-delay combinational loop that prevents simulators from
    // advancing time.  After a write, the registered wr_gray updates and this
    // expression asserts full for the following cycle as intended.
    assign wr_full = (wr_gray == {~rd_gray_wr_sync2[PTR_W-1:PTR_W-2], rd_gray_wr_sync2[PTR_W-3:0]});
    assign rd_empty = (rd_gray == wr_gray_rd_sync2);
    assign wr_data_count = wr_bin - rd_bin_wr;
    assign rd_data_count = wr_bin_rd - rd_bin;
    assign rd_data = mem[rd_bin[ADDR_W-1:0]];

    always_ff @(posedge wr_clk or negedge wr_resetn) begin
        if (!wr_resetn) begin
            wr_bin <= '0;
            wr_gray <= '0;
            rd_gray_wr_sync1 <= '0;
            rd_gray_wr_sync2 <= '0;
        end else begin
            rd_gray_wr_sync1 <= rd_gray;
            rd_gray_wr_sync2 <= rd_gray_wr_sync1;
            if (wr_fire) begin
                mem[wr_bin[ADDR_W-1:0]] <= wr_data;
                wr_bin <= wr_bin_next;
                wr_gray <= wr_gray_next;
            end
        end
    end

    always_ff @(posedge rd_clk or negedge rd_resetn) begin
        if (!rd_resetn) begin
            rd_bin <= '0;
            rd_gray <= '0;
            wr_gray_rd_sync1 <= '0;
            wr_gray_rd_sync2 <= '0;
        end else begin
            wr_gray_rd_sync1 <= wr_gray;
            wr_gray_rd_sync2 <= wr_gray_rd_sync1;
            if (rd_fire) begin
                rd_bin <= rd_bin_next;
                rd_gray <= rd_gray_next;
            end
        end
    end
endmodule
