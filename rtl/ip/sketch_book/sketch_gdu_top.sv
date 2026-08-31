module sketch_gdu_top #(
    parameter int SRC_W = 400,
    parameter int SRC_H = 300,
    parameter int OUT_W = 800,
    parameter int OUT_H = 600,
    parameter int H_FRONT = 56,
    parameter int H_SYNC = 120,
    parameter int H_BACK = 64,
    parameter int V_FRONT = 37,
    parameter int V_SYNC = 6,
    parameter int V_BACK = 23,
    parameter bit HSYNC_ACTIVE_LOW = 1'b0,
    parameter bit VSYNC_ACTIVE_LOW = 1'b0,
    parameter int ADDR_W = $clog2((SRC_W * SRC_H) / 8)
) (
    input  logic clk,
    input  logic resetn,
    input  logic display_enable,
    input  logic frame_valid,
    input  logic front_page,
    output logic gdu_page,
    output logic [ADDR_W-1:0] gdu_addr,
    input  logic [63:0] gdu_rdata,
    output logic frame_boundary,
    output logic dvi_clk,
    output logic dvi_hs,
    output logic dvi_vs,
    output logic dvi_de,
    output logic [7:0] dvi_d
);
    localparam int H_TOTAL = OUT_W + H_FRONT + H_SYNC + H_BACK;
    localparam int V_TOTAL = OUT_H + V_FRONT + V_SYNC + V_BACK;
    logic [$clog2(H_TOTAL)-1:0] h_cnt;
    logic [$clog2(V_TOTAL)-1:0] v_cnt;
    logic timing_de, timing_hs, timing_vs;
    logic hs_d, vs_d, de_d;
    logic [ADDR_W-1:0] src_addr;
    logic [ADDR_W+2:0] src_pixel_addr;
    logic [$clog2(SRC_W)-1:0] src_x;
    logic [$clog2(SRC_H)-1:0] src_y;

    sketch_timing_800x600 #(
        .OUT_W(OUT_W), .OUT_H(OUT_H),
        .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
        .HSYNC_ACTIVE_LOW(HSYNC_ACTIVE_LOW), .VSYNC_ACTIVE_LOW(VSYNC_ACTIVE_LOW)
    ) u_timing (
        .clk(clk), .resetn(resetn), .run(display_enable),
        .h_cnt(h_cnt), .v_cnt(v_cnt), .de(timing_de),
        .hs(timing_hs), .vs(timing_vs), .frame_boundary(frame_boundary)
    );

    always_comb begin
        src_x = h_cnt >> 1;
        src_y = v_cnt >> 1;
        // SRC_W=400 = 256+128+16.  For reduced-size simulation instances the
        // constant multiply is retained so the same module remains reusable.
        if (SRC_W == 400)
            src_pixel_addr = ({3'd0, src_y} << 8) + ({3'd0, src_y} << 7) +
                             ({3'd0, src_y} << 4) + src_x;
        else
            src_pixel_addr = src_y * SRC_W + src_x;
        src_addr = src_pixel_addr >> 3;
        // Do not address outside the BRAM during porches.  This is important
        // for simulators that diagnose out-of-range array reads as warnings.
        gdu_addr = timing_de ? src_addr : '0;
        gdu_page = front_page;
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            hs_d <= 1'b0;
            vs_d <= 1'b0;
            de_d <= 1'b0;
        end else begin
            hs_d <= timing_hs;
            vs_d <= timing_vs;
            de_d <= timing_de;
        end
    end

    assign dvi_clk = clk;
    assign dvi_hs = hs_d;
    assign dvi_vs = vs_d;
    assign dvi_de = de_d;
    // The first front page contains power-up BRAM contents.  Keep timing live
    // so the initial swap can happen, but present black until a rendered page
    // has reached the front.
    logic [2:0] pixel_lane_d;
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            pixel_lane_d <= '0;
        else
            pixel_lane_d <= src_x[2:0];
    end
    assign dvi_d = (de_d && frame_valid) ? gdu_rdata[pixel_lane_d*8 +: 8] : 8'h00;
endmodule
