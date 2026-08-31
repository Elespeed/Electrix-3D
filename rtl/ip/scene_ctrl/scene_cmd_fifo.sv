// Fixed-width command FIFO for the multi-mesh Scene front end.  Commands are
// queued only while a frame is being assembled; FRAME_START locks the queue
// until the consumer reports frame_complete or frame_error.
module scene_cmd_fifo #(
    parameter int DEPTH = 16,
    parameter int WIDTH = 128,
    parameter int AW = $clog2(DEPTH)
) (
    input  logic clk, input logic resetn,
    input  logic push_valid, input logic [WIDTH-1:0] push_data,
    output logic push_ready, output logic [$clog2(DEPTH+1)-1:0] level,
    output logic full, output logic locked,
    input  logic frame_start, input logic frame_complete, input logic frame_error,
    input  logic pop, output logic [WIDTH-1:0] head, output logic empty
);
    (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [AW-1:0] wr_ptr, rd_ptr;
    logic [$clog2(DEPTH+1)-1:0] count;
    assign level = count;
    assign empty = (count == 0);
    assign full = (count == DEPTH);
    assign push_ready = !locked && !full;
    assign head = mem[rd_ptr];
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr <= '0; rd_ptr <= '0; count <= '0; locked <= 1'b0;
        end else begin
            if (frame_complete || frame_error) begin
                wr_ptr <= '0; rd_ptr <= '0; count <= '0; locked <= 1'b0;
            end else begin
                if (frame_start && !locked && count != 0) locked <= 1'b1;
                if (push_valid && push_ready) begin
                    mem[wr_ptr] <= push_data;
                    wr_ptr <= wr_ptr + 1'b1;
                    count <= count + 1'b1;
                end
                if (pop && locked && !empty) begin
                    rd_ptr <= rd_ptr + 1'b1;
                    count <= count - 1'b1;
                end
            end
        end
    end
endmodule
