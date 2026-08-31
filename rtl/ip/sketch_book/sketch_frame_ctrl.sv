// Ownership controller for the two BRAM framebuffer pages.  PRESENT arrives
// only after the GRU has retired all earlier commands; the actual page swap is
// deliberately delayed until a GDU frame boundary.
module sketch_frame_ctrl (
    input  logic clk,
    input  logic resetn,
    input  logic frame_boundary,
    input  logic present_req,
    input  logic gru_write_attempt,
    output logic front_idx,
    output logic back_idx,
    output logic front_valid,
    output logic swap_pending,
    output logic render_allowed,
    output logic swap_done,
    output logic active_write_error,
    output logic [31:0] frame_counter,
    output logic [31:0] swap_counter
);
    assign render_allowed = !swap_pending;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            front_idx <= 1'b0;
            back_idx <= 1'b1;
            front_valid <= 1'b0;
            swap_pending <= 1'b0;
            swap_done <= 1'b0;
            active_write_error <= 1'b0;
            frame_counter <= '0;
            swap_counter <= '0;
        end else begin
            swap_done <= 1'b0;
            if (gru_write_attempt && !render_allowed)
                active_write_error <= 1'b1;
            if (present_req)
                swap_pending <= 1'b1;
            if (frame_boundary) begin
                frame_counter <= frame_counter + 1'b1;
                if (swap_pending || present_req) begin
                    front_idx <= back_idx;
                    back_idx <= front_idx;
                    front_valid <= 1'b1;
                    swap_pending <= 1'b0;
                    swap_done <= 1'b1;
                    swap_counter <= swap_counter + 1'b1;
                end
            end
        end
    end
endmodule
