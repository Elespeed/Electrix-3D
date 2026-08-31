`timescale 1ns/1ps

// Generic protocol/reference checker for the observable SketchBook model stream.
// It validates frame order, triangle bounds and that adjacent frames do not hash
// identically, which would indicate the automatic rotation stalled.
module model_scene_ref_agent #(
    parameter int FRAME_W = 400,
    parameter int FRAME_H = 300
) (
    input logic clk, input logic resetn, input logic valid, input logic we, input logic ready,
    input logic [31:0] addr, input logic [31:0] wdata, output logic error
);
    localparam logic [15:0] FRAME_W_U16 = FRAME_W[15:0];
    localparam logic [15:0] FRAME_H_U16 = FRAME_H[15:0];
    logic [31:0] w0, w1, w2, w3;
    logic [2:0] write_mask;
    logic saw_clear;
    logic [31:0] frame_hash, prev_frame_hash;
    logic prev_frame_valid;
    int tri_count_in_frame;

    function automatic [31:0] mix_hash(input [31:0] current, input [31:0] value);
        begin
            mix_hash = {current[26:0], current[31:27]} ^ value ^ 32'h9e37_79b9;
        end
    endfunction

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            error <= 0;
            w0 <= 0;
            w1 <= 0;
            w2 <= 0;
            w3 <= 0;
            write_mask <= 0;
            saw_clear <= 0;
            frame_hash <= 32'h811c_9dc5;
            prev_frame_hash <= 0;
            prev_frame_valid <= 0;
            tri_count_in_frame <= 0;
        end else if (valid && we && ready) begin
            case (addr[11:0])
                12'h008: begin w0 <= wdata; write_mask <= 3'b001; end
                12'h00c: begin w1 <= wdata; write_mask <= write_mask | 3'b010; end
                12'h010: begin w2 <= wdata; write_mask <= write_mask | 3'b011; end
                12'h014: begin w3 <= wdata; write_mask <= write_mask | 3'b100; end
                12'h018: begin
                    case (w0[4:0])
                        0: begin
                            if (saw_clear || tri_count_in_frame != 0) error <= 1;
                            saw_clear <= 1;
                            frame_hash <= 32'h811c_9dc5 ^ w0;
                            tri_count_in_frame <= 0;
                        end
                        1: begin
                            if (saw_clear || tri_count_in_frame != 0) error <= 1;
                            saw_clear <= 1;
                            frame_hash <= 32'h811c_9dc5 ^ w0 ^ w1 ^ w2;
                            tri_count_in_frame <= 0;
                        end
                        5: begin
                            if (write_mask != 3'b111 || !saw_clear) error <= 1;
                            if (w1[15:0] >= FRAME_W_U16 || w1[31:16] >= FRAME_H_U16 ||
                                    w2[15:0] >= FRAME_W_U16 || w2[31:16] >= FRAME_H_U16 ||
                                    w3[15:0] >= FRAME_W_U16 || w3[31:16] >= FRAME_H_U16) error <= 1;
                            frame_hash <= mix_hash(mix_hash(mix_hash(mix_hash(frame_hash, w0), w1), w2), w3);
                            tri_count_in_frame <= tri_count_in_frame + 1;
                        end
                        6: begin
                            if (!saw_clear || tri_count_in_frame == 0) error <= 1;
                            if (prev_frame_valid && frame_hash == prev_frame_hash) error <= 1;
                            prev_frame_hash <= frame_hash;
                            prev_frame_valid <= 1;
                            frame_hash <= 32'h811c_9dc5;
                            tri_count_in_frame <= 0;
                            saw_clear <= 0;
                        end
                        default: error <= 1;
                    endcase
                    write_mask <= 0;
                end
                default: begin
                end
            endcase
        end
    end
endmodule
