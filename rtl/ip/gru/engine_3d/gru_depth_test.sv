module gru_depth_test (
    input  logic [15:0] old_depth,
    input  logic [15:0] new_depth,
    input  logic        compare_lequal,
    output logic        pass
);
    always_comb begin
        if (compare_lequal) begin
            pass = (new_depth <= old_depth);
        end else begin
            pass = (new_depth < old_depth);
        end
    end
endmodule
