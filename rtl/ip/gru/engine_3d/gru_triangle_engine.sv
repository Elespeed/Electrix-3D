`include "gru_defs.vh"

module gru_triangle_engine (
    input  logic                      clk,
    input  logic                      rstn,
    input  logic                      clr,
    input  logic [15:0]               frame_w,
    input  logic [15:0]               frame_h,
    input  logic [31:0]               tex_base,
    input  logic [31:0]               tex_stride,
    input  logic [15:0]               tex_width,
    input  logic [15:0]               tex_height,
    input  logic [2:0]                tex_format,
    input  logic                      tex_wrap_mode,
    input  logic                      cmd_valid,
    output logic                      cmd_ready,
    input  logic [`GRU_TRI_CMD_W-1:0] cmd_data,
    output logic                      span_valid,
    input  logic                      span_ready,
    output logic [`GRU_SPAN_W-1:0]    span_data,
    output logic [4:0]                m_axi_arid,
    output logic [31:0]               m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arlock,
    output logic [3:0]                m_axi_arcache,
    output logic [2:0]                m_axi_arprot,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [4:0]                m_axi_rid,
    input  logic [127:0]              m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready
);
    logic [`GRU_SEQ_W-1:0]   seq_id;
    logic [4:0]              opcode;
    logic                    gouraud_en;
    logic                    textured_en;
    logic                    perspective_en;
    logic [`GRU_COLOR_W-1:0] color_idx;
    logic [15:0]             flat_rgb565;
    logic [15:0]             c0_rgb565;
    logic [15:0]             c1_rgb565;
    logic [15:0]             c2_rgb565;
    logic signed [15:0]      u0_q8_8, v0_q8_8, u1_q8_8, v1_q8_8, u2_q8_8, v2_q8_8;
    logic signed [15:0]      inv_w0_q8_8, inv_w1_q8_8, inv_w2_q8_8;
    logic signed [15:0]      x0, y0, x1, y1, x2, y2;
    logic signed [15:0]      bbox_min_x, bbox_max_x, bbox_min_y, bbox_max_y;
    logic signed [31:0]      area2;
    logic                    reject;
    logic                    raster_busy;
    logic                    start_raster;
    logic                    setup_pending_q;
    logic [`GRU_SEQ_W-1:0]   seq_q;
    logic                    gouraud_q;
    logic                    textured_q;
    logic                    perspective_q;
    logic [15:0]             flat_rgb565_q;
    logic [15:0]             c0_rgb565_q;
    logic [15:0]             c1_rgb565_q;
    logic [15:0]             c2_rgb565_q;
    logic signed [15:0]      u0_q8_8_q, v0_q8_8_q, u1_q8_8_q, v1_q8_8_q, u2_q8_8_q, v2_q8_8_q;
    logic signed [15:0]      inv_w0_q8_8_q, inv_w1_q8_8_q, inv_w2_q8_8_q;
    logic signed [15:0]      x0_q, y0_q, x1_q, y1_q, x2_q, y2_q;
    logic signed [15:0]      bbox_min_x_q, bbox_max_x_q, bbox_min_y_q, bbox_max_y_q;
    logic signed [31:0]      area2_q;
    logic                    reject_q;

    gru_colour_lut u_gru_colour_lut (
        .color_idx (color_idx),
        .rgb565    (flat_rgb565)
    );

    gru_triangle_setup u_gru_triangle_setup (
        .tri_cmd    (cmd_data),
        .frame_w    (frame_w),
        .frame_h    (frame_h),
        .seq_id     (seq_id),
        .opcode     (opcode),
        .gouraud_en (gouraud_en),
        .textured_en(textured_en),
        .perspective_en(perspective_en),
        .color_idx  (color_idx),
        .c0_rgb565  (c0_rgb565),
        .c1_rgb565  (c1_rgb565),
        .c2_rgb565  (c2_rgb565),
        .u0_q8_8    (u0_q8_8),
        .v0_q8_8    (v0_q8_8),
        .u1_q8_8    (u1_q8_8),
        .v1_q8_8    (v1_q8_8),
        .u2_q8_8    (u2_q8_8),
        .v2_q8_8    (v2_q8_8),
        .inv_w0_q8_8(inv_w0_q8_8),
        .inv_w1_q8_8(inv_w1_q8_8),
        .inv_w2_q8_8(inv_w2_q8_8),
        .x0         (x0),
        .y0         (y0),
        .x1         (x1),
        .y1         (y1),
        .x2         (x2),
        .y2         (y2),
        .bbox_min_x (bbox_min_x),
        .bbox_max_x (bbox_max_x),
        .bbox_min_y (bbox_min_y),
        .bbox_max_y (bbox_max_y),
        .area2      (area2),
        .reject     (reject)
    );

    assign cmd_ready = ~raster_busy & ~setup_pending_q;
    assign start_raster = setup_pending_q & ~raster_busy;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            setup_pending_q <= 1'b0;
            seq_q <= '0;
            gouraud_q <= 1'b0;
            textured_q <= 1'b0;
            perspective_q <= 1'b0;
            flat_rgb565_q <= '0;
            c0_rgb565_q <= '0;
            c1_rgb565_q <= '0;
            c2_rgb565_q <= '0;
            u0_q8_8_q <= '0;
            v0_q8_8_q <= '0;
            u1_q8_8_q <= '0;
            v1_q8_8_q <= '0;
            u2_q8_8_q <= '0;
            v2_q8_8_q <= '0;
            inv_w0_q8_8_q <= '0;
            inv_w1_q8_8_q <= '0;
            inv_w2_q8_8_q <= '0;
            x0_q <= '0;
            y0_q <= '0;
            x1_q <= '0;
            y1_q <= '0;
            x2_q <= '0;
            y2_q <= '0;
            bbox_min_x_q <= '0;
            bbox_max_x_q <= '0;
            bbox_min_y_q <= '0;
            bbox_max_y_q <= '0;
            area2_q <= '0;
            reject_q <= 1'b0;
        end else if (clr) begin
            setup_pending_q <= 1'b0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                setup_pending_q <= 1'b1;
                seq_q <= seq_id;
                gouraud_q <= gouraud_en;
                textured_q <= textured_en;
                perspective_q <= perspective_en;
                flat_rgb565_q <= flat_rgb565;
                c0_rgb565_q <= c0_rgb565;
                c1_rgb565_q <= c1_rgb565;
                c2_rgb565_q <= c2_rgb565;
                u0_q8_8_q <= u0_q8_8;
                v0_q8_8_q <= v0_q8_8;
                u1_q8_8_q <= u1_q8_8;
                v1_q8_8_q <= v1_q8_8;
                u2_q8_8_q <= u2_q8_8;
                v2_q8_8_q <= v2_q8_8;
                inv_w0_q8_8_q <= inv_w0_q8_8;
                inv_w1_q8_8_q <= inv_w1_q8_8;
                inv_w2_q8_8_q <= inv_w2_q8_8;
                x0_q <= x0;
                y0_q <= y0;
                x1_q <= x1;
                y1_q <= y1;
                x2_q <= x2;
                y2_q <= y2;
                bbox_min_x_q <= bbox_min_x;
                bbox_max_x_q <= bbox_max_x;
                bbox_min_y_q <= bbox_min_y;
                bbox_max_y_q <= bbox_max_y;
                area2_q <= area2;
                reject_q <= reject;
            end else if (start_raster) begin
                setup_pending_q <= 1'b0;
            end
        end
    end

    gru_triangle_raster u_gru_triangle_raster (
        .clk        (clk),
        .rstn       (rstn),
        .clr        (clr),
        .start      (start_raster),
        .seq_id     (seq_q),
        .gouraud_en (gouraud_q),
        .textured_en(textured_q),
        .perspective_en(perspective_q),
        .flat_rgb565(flat_rgb565_q),
        .c0_rgb565  (c0_rgb565_q),
        .c1_rgb565  (c1_rgb565_q),
        .c2_rgb565  (c2_rgb565_q),
        .u0_q8_8    (u0_q8_8_q),
        .v0_q8_8    (v0_q8_8_q),
        .u1_q8_8    (u1_q8_8_q),
        .v1_q8_8    (v1_q8_8_q),
        .u2_q8_8    (u2_q8_8_q),
        .v2_q8_8    (v2_q8_8_q),
        .inv_w0_q8_8(inv_w0_q8_8_q),
        .inv_w1_q8_8(inv_w1_q8_8_q),
        .inv_w2_q8_8(inv_w2_q8_8_q),
        .tex_base   (tex_base),
        .tex_stride (tex_stride),
        .tex_width  (tex_width),
        .tex_height (tex_height),
        .tex_format (tex_format),
        .tex_wrap_mode(tex_wrap_mode),
        .x0         (x0_q),
        .y0         (y0_q),
        .x1         (x1_q),
        .y1         (y1_q),
        .x2         (x2_q),
        .y2         (y2_q),
        .bbox_min_x (bbox_min_x_q),
        .bbox_max_x (bbox_max_x_q),
        .bbox_min_y (bbox_min_y_q),
        .bbox_max_y (bbox_max_y_q),
        .area2      (area2_q),
        .reject     (reject_q),
        .busy       (raster_busy),
        .span_valid (span_valid),
        .span_ready (span_ready),
        .span_data  (span_data),
        .m_axi_arid    (m_axi_arid),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_arlock  (m_axi_arlock),
        .m_axi_arcache (m_axi_arcache),
        .m_axi_arprot  (m_axi_arprot),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rid     (m_axi_rid),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rlast   (m_axi_rlast),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready)
    );
endmodule
