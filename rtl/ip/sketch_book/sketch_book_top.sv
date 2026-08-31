module sketch_book_top #(
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
    parameter bit ENABLE_GOURAUD = 1'b0,
    parameter int CMD_FIFO_DEPTH = 16,
    parameter int ASSET_WORDS = 2048,
    parameter string ASSET_INIT_FILE = ""
) (
    input  logic clk,
    input  logic resetn,
    input  logic mmio_valid,
    input  logic mmio_we,
    input  logic [31:0] mmio_addr,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata,
    output logic mmio_ready,
    output logic dvi_clk,
    output logic dvi_hs,
    output logic dvi_vs,
    output logic dvi_de,
    output logic [7:0] dvi_d,
    output logic irq_done,
    output logic err_active_write
);
    localparam int ADDR_W = $clog2((SRC_W * SRC_H) / 8);
    localparam logic [11:0] REG_CTRL          = 12'h000;
    localparam logic [11:0] REG_STATUS        = 12'h004;
    localparam logic [11:0] REG_CMD0          = 12'h008;
    localparam logic [11:0] REG_CMD1          = 12'h00c;
    localparam logic [11:0] REG_CMD2          = 12'h010;
    localparam logic [11:0] REG_CMD3          = 12'h014;
    localparam logic [11:0] REG_CMD_PUSH      = 12'h018;
    localparam logic [11:0] REG_CMD_LEVEL     = 12'h01c;
    localparam logic [11:0] REG_FRAME_COUNTER = 12'h020;
    localparam logic [11:0] REG_PAGE_STATUS   = 12'h024;
    localparam logic [11:0] REG_ERR_STATUS    = 12'h028;
    localparam logic [11:0] REG_CMD4          = 12'h02c;

    logic [31:0] cmd0, cmd1, cmd2, cmd3, cmd4;
    logic cmd_push_strobe, soft_reset_strobe;
    logic display_enable;
    logic cmd_push_ready, cmd_full, gru_busy, gru_idle, frame_closed, present_req, gru_error;
    logic [$clog2(CMD_FIFO_DEPTH + 1)-1:0] cmd_level;
    logic gru_we, gru_page;
    logic [ADDR_W-1:0] gru_addr, gdu_addr;
    logic [63:0] gru_wdata, gdu_rdata;
    logic [7:0] gru_wstrb;
    logic front_idx, back_idx, front_valid, swap_pending, render_allowed, swap_done;
    logic frame_boundary;
    logic [31:0] frame_counter, swap_counter;
    logic frame_done_sticky;

    always_comb begin
        mmio_ready = mmio_valid;
        if (mmio_valid && mmio_we && (mmio_addr[11:0] == REG_CMD_PUSH))
            mmio_ready = cmd_push_ready;
    end

    assign irq_done = swap_done;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            cmd0 <= '0; cmd1 <= '0; cmd2 <= '0; cmd3 <= '0; cmd4 <= '0;
            cmd_push_strobe <= 1'b0;
            soft_reset_strobe <= 1'b0;
            display_enable <= 1'b1;
            frame_done_sticky <= 1'b0;
        end else begin
            cmd_push_strobe <= 1'b0;
            soft_reset_strobe <= 1'b0;
            if (swap_done)
                frame_done_sticky <= 1'b1;
            if (mmio_valid && mmio_we && mmio_ready) begin
                case (mmio_addr[11:0])
                    REG_CTRL: begin
                        display_enable <= mmio_wdata[0];
                        if (mmio_wdata[1])
                            soft_reset_strobe <= 1'b1;
                    end
                    REG_STATUS: if (mmio_wdata[5]) frame_done_sticky <= 1'b0;
                    REG_CMD0: cmd0 <= mmio_wdata;
                    REG_CMD1: cmd1 <= mmio_wdata;
                    REG_CMD2: cmd2 <= mmio_wdata;
                    REG_CMD3: cmd3 <= mmio_wdata;
                    REG_CMD4: cmd4 <= mmio_wdata;
                    REG_CMD_PUSH: cmd_push_strobe <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        mmio_rdata = '0;
        if (mmio_valid && !mmio_we) begin
            case (mmio_addr[11:0])
                REG_CTRL: mmio_rdata = {31'd0, display_enable};
                REG_STATUS: mmio_rdata = {25'd0, gru_error, frame_done_sticky, swap_pending,
                                          frame_closed, cmd_full, gru_idle, gru_busy};
                REG_CMD0: mmio_rdata = cmd0;
                REG_CMD1: mmio_rdata = cmd1;
                REG_CMD2: mmio_rdata = cmd2;
                REG_CMD3: mmio_rdata = cmd3;
                REG_CMD4: mmio_rdata = cmd4;
                REG_CMD_LEVEL: mmio_rdata = cmd_level;
                REG_FRAME_COUNTER: mmio_rdata = frame_counter;
                REG_PAGE_STATUS: mmio_rdata = {29'd0, front_valid, back_idx, front_idx};
                REG_ERR_STATUS: mmio_rdata = {30'd0, err_active_write, gru_error};
                default: ;
            endcase
        end
    end

    sketch_gru_top #(
        .SRC_W(SRC_W), .SRC_H(SRC_H), .ADDR_W(ADDR_W), .CMD_FIFO_DEPTH(CMD_FIFO_DEPTH),
        .ASSET_WORDS(ASSET_WORDS), .ASSET_INIT_FILE(ASSET_INIT_FILE),
        .ENABLE_GOURAUD(ENABLE_GOURAUD)
    ) u_gru (
        .clk(clk), .resetn(resetn), .soft_reset(soft_reset_strobe),
        .render_allowed(render_allowed), .target_page(back_idx),
        .cmd_push_valid(cmd_push_strobe), .cmd_push_w0(cmd0), .cmd_push_w1(cmd1),
        .cmd_push_w2(cmd2), .cmd_push_w3(cmd3), .cmd_push_w4(cmd4), .cmd_push_ready(cmd_push_ready),
        .cmd_level(cmd_level), .cmd_full(cmd_full), .busy(gru_busy), .idle(gru_idle),
        .frame_closed(frame_closed), .present_req(present_req), .error(gru_error),
        .write_attempt(), .gru_we(gru_we), .gru_page(gru_page), .gru_addr(gru_addr),
        .gru_wdata(gru_wdata), .gru_wstrb(gru_wstrb)
    );

    sketch_frame_ctrl u_frame_ctrl (
        .clk(clk), .resetn(resetn), .frame_boundary(frame_boundary), .present_req(present_req),
        .gru_write_attempt(gru_we), .front_idx(front_idx), .back_idx(back_idx),
        .front_valid(front_valid), .swap_pending(swap_pending), .render_allowed(render_allowed),
        .swap_done(swap_done), .active_write_error(err_active_write),
        .frame_counter(frame_counter), .swap_counter(swap_counter)
    );

    sketch_frame_bram_bank #(.SRC_W(SRC_W), .SRC_H(SRC_H), .ADDR_W(ADDR_W)) u_bram (
        .clk(clk), .gru_we(gru_we), .gru_page(gru_page), .gru_addr(gru_addr),
        .gru_wdata(gru_wdata), .gru_wstrb(gru_wstrb),
        .gdu_page(front_idx), .gdu_addr(gdu_addr), .gdu_rdata(gdu_rdata)
    );

    sketch_gdu_top #(
        .SRC_W(SRC_W), .SRC_H(SRC_H), .OUT_W(OUT_W), .OUT_H(OUT_H),
        .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
        .HSYNC_ACTIVE_LOW(HSYNC_ACTIVE_LOW), .VSYNC_ACTIVE_LOW(VSYNC_ACTIVE_LOW), .ADDR_W(ADDR_W)
    ) u_gdu (
        .clk(clk), .resetn(resetn), .display_enable(display_enable), .frame_valid(front_valid),
        .front_page(front_idx), .gdu_page(), .gdu_addr(gdu_addr), .gdu_rdata(gdu_rdata),
        .frame_boundary(frame_boundary), .dvi_clk(dvi_clk), .dvi_hs(dvi_hs), .dvi_vs(dvi_vs),
        .dvi_de(dvi_de), .dvi_d(dvi_d)
    );
endmodule
