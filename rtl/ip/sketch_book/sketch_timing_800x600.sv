// Single-clock video timing generator.  The *_FRONT/SYNC/BACK parameters are
// widths, unlike the counter-boundary convention used by the legacy GDU.
module sketch_timing_800x600 #(
    parameter int OUT_W  = 800,
    parameter int OUT_H  = 600,
    parameter int H_FRONT = 56,
    parameter int H_SYNC  = 120,
    parameter int H_BACK  = 64,
    parameter int V_FRONT = 37,
    parameter int V_SYNC  = 6,
    parameter int V_BACK  = 23,
    parameter bit HSYNC_ACTIVE_LOW = 1'b0,
    parameter bit VSYNC_ACTIVE_LOW = 1'b0
) (
    input  logic clk,
    input  logic resetn,
    input  logic run,
    output logic [$clog2(OUT_W + H_FRONT + H_SYNC + H_BACK)-1:0] h_cnt,
    output logic [$clog2(OUT_H + V_FRONT + V_SYNC + V_BACK)-1:0] v_cnt,
    output logic de,
    output logic hs,
    output logic vs,
    // Asserted during the final pixel-clock of a frame, before counters wrap.
    output logic frame_boundary
);
    localparam int H_TOTAL = OUT_W + H_FRONT + H_SYNC + H_BACK;
    localparam int V_TOTAL = OUT_H + V_FRONT + V_SYNC + V_BACK;

    logic hs_active;
    logic vs_active;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else if (!run) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= '0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= '0;
            else
                v_cnt <= v_cnt + 1'b1;
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    always_comb begin
        de = run && (h_cnt < OUT_W) && (v_cnt < OUT_H);
        hs_active = (h_cnt >= OUT_W + H_FRONT) &&
                    (h_cnt < OUT_W + H_FRONT + H_SYNC);
        vs_active = (v_cnt >= OUT_H + V_FRONT) &&
                    (v_cnt < OUT_H + V_FRONT + V_SYNC);
        hs = HSYNC_ACTIVE_LOW ? ~hs_active : hs_active;
        vs = VSYNC_ACTIVE_LOW ? ~vs_active : vs_active;
        frame_boundary = run && (h_cnt == H_TOTAL - 1) &&
                         (v_cnt == V_TOTAL - 1);
    end
endmodule
