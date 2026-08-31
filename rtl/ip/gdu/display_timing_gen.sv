module display_timing_gen #(
    parameter H_ACTIVE = 12'd800,
    parameter H_FRONT  = 12'd56,
    parameter H_SYNC   = 12'd120,
    parameter H_BACK   = 12'd64,
    parameter H_TOTAL  = 12'd1040,
    parameter V_ACTIVE = 12'd600,
    parameter V_FRONT  = 12'd37,
    parameter V_SYNC   = 12'd6,
    parameter V_BACK   = 12'd23,
    parameter V_TOTAL  = 12'd666,
    parameter H_POL    = 1'b1,
    parameter V_POL    = 1'b1
) (
    input  logic        clk,
    input  logic        rstn,
    input  logic        run,
    output logic [11:0] x,
    output logic [11:0] y,
    output logic        hsync,
    output logic        vsync,
    output logic        de,
    output logic        frame_start,
    output logic        line_start,
    output logic        vblank_enter
);

    logic [11:0] h_cnt;
    logic [11:0] v_cnt;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            h_cnt <= 12'd0;
            v_cnt <= 12'd0;
        end else if (!run) begin
            h_cnt <= 12'd0;
            v_cnt <= 12'd0;
        end else begin
            if (h_cnt == (H_TOTAL - 1'b1)) begin
                h_cnt <= 12'd0;
                if (v_cnt == (V_TOTAL - 1'b1)) begin
                    v_cnt <= 12'd0;
                end else begin
                    v_cnt <= v_cnt + 1'b1;
                end
            end else begin
                h_cnt <= h_cnt + 1'b1;
            end
        end
    end

    assign x = h_cnt;
    assign y = v_cnt;
    assign de = run && (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    assign line_start  = run && (h_cnt == 12'd0) && (v_cnt < V_ACTIVE);
    assign frame_start = run && (h_cnt == 12'd0) && (v_cnt == 12'd0);
    assign vblank_enter = run && (h_cnt == 12'd0) && (v_cnt == V_ACTIVE);

    wire hsync_act = (h_cnt >= (H_ACTIVE + H_FRONT)) && (h_cnt < (H_ACTIVE + H_FRONT + H_SYNC));
    wire vsync_act = (v_cnt >= (V_ACTIVE + V_FRONT)) && (v_cnt < (V_ACTIVE + V_FRONT + V_SYNC));

    assign hsync = H_POL ? hsync_act : ~hsync_act;
    assign vsync = V_POL ? vsync_act : ~vsync_act;

endmodule
