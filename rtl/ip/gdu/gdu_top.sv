`include "../../config.h"

module gdu_top #(
    parameter int H_ACTIVE = `GDU_TIMING_H_ACTIVE,
    parameter int H_FRONT  = `GDU_TIMING_H_FRONT,
    parameter int H_SYNC   = `GDU_TIMING_H_SYNC,
    parameter int H_BACK   = `GDU_TIMING_H_BACK,
    parameter int H_TOTAL  = `GDU_TIMING_H_TOTAL,
    parameter int V_ACTIVE = `GDU_TIMING_V_ACTIVE,
    parameter int V_FRONT  = `GDU_TIMING_V_FRONT,
    parameter int V_SYNC   = `GDU_TIMING_V_SYNC,
    parameter int V_BACK   = `GDU_TIMING_V_BACK,
    parameter int V_TOTAL  = `GDU_TIMING_V_TOTAL,
    parameter logic [31:0] DEFAULT_FB_BASE = `GDU_DEFAULT_FB_BASE,
    parameter logic [31:0] DEFAULT_STRIDE = `GDU_DEFAULT_STRIDE,
    parameter logic [15:0] DEFAULT_WIDTH = `GDU_DEFAULT_WIDTH,
    parameter logic [15:0] DEFAULT_HEIGHT = `GDU_DEFAULT_HEIGHT,
    parameter logic [1:0]  DEFAULT_PIXEL_FORMAT = `GDU_DEFAULT_PIXEL_FMT,
    parameter int unsigned FIFO_DEPTH = `GDU_FIFO_DEPTH,
    parameter logic [11:0] FIFO_CRITICAL_WATER = 12'd128,
    parameter logic [11:0] FIFO_LOW_WATER = 12'd512,
    parameter int unsigned STARTUP_PREFILL_LINES = `GDU_STARTUP_PREFILL_LINES,
    parameter int unsigned READER_FIFO_HIGH_WATER = 1800,
    parameter int unsigned READER_MAX_SAFE_BURST = 32,
    // Optional nearest-neighbour 2x expansion before the normal scanout FIFO.
    parameter bit SCALE_2X = 1'b0
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

    output logic [4:0]  m_axi_arid,
    output logic [31:0] m_axi_araddr,
    output logic [7:0]  m_axi_arlen,
    output logic [2:0]  m_axi_arsize,
    output logic [1:0]  m_axi_arburst,
    output logic        m_axi_arlock,
    output logic [3:0]  m_axi_arcache,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [4:0]  m_axi_rid,
    input  logic [127:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rlast,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    input  logic        ddr_init_calib_complete,

    output logic [4:0]  video_red,
    output logic [5:0]  video_green,
    output logic [4:0]  video_blue,
    output logic        video_hsync,
    output logic        video_vsync,
    output logic        video_de,
    output logic        video_clk,

    output logic [15:0] lcd_rgb,
    output logic        lcd_hsync,
    output logic        lcd_vsync,
    output logic        lcd_de,
    output logic        lcd_pclk,
    output logic        lcd_rst,
    output logic        lcd_bl_ctr,
    output logic        fifo_underflow_evt,
    output logic        axi_error_evt,
    output logic        gdu_fifo_critical,
    output logic        gdu_fifo_low,

    // Phase-4: ddr_axi_arbiter_2m1s cumulative counters, routed in from the
    // parent (graph_system / soc_top_lv3_board) so the GDU perf MMIO window can
    // expose system-bus stats.  fb_axi_reader's own counters are internal.
    input  logic [31:0] arb_gru_grant_count,
    input  logic [31:0] arb_gdu_grant_count,
    input  logic [31:0] arb_gru_wait_cycle_count,
    input  logic [31:0] arb_gdu_wait_cycle_count,
    input  logic [31:0] arb_gru_max_wait_cycles,
    input  logic [31:0] arb_gdu_max_wait_cycles,
    input  logic [31:0] arb_qos_override_count,
    input  logic [31:0] arb_critical_override_count,
    input  logic [31:0] arb_starvation_relief_count,

    input  logic        aclk,
    input  logic        aresetn
);
    localparam int unsigned FIFO_DEPTH_CLAMPED =
        (FIFO_DEPTH > 12'hfff) ? 12'hfff : FIFO_DEPTH;

    typedef enum logic [1:0] {
        GDU_STATE_IDLE    = 2'd0,
        GDU_STATE_PREFILL = 2'd1,
        GDU_STATE_RUN     = 2'd2
    } gdu_state_t;

    logic        gdu_enable;
    logic [31:0] fb_base;
    logic [31:0] fb_base_active;
    logic [31:0] stride;
    logic [15:0] width;
    logic [15:0] height;
    logic [1:0]  pixel_format;
    logic        swap_pending;

    logic [11:0] scan_x;
    logic [11:0] scan_y;
    logic        timing_hsync;
    logic        timing_vsync;
    logic        timing_de;
    logic        frame_start;
    logic        frame_restart_next;
    logic        line_start;
    logic        vblank_enter;

    logic        fifo_wr_en;
    logic [15:0] fifo_wr_data;
    logic        fifo_rd_en;
    logic [15:0] fifo_rd_data;
    logic        fifo_full;
    logic        fifo_empty;
    logic [11:0] fifo_level;

    logic [15:0] pixel_rgb565;
    logic        gdu_pixel_de;
    logic        gdu_pixel_de_d;
    logic        gdu_pixel_de_out;
    logic        timing_hsync_d;
    logic        timing_vsync_d;
    logic        reader_enable;
    logic        scan_run;
    logic        timing_run;
    logic        session_rstn;
    logic        startup_ready;
    logic        first_frame_started;
    logic        first_frame_done;
    logic        reload_pulse;
    logic        swap_done_evt;
    logic        present_pending;
    logic        present_started;
    logic        present_done_evt;
    logic        underflow_suppress;
    logic        reload_frame_seen;
    logic        prefill_fifo_empty_seen;
    logic        prefill_ready_seen;
    logic [11:0] width_12b;
    logic [31:0] startup_threshold;
    logic [11:0] min_fifo_level_dbg;
    gdu_state_t  gdu_state;

    // Phase-4 fb_axi_reader cumulative perf counters (internal nets).
    logic [31:0] rd_ar_txn_count;
    logic [31:0] rd_beat_count;
    logic [31:0] rd_wait_cycle_count;


    assign session_rstn = aresetn & gdu_enable;
    assign scan_run = (gdu_state == GDU_STATE_RUN);
    assign timing_run = gdu_enable & ddr_init_calib_complete & (first_frame_started | scan_run);
    assign reader_enable = (gdu_state != GDU_STATE_IDLE) & ddr_init_calib_complete;
    assign width_12b = (width[15:12] != 4'd0) ? 12'hfff : width[11:0];
    assign startup_threshold = STARTUP_PREFILL_LINES * width_12b;
    assign startup_ready = (width_12b != 12'd0) &&
                           (fifo_level >= ((startup_threshold < FIFO_DEPTH_CLAMPED) ?
                                           startup_threshold[11:0] : FIFO_DEPTH_CLAMPED[11:0]));
    assign gdu_pixel_de = timing_de & scan_run;
    assign gdu_pixel_de_out = gdu_pixel_de_d & ~reload_pulse;
    assign fifo_rd_en = gdu_pixel_de & ~fifo_empty;
    assign gdu_fifo_critical = (fifo_level < FIFO_CRITICAL_WATER);
    assign gdu_fifo_low = (fifo_level < FIFO_LOW_WATER);
    assign frame_restart_next = timing_run &&
                                (scan_x == (H_TOTAL - 1)) &&
                                (scan_y == (V_TOTAL - 1));

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            gdu_state <= GDU_STATE_IDLE;
            first_frame_started <= 1'b0;
            first_frame_done <= 1'b0;
            reload_pulse <= 1'b0;
            swap_done_evt <= 1'b0;
            present_pending <= 1'b0;
            present_started <= 1'b0;
            present_done_evt <= 1'b0;
            fb_base_active <= DEFAULT_FB_BASE;
            underflow_suppress <= 1'b0;
            reload_frame_seen <= 1'b0;
            prefill_fifo_empty_seen <= 1'b0;
            prefill_ready_seen <= 1'b0;
            min_fifo_level_dbg <= FIFO_DEPTH_CLAMPED[11:0];
        end else if (!gdu_enable) begin
            gdu_state <= GDU_STATE_IDLE;
            first_frame_started <= 1'b0;
            first_frame_done <= 1'b0;
            reload_pulse <= 1'b0;
            swap_done_evt <= 1'b0;
            present_pending <= 1'b0;
            present_started <= 1'b0;
            present_done_evt <= 1'b0;
            fb_base_active <= fb_base;
            underflow_suppress <= 1'b0;
            reload_frame_seen <= 1'b0;
            prefill_fifo_empty_seen <= 1'b0;
            prefill_ready_seen <= 1'b0;
            min_fifo_level_dbg <= fifo_level;
        end else begin
            reload_pulse <= 1'b0;
            swap_done_evt <= 1'b0;
            present_done_evt <= 1'b0;
            case (gdu_state)
                GDU_STATE_IDLE: begin
                    gdu_state <= GDU_STATE_PREFILL;
                    first_frame_started <= 1'b0;
                    first_frame_done <= 1'b0;
                    fb_base_active <= fb_base;
                    present_started <= 1'b0;
                    prefill_fifo_empty_seen <= 1'b0;
                    prefill_ready_seen <= 1'b0;
                    min_fifo_level_dbg <= fifo_level;
                end
                GDU_STATE_PREFILL: begin
                    min_fifo_level_dbg <= fifo_level;
                    if (!prefill_fifo_empty_seen) begin
                        if (fifo_level == 12'd0) begin
                            prefill_fifo_empty_seen <= 1'b1;
                        end
                    end else if (!first_frame_started) begin
                        if (reader_enable && startup_ready) begin
                            gdu_state <= GDU_STATE_RUN;
                            first_frame_started <= 1'b1;
                            prefill_ready_seen <= 1'b0;
                        end
                    end else begin
                        if (reader_enable && startup_ready) begin
                            prefill_ready_seen <= 1'b1;
                        end
                        if (prefill_ready_seen && frame_restart_next) begin
                            gdu_state <= GDU_STATE_RUN;
                            prefill_ready_seen <= 1'b0;
                        end
                    end
                end
                GDU_STATE_RUN: begin
                    if (fifo_level < min_fifo_level_dbg) begin
                        min_fifo_level_dbg <= fifo_level;
                    end
                    if (swap_pending && vblank_enter) begin
                        fb_base_active <= fb_base;
                        reload_pulse <= 1'b1;
                        swap_done_evt <= 1'b1;
                        present_pending <= 1'b1;
                        present_started <= 1'b0;
                        gdu_state <= GDU_STATE_PREFILL;
                        underflow_suppress <= 1'b1;
                        reload_frame_seen <= 1'b0;
                        prefill_fifo_empty_seen <= 1'b0;
                        prefill_ready_seen <= 1'b0;
                    end
                    if (frame_start) begin
                        if (underflow_suppress) begin
                            if (!reload_frame_seen) begin
                                reload_frame_seen <= 1'b1;
                            end else begin
                                underflow_suppress <= 1'b0;
                                reload_frame_seen <= 1'b0;
                            end
                        end
                        if (present_pending) begin
                            if (!present_started) begin
                                present_started <= 1'b1;
                            end else begin
                                present_done_evt <= 1'b1;
                                present_pending <= 1'b0;
                                present_started <= 1'b0;
                            end
                        end
                        if (!first_frame_done) begin
                            present_done_evt <= 1'b1;
                            first_frame_done <= 1'b1;
                        end
                    end
                end
                default: begin
                    gdu_state <= GDU_STATE_IDLE;
                    first_frame_started <= 1'b0;
                    first_frame_done <= 1'b0;
                    present_started <= 1'b0;
                    prefill_fifo_empty_seen <= 1'b0;
                    prefill_ready_seen <= 1'b0;
                end
            endcase
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            pixel_rgb565 <= 16'd0;
        end else if (!gdu_enable || reload_pulse) begin
            pixel_rgb565 <= 16'd0;
        end else begin
            if (fifo_rd_en) begin
                pixel_rgb565 <= fifo_rd_data;
            end else if (gdu_pixel_de && fifo_empty) begin
                pixel_rgb565 <= 16'd0;
            end else if (~gdu_pixel_de) begin
                pixel_rgb565 <= 16'd0;
            end
        end
    end

    // Delay DE and sync signals to align with pixel_rgb565 register
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            gdu_pixel_de_d <= 1'b0;
            timing_hsync_d <= 1'b0;
            timing_vsync_d <= 1'b0;
        end else if (!timing_run) begin
            gdu_pixel_de_d <= 1'b0;
            timing_hsync_d <= 1'b0;
            timing_vsync_d <= 1'b0;
        end else begin
            gdu_pixel_de_d <= gdu_pixel_de;
            timing_hsync_d <= timing_hsync;
            timing_vsync_d <= timing_vsync;
        end
    end

    assign fifo_underflow_evt = gdu_pixel_de & fifo_empty & ~reload_pulse & ~underflow_suppress;

    gdu_regs #(
        .DEFAULT_FB_BASE     (DEFAULT_FB_BASE),
        .DEFAULT_STRIDE      (DEFAULT_STRIDE),
        .DEFAULT_WIDTH       (DEFAULT_WIDTH),
        .DEFAULT_HEIGHT      (DEFAULT_HEIGHT),
        .DEFAULT_PIXEL_FORMAT(DEFAULT_PIXEL_FORMAT)
    ) u_gdu_regs (
        .s_awvalid       (s_awvalid),
        .s_awready       (s_awready),
        .s_awaddr        (s_awaddr),
        .s_awid          (s_awid),
        .s_awlen         (s_awlen),
        .s_awsize        (s_awsize),
        .s_awburst       (s_awburst),
        .s_awlock        (s_awlock),
        .s_awcache       (s_awcache),
        .s_awprot        (s_awprot),
        .s_wvalid        (s_wvalid),
        .s_wready        (s_wready),
        .s_wdata         (s_wdata),
        .s_wstrb         (s_wstrb),
        .s_wlast         (s_wlast),
        .s_bvalid        (s_bvalid),
        .s_bready        (s_bready),
        .s_bid           (s_bid),
        .s_bresp         (s_bresp),
        .s_arvalid       (s_arvalid),
        .s_arready       (s_arready),
        .s_araddr        (s_araddr),
        .s_arid          (s_arid),
        .s_arlen         (s_arlen),
        .s_arsize        (s_arsize),
        .s_arburst       (s_arburst),
        .s_arlock        (s_arlock),
        .s_arcache       (s_arcache),
        .s_arprot        (s_arprot),
        .s_rvalid        (s_rvalid),
        .s_rready        (s_rready),
        .s_rdata         (s_rdata),
        .s_rid           (s_rid),
        .s_rresp         (s_rresp),
        .s_rlast         (s_rlast),
        .fifo_underflow  (fifo_underflow_evt),
        .present_done    (present_done_evt),
        .axi_error       (axi_error_evt),
        .swap_done       (swap_done_evt),
        .gdu_enable      (gdu_enable),
        .fb_base         (fb_base),
        .stride          (stride),
        .width           (width),
        .height          (height),
        .pixel_format    (pixel_format),
        .swap_pending    (swap_pending),
        .perf_rd_ar_txn              (rd_ar_txn_count),
        .perf_rd_beat                (rd_beat_count),
        .perf_rd_wait                (rd_wait_cycle_count),
        .perf_arb_gru_grant          (arb_gru_grant_count),
        .perf_arb_gdu_grant          (arb_gdu_grant_count),
        .perf_arb_gru_wait           (arb_gru_wait_cycle_count),
        .perf_arb_gdu_wait           (arb_gdu_wait_cycle_count),
        .perf_arb_gru_max_wait       (arb_gru_max_wait_cycles),
        .perf_arb_gdu_max_wait       (arb_gdu_max_wait_cycles),
        .perf_arb_qos_override       (arb_qos_override_count),
        .perf_arb_critical_override  (arb_critical_override_count),
        .perf_arb_starvation_relief  (arb_starvation_relief_count),
        .aclk            (aclk),
        .aresetn         (aresetn)
    );

    // Optimized for faster simulation: 80×60 resolution
    // Original parameters: 800×600 @ ~5 hours/frame
    // Optimized parameters: 80×60 @ ~3 minutes/frame (100x faster)
    display_timing_gen #(
        .H_ACTIVE(H_ACTIVE),
        .H_FRONT (H_FRONT),
        .H_SYNC  (H_SYNC),
        .H_BACK  (H_BACK),
        .H_TOTAL (H_TOTAL),
        .V_ACTIVE(V_ACTIVE),
        .V_FRONT (V_FRONT),
        .V_SYNC  (V_SYNC),
        .V_BACK  (V_BACK),
        .V_TOTAL (V_TOTAL)
    ) u_display_timing_gen (
        .clk         (aclk),
        .rstn        (aresetn),
        .run         (timing_run),
        .x           (scan_x),
        .y           (scan_y),
        .hsync       (timing_hsync),
        .vsync       (timing_vsync),
        .de          (timing_de),
        .frame_start (frame_start),
        .line_start  (line_start),
        .vblank_enter(vblank_enter)
    );

    pixel_fifo #(
        .DEPTH(FIFO_DEPTH)
    ) u_pixel_fifo (
        .clk     (aclk),
        .rstn    (session_rstn),
        .clr     (reload_pulse),
        .wr_en   (fifo_wr_en),
        .wr_data (fifo_wr_data),
        .rd_en   (fifo_rd_en),
        .rd_data (fifo_rd_data),
        .full    (fifo_full),
        .empty   (fifo_empty),
        .level   (fifo_level)
    );

    fb_axi_reader #(
        .SCALE_2X      (SCALE_2X),
        .FIFO_HIGH_WATER(READER_FIFO_HIGH_WATER),
        .MAX_SAFE_BURST(READER_MAX_SAFE_BURST)
    ) u_fb_axi_reader (
        .clk           (aclk),
        .rstn          (session_rstn),
        .enable        (reader_enable),
        .reload        (reload_pulse),
        .fb_base       (fb_base_active),
        .stride        (stride),
        .width         (width),
        .height        (height),
        .fifo_level    (fifo_level),
        .fifo_wr_en    (fifo_wr_en),
        .fifo_wr_data  (fifo_wr_data),
        .axi_error     (axi_error_evt),
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
        .m_axi_rready  (m_axi_rready),
        .rd_ar_txn_count     (rd_ar_txn_count),
        .rd_beat_count       (rd_beat_count),
        .rd_wait_cycle_count (rd_wait_cycle_count)
    );

    dvi_adapter u_dvi_adapter (
        .clk         (aclk),
        .pixel_rgb565(pixel_rgb565),
        .de          (gdu_pixel_de_out),    // Mask cutover cycle during swap reload
        .hsync       (timing_hsync_d),      // Use delayed HSYNC
        .vsync       (timing_vsync_d),      // Use delayed VSYNC
        .video_red   (video_red),
        .video_green (video_green),
        .video_blue  (video_blue),
        .video_hsync (video_hsync),
        .video_vsync (video_vsync),
        .video_de    (video_de),
        .video_clk   (video_clk)
    );

    lcd_adapter u_lcd_adapter (
        .clk         (aclk),
        .resetn      (aresetn),
        .pixel_rgb565(pixel_rgb565),
        .de          (gdu_pixel_de_out),
        .hsync       (timing_hsync_d),
        .vsync       (timing_vsync_d),
        .lcd_rgb     (lcd_rgb),
        .lcd_hsync   (lcd_hsync),
        .lcd_vsync   (lcd_vsync),
        .lcd_de      (lcd_de),
        .lcd_pclk    (lcd_pclk),
        .lcd_rst     (lcd_rst),
        .lcd_bl_ctr  (lcd_bl_ctr)
    );

endmodule
