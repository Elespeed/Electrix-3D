`include "gru_defs.vh"

module gru_seq_tracker (
    input  logic                    clk,
    input  logic                    rstn,
    input  logic                    clr,
    input  logic                    alloc_fire,
    output logic [`GRU_SEQ_W-1:0]   alloc_seq,
    output logic [`GRU_SEQ_W-1:0]   next_seq_dbg
);
    logic [`GRU_SEQ_W-1:0] next_seq;

    assign alloc_seq = next_seq;
    assign next_seq_dbg = next_seq;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            next_seq <= '0;
        end else if (clr) begin
            next_seq <= '0;
        end else if (alloc_fire) begin
            next_seq <= next_seq + 1'b1;
        end
    end
endmodule
