`include "../../config.h"

module lcd_refresh_top #(
    parameter logic [31:0] ILI9341_RESET_DELAY_CYCLES     = 32'd1,
    parameter logic [31:0] ILI9341_SLEEP_OUT_DELAY_CYCLES = 32'd1,
    parameter logic [7:0]  ILI9341_MADCTL                 = 8'h48
) (
    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_awaddr,
    input  logic [4:0]  s_awid,
    input  logic [7:0]  s_awlen,
    input  logic [2:0]  s_awsize,
    input  logic [1:0]  s_awburst,
    input  logic        s_awlock,
    input  logic [3:0]  s_awcache,
    input  logic [2:0]  s_awprot,
    input  logic        s_wvalid,
    output logic        s_wready,
    input  logic [31:0] s_wdata,
    input  logic [3:0]  s_wstrb,
    input  logic        s_wlast,
    output logic        s_bvalid,
    input  logic        s_bready,
    output logic [4:0]  s_bid,
    output logic [1:0]  s_bresp,
    input  logic        s_arvalid,
    output logic        s_arready,
    input  logic [31:0] s_araddr,
    input  logic [4:0]  s_arid,
    input  logic [7:0]  s_arlen,
    input  logic [2:0]  s_arsize,
    input  logic [1:0]  s_arburst,
    input  logic        s_arlock,
    input  logic [3:0]  s_arcache,
    input  logic [2:0]  s_arprot,
    output logic        s_rvalid,
    input  logic        s_rready,
    output logic [31:0] s_rdata,
    output logic [4:0]  s_rid,
    output logic [1:0]  s_rresp,
    output logic        s_rlast,

    output logic [4:0]   m_axi_arid,
    output logic [31:0]  m_axi_araddr,
    output logic [7:0]   m_axi_arlen,
    output logic [2:0]   m_axi_arsize,
    output logic [1:0]   m_axi_arburst,
    output logic         m_axi_arlock,
    output logic [3:0]   m_axi_arcache,
    output logic [2:0]   m_axi_arprot,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,
    input  logic [4:0]   m_axi_rid,
    input  logic [127:0] m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rlast,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,

    input  logic        ddr_init_calib_complete,
    input  logic        tft_sdo,
    output logic        tft_scl,
    output logic        tft_sdi,
    output logic        tft_cs,
    output logic        tft_rs,

    output logic        refresh_busy,
    output logic        refresh_done_evt,
    output logic        axi_error_evt,
    output logic        spi_error_evt,
    output logic        cfg_error_evt,

    input  logic        aclk,
    input  logic        aresetn
);

    logic        lcd_enable;
    logic [31:0] front_fb_base;
    logic [31:0] stride;
    logic [15:0] width;
    logic [15:0] height;
    logic [1:0]  pixel_format;
    logic [15:0] dirty_x;
    logic [15:0] dirty_y;
    logic [15:0] dirty_w;
    logic [15:0] dirty_h;
    logic [15:0] spi_clk_div;
    logic        full_start_pulse;
    logic        partial_start_pulse;
    logic        abort_pulse;

    logic        reader_start;
    logic        tx_start;
    logic [15:0] active_x;
    logic [15:0] active_y;
    logic [15:0] active_w;
    logic [15:0] active_h;
    logic        reader_busy;
    logic        reader_done;
    logic        reader_axi_error;
    logic        pixel_valid;
    logic        pixel_ready;
    logic [15:0] pixel_data;
    logic        tx_busy;
    logic        tx_done;
    logic        tx_spi_error;
    logic [31:0] tx_pixel_count;
    logic [31:0] tx_byte_count;

    logic        start_req;
    logic        partial_req;
    logic        valid_rect;
    logic        start_ok;

    assign start_req = full_start_pulse | partial_start_pulse;
    assign partial_req = partial_start_pulse;
    assign valid_rect = lcd_enable &&
                        ddr_init_calib_complete &&
                        (width != 16'd0) &&
                        (height != 16'd0) &&
                        (stride != 32'd0) &&
                        (pixel_format == `GDU_DEFAULT_PIXEL_FMT) &&
                        (!partial_req || ((dirty_w != 16'd0) &&
                                          (dirty_h != 16'd0) &&
                                          (dirty_x < width) &&
                                          (dirty_y < height) &&
                                          ((dirty_x + dirty_w) <= width) &&
                                          ((dirty_y + dirty_h) <= height)));
    assign start_ok = start_req && !refresh_busy && valid_rect;
    assign cfg_error_evt = start_req && !start_ok;
    assign refresh_busy = reader_busy | tx_busy;
    assign refresh_done_evt = tx_done;
    assign axi_error_evt = reader_axi_error;
    assign spi_error_evt = tx_spi_error;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            reader_start <= 1'b0;
            tx_start <= 1'b0;
            active_x <= 16'd0;
            active_y <= 16'd0;
            active_w <= 16'd0;
            active_h <= 16'd0;
        end else begin
            reader_start <= 1'b0;
            tx_start <= 1'b0;
            if (start_ok) begin
                active_x <= partial_req ? dirty_x : 16'd0;
                active_y <= partial_req ? dirty_y : 16'd0;
                active_w <= partial_req ? dirty_w : width;
                active_h <= partial_req ? dirty_h : height;
                reader_start <= 1'b1;
                tx_start <= 1'b1;
            end
        end
    end

    lcd_refresh_regs u_lcd_refresh_regs (
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awaddr (s_awaddr),
        .s_awid   (s_awid),
        .s_awlen  (s_awlen),
        .s_awsize (s_awsize),
        .s_awburst(s_awburst),
        .s_awlock (s_awlock),
        .s_awcache(s_awcache),
        .s_awprot (s_awprot),
        .s_wvalid (s_wvalid),
        .s_wready (s_wready),
        .s_wdata  (s_wdata),
        .s_wstrb  (s_wstrb),
        .s_wlast  (s_wlast),
        .s_bvalid (s_bvalid),
        .s_bready (s_bready),
        .s_bid    (s_bid),
        .s_bresp  (s_bresp),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_araddr (s_araddr),
        .s_arid   (s_arid),
        .s_arlen  (s_arlen),
        .s_arsize (s_arsize),
        .s_arburst(s_arburst),
        .s_arlock (s_arlock),
        .s_arcache(s_arcache),
        .s_arprot (s_arprot),
        .s_rvalid (s_rvalid),
        .s_rready (s_rready),
        .s_rdata  (s_rdata),
        .s_rid    (s_rid),
        .s_rresp  (s_rresp),
        .s_rlast  (s_rlast),
        .refresh_busy(refresh_busy),
        .refresh_done_evt(refresh_done_evt),
        .axi_error_evt(axi_error_evt),
        .spi_error_evt(spi_error_evt),
        .cfg_error_evt(cfg_error_evt),
        .lcd_enable(lcd_enable),
        .front_fb_base(front_fb_base),
        .stride(stride),
        .width(width),
        .height(height),
        .pixel_format(pixel_format),
        .dirty_x(dirty_x),
        .dirty_y(dirty_y),
        .dirty_w(dirty_w),
        .dirty_h(dirty_h),
        .spi_clk_div(spi_clk_div),
        .full_start_pulse(full_start_pulse),
        .partial_start_pulse(partial_start_pulse),
        .abort_pulse(abort_pulse),
        .aclk(aclk),
        .aresetn(aresetn)
    );

    lcd_axi_reader u_lcd_axi_reader (
        .clk(aclk),
        .rstn(aresetn & lcd_enable),
        .start(reader_start),
        .abort(abort_pulse),
        .fb_base(front_fb_base),
        .stride(stride),
        .rect_x(active_x),
        .rect_y(active_y),
        .rect_w(active_w),
        .rect_h(active_h),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .pixel_data(pixel_data),
        .busy(reader_busy),
        .done(reader_done),
        .axi_error(reader_axi_error),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    spi_lcd_tx #(
        .INIT_RESET_DELAY_CYCLES    (ILI9341_RESET_DELAY_CYCLES),
        .INIT_SLEEP_OUT_DELAY_CYCLES(ILI9341_SLEEP_OUT_DELAY_CYCLES),
        .INIT_MADCTL                (ILI9341_MADCTL)
    ) u_spi_lcd_tx (
        .clk(aclk),
        // Initialize once after SoC reset.  Gating this reset with lcd_enable
        // would restart the 125 ms ILI9341 sequence on every enable.
        .rstn(aresetn),
        .start(tx_start),
        .abort(abort_pulse),
        .spi_clk_div(spi_clk_div),
        .win_x(active_x),
        .win_y(active_y),
        .win_w(active_w),
        .win_h(active_h),
        .pixel_data(pixel_data),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .busy(tx_busy),
        .done(tx_done),
        .spi_error(tx_spi_error),
        .pixel_count(tx_pixel_count),
        .byte_count(tx_byte_count),
        .tft_scl(tft_scl),
        .tft_sdi(tft_sdi),
        .tft_cs(tft_cs),
        .tft_rs(tft_rs)
    );

    wire _unused = tft_sdo ^ reader_done ^ tx_pixel_count[0] ^ tx_byte_count[0];

endmodule
