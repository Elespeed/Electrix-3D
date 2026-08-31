`include "../../config.h"

module lcd_refresh_regs (
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

    input  logic        refresh_busy,
    input  logic        refresh_done_evt,
    input  logic        axi_error_evt,
    input  logic        spi_error_evt,
    input  logic        cfg_error_evt,

    output logic        lcd_enable,
    output logic [31:0] front_fb_base,
    output logic [31:0] stride,
    output logic [15:0] width,
    output logic [15:0] height,
    output logic [1:0]  pixel_format,
    output logic [15:0] dirty_x,
    output logic [15:0] dirty_y,
    output logic [15:0] dirty_w,
    output logic [15:0] dirty_h,
    output logic [15:0] spi_clk_div,
    output logic        full_start_pulse,
    output logic        partial_start_pulse,
    output logic        abort_pulse,

    input  logic        aclk,
    input  logic        aresetn
);

    localparam logic [7:0] REG_CTRL       = 8'h00;
    localparam logic [7:0] REG_STATUS     = 8'h04;
    localparam logic [7:0] REG_FB_BASE    = 8'h08;
    localparam logic [7:0] REG_STRIDE     = 8'h0c;
    localparam logic [7:0] REG_SIZE       = 8'h10;
    localparam logic [7:0] REG_PIXEL_FMT  = 8'h14;
    localparam logic [7:0] REG_REFRESH    = 8'h18;
    localparam logic [7:0] REG_DIRTY_XY   = 8'h1c;
    localparam logic [7:0] REG_DIRTY_WH   = 8'h20;
    localparam logic [7:0] REG_SPI_CLKDIV = 8'h24;
    localparam logic [7:0] REG_IRQ_CLEAR  = 8'h28;

    logic busy;
    logic write_phase;
    logic req_is_read;
    logic [4:0]  req_id;
    logic [31:0] req_addr;

    logic status_done;
    logic status_axi_error;
    logic status_spi_error;
    logic status_cfg_error;

    wire ar_enter = s_arvalid & s_arready;
    wire aw_enter = s_awvalid & s_awready;
    wire w_enter  = s_wvalid  & s_wready  & s_wlast;
    wire r_retire = s_rvalid  & s_rready  & s_rlast;
    wire b_retire = s_bvalid  & s_bready;

    assign s_arready = ~busy & (~req_is_read | ~s_awvalid);
    assign s_awready = ~busy & ( req_is_read | ~s_arvalid);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            busy <= 1'b0;
        end else begin
            if (ar_enter | aw_enter) begin
                busy <= 1'b1;
            end else if (r_retire | b_retire) begin
                busy <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            req_is_read <= 1'b0;
            req_id      <= 5'd0;
            req_addr    <= 32'd0;
        end else if (ar_enter | aw_enter) begin
            req_is_read <= ar_enter;
            req_id      <= ar_enter ? s_arid   : s_awid;
            req_addr    <= ar_enter ? s_araddr : s_awaddr;
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            write_phase <= 1'b0;
            s_wready    <= 1'b0;
        end else begin
            if (aw_enter) begin
                write_phase <= 1'b1;
                s_wready    <= 1'b1;
            end else if (ar_enter) begin
                write_phase <= 1'b0;
                s_wready    <= 1'b0;
            end else if (w_enter) begin
                s_wready    <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_rvalid <= 1'b0;
            s_rlast  <= 1'b0;
            s_rdata  <= 32'd0;
        end else begin
            if (busy & ~write_phase & ~r_retire) begin
                s_rvalid <= 1'b1;
                s_rlast  <= 1'b1;
                case (req_addr[7:0])
                    REG_CTRL:       s_rdata <= {31'd0, lcd_enable};
                    REG_STATUS:     s_rdata <= {27'd0, status_cfg_error, status_axi_error, status_spi_error, status_done, refresh_busy};
                    REG_FB_BASE:    s_rdata <= front_fb_base;
                    REG_STRIDE:     s_rdata <= stride;
                    REG_SIZE:       s_rdata <= {height, width};
                    REG_PIXEL_FMT:  s_rdata <= {30'd0, pixel_format};
                    REG_REFRESH:    s_rdata <= {31'd0, refresh_busy};
                    REG_DIRTY_XY:   s_rdata <= {dirty_y, dirty_x};
                    REG_DIRTY_WH:   s_rdata <= {dirty_h, dirty_w};
                    REG_SPI_CLKDIV: s_rdata <= {16'd0, spi_clk_div};
                    default:        s_rdata <= 32'd0;
                endcase
            end else if (r_retire) begin
                s_rvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_bvalid <= 1'b0;
        end else begin
            if (w_enter) begin
                s_bvalid <= 1'b1;
            end else if (b_retire) begin
                s_bvalid <= 1'b0;
            end
        end
    end

    assign s_rid   = req_id;
    assign s_bid   = req_id;
    assign s_rresp = 2'b00;
    assign s_bresp = 2'b00;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            lcd_enable          <= 1'b0;
            front_fb_base       <= `GDU_DEFAULT_FB_BASE;
            stride              <= `GDU_DEFAULT_STRIDE;
            width               <= `GDU_DEFAULT_WIDTH;
            height              <= `GDU_DEFAULT_HEIGHT;
            pixel_format        <= `GDU_DEFAULT_PIXEL_FMT;
            dirty_x             <= 16'd0;
            dirty_y             <= 16'd0;
            dirty_w             <= `GDU_DEFAULT_WIDTH;
            dirty_h             <= `GDU_DEFAULT_HEIGHT;
            spi_clk_div         <= 16'd0;
            status_done         <= 1'b0;
            status_axi_error    <= 1'b0;
            status_spi_error    <= 1'b0;
            status_cfg_error    <= 1'b0;
            full_start_pulse    <= 1'b0;
            partial_start_pulse <= 1'b0;
            abort_pulse         <= 1'b0;
        end else begin
            full_start_pulse    <= 1'b0;
            partial_start_pulse <= 1'b0;
            abort_pulse         <= 1'b0;

            if (refresh_done_evt) status_done <= 1'b1;
            if (axi_error_evt)    status_axi_error <= 1'b1;
            if (spi_error_evt)    status_spi_error <= 1'b1;
            if (cfg_error_evt)    status_cfg_error <= 1'b1;

            if (w_enter) begin
                case (req_addr[7:0])
                    REG_CTRL: begin
                        lcd_enable <= s_wdata[0];
                        abort_pulse <= s_wdata[4];
                        if (!s_wdata[0]) begin
                            status_done      <= 1'b0;
                            status_axi_error <= 1'b0;
                            status_spi_error <= 1'b0;
                            status_cfg_error <= 1'b0;
                        end
                    end
                    REG_FB_BASE:    front_fb_base <= s_wdata;
                    REG_STRIDE:     stride <= s_wdata;
                    REG_SIZE: begin
                        width  <= s_wdata[15:0];
                        height <= s_wdata[31:16];
                    end
                    REG_PIXEL_FMT:  pixel_format <= s_wdata[1:0];
                    REG_REFRESH: begin
                        if (s_wdata[0]) begin
                            full_start_pulse <= 1'b1;
                            status_done      <= 1'b0;
                            status_axi_error <= 1'b0;
                            status_spi_error <= 1'b0;
                            status_cfg_error <= 1'b0;
                        end
                        if (s_wdata[1]) begin
                            partial_start_pulse <= 1'b1;
                            status_done      <= 1'b0;
                            status_axi_error <= 1'b0;
                            status_spi_error <= 1'b0;
                            status_cfg_error <= 1'b0;
                        end
                    end
                    REG_DIRTY_XY: begin
                        dirty_x <= s_wdata[15:0];
                        dirty_y <= s_wdata[31:16];
                    end
                    REG_DIRTY_WH: begin
                        dirty_w <= s_wdata[15:0];
                        dirty_h <= s_wdata[31:16];
                    end
                    REG_SPI_CLKDIV: spi_clk_div <= s_wdata[15:0];
                    REG_IRQ_CLEAR: begin
                        if (s_wdata[0]) status_done <= 1'b0;
                        if (s_wdata[1]) status_spi_error <= 1'b0;
                        if (s_wdata[2]) status_axi_error <= 1'b0;
                        if (s_wdata[3]) status_cfg_error <= 1'b0;
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    wire [7:0] _unused_axi = {s_awlen[0], s_awsize[0], s_awburst[0], s_awlock,
                              s_awcache[0], s_awprot[0], s_arlen[0], s_arprot[0]};
    wire [3:0] _unused_wstrb = s_wstrb;
    wire [3:0] _unused_ar = {s_arsize[0], s_arburst[0], s_arlock, s_arcache[0]};

endmodule
