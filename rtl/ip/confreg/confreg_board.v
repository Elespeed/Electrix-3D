`ifndef CONFREG_ADDR_DEFS
`define CONFREG_ADDR_DEFS
`define CONFREG_INT_ADDR    16'hf000
`define TIMER_ADDR          16'hf100
`define DIGITAL_ADDR        16'hf200
`define LED_ADDR            16'hf300
`define SWITCH_ADDR         16'hf400
`define SIMU_FLAG_ADDR      16'hf500
`endif

module confreg_board #(
    parameter SIMULATION=1'b0
) (
    input             aclk,
    input             aresetn,
    input             cpu_clk,
    input             cpu_resetn,
    input      [4:0]  s_awid,
    input      [31:0] s_awaddr,
    input      [7:0]  s_awlen,
    input      [2:0]  s_awsize,
    input      [1:0]  s_awburst,
    input             s_awlock,
    input      [3:0]  s_awcache,
    input      [2:0]  s_awprot,
    input             s_awvalid,
    output            s_awready,
    input      [4:0]  s_wid,
    input      [31:0] s_wdata,
    input      [3:0]  s_wstrb,
    input             s_wlast,
    input             s_wvalid,
    output reg        s_wready,
    output     [4:0]  s_bid,
    output     [1:0]  s_bresp,
    output reg        s_bvalid,
    input             s_bready,
    input      [4:0]  s_arid,
    input      [31:0] s_araddr,
    input      [7:0]  s_arlen,
    input      [2:0]  s_arsize,
    input      [1:0]  s_arburst,
    input             s_arlock,
    input      [3:0]  s_arcache,
    input      [2:0]  s_arprot,
    input             s_arvalid,
    output            s_arready,
    output     [4:0]  s_rid,
    output reg [31:0] s_rdata,
    output     [1:0]  s_rresp,
    output reg        s_rlast,
    output reg        s_rvalid,
    input             s_rready,
    output     [7:0]  led,
    output     [7:0]  seg_data,
    output     [7:0]  seg_an,
    input      [3:0]  diag_led,
    input      [7:0]  switch,
    input      [4:0]  btn,
    input             dma_finish,
    input             fft_finish,
    output            confreg_int
);

wire [4:0] btn_data = btn;
reg  [31:0] led_data;
wire [31:0] switch_data = {24'd0, switch};
reg  [31:0] simu_flag;
wire [7:0]  led_value = {diag_led, led_data[3:0]};

reg [31:0] confreg_int_en, confreg_int_edge, confreg_int_pol, confreg_int_clr, confreg_int_set;
wire [31:0] confreg_int_state;
reg [31:0] sys_timer, sys_timer_cmp;
reg        sys_timer_en;
reg        timer_int;
reg [31:0] digital_ctrl;
reg [31:0] digital_data;

reg busy, write_phase, req_is_read;
reg [4:0]  buf_id;
reg [31:0] buf_addr;
reg [7:0]  buf_len;
reg [2:0]  buf_size;
reg [1:0]  buf_burst;
reg        buf_lock;
reg [3:0]  buf_cache;
reg [2:0]  buf_prot;

wire ar_enter = s_arvalid & s_arready;
wire r_retire = s_rvalid & s_rready & s_rlast;
wire aw_enter = s_awvalid & s_awready;
wire w_enter  = s_wvalid & s_wready & s_wlast;
wire b_retire = s_bvalid & s_bready;

assign s_arready = ~busy & (!req_is_read | !s_awvalid);
assign s_awready = ~busy & ( req_is_read | !s_arvalid);

always @(posedge aclk or negedge aresetn) begin
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

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        buf_id    <= 5'd0;
        buf_addr  <= 32'd0;
        buf_len   <= 8'd0;
        buf_size  <= 3'd0;
        buf_burst <= 2'd0;
        buf_lock  <= 1'b0;
        buf_cache <= 4'd0;
        buf_prot  <= 3'd0;
        req_is_read <= 1'b0;
    end else if (ar_enter | aw_enter) begin
        req_is_read <= ar_enter;
        buf_id    <= ar_enter ? s_arid    : s_awid;
        buf_addr  <= ar_enter ? s_araddr  : s_awaddr;
        buf_len   <= ar_enter ? s_arlen   : s_awlen;
        buf_size  <= ar_enter ? s_arsize  : s_awsize;
        buf_burst <= ar_enter ? s_arburst : s_awburst;
        buf_lock  <= ar_enter ? s_arlock  : s_awlock;
        buf_cache <= ar_enter ? s_arcache : s_awcache;
        buf_prot  <= ar_enter ? s_arprot  : s_awprot;
    end
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        write_phase <= 1'b0;
        s_wready <= 1'b0;
    end else begin
        if (aw_enter) begin
            write_phase <= 1'b1;
            s_wready <= 1'b1;
        end else if (ar_enter) begin
            write_phase <= 1'b0;
            s_wready <= 1'b0;
        end else if (w_enter) begin
            s_wready <= 1'b0;
        end
    end
end

wire [31:0] rdata_d =
    (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h0))  ? confreg_int_en    :
    (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h4))  ? confreg_int_edge  :
    (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h8))  ? confreg_int_pol   :
    (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'hc))  ? confreg_int_clr   :
    (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h10)) ? confreg_int_set   :
    (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h14)) ? confreg_int_state :
    (buf_addr[15:0] == (`TIMER_ADDR + 16'h0))        ? sys_timer         :
    (buf_addr[15:0] == (`TIMER_ADDR + 16'h4))        ? sys_timer_cmp     :
    (buf_addr[15:0] == (`TIMER_ADDR + 16'h8))        ? {31'd0, sys_timer_en} :
    (buf_addr[15:0] == (`DIGITAL_ADDR + 16'h0))      ? digital_ctrl      :
    (buf_addr[15:0] == (`DIGITAL_ADDR + 16'h4))      ? digital_data      :
    (buf_addr[15:0] == `LED_ADDR)                    ? {24'd0, led_value} :
    (buf_addr[15:0] == `SWITCH_ADDR)                 ? switch_data       :
    (buf_addr[15:0] == `SIMU_FLAG_ADDR)              ? simu_flag         :
    32'd0;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        s_rdata  <= 32'd0;
        s_rvalid <= 1'b0;
        s_rlast  <= 1'b0;
    end else if (busy & !write_phase & !r_retire) begin
        s_rdata  <= rdata_d;
        s_rvalid <= 1'b1;
        s_rlast  <= 1'b1;
    end else if (r_retire) begin
        s_rvalid <= 1'b0;
    end
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        s_bvalid <= 1'b0;
    end else if (w_enter) begin
        s_bvalid <= 1'b1;
    end else if (b_retire) begin
        s_bvalid <= 1'b0;
    end
end

assign s_rid   = buf_id;
assign s_bid   = buf_id;
assign s_bresp = 2'b0;
assign s_rresp = 2'b0;

wire write_timer_cmp = w_enter & (buf_addr[15:0] == (`TIMER_ADDR + 16'h4));
wire write_timer_en  = w_enter & (buf_addr[15:0] == (`TIMER_ADDR + 16'h8));
wire write_led       = w_enter & (buf_addr[15:0] == `LED_ADDR);
wire write_digital_ctrl = w_enter & (buf_addr[15:0] == (`DIGITAL_ADDR + 16'h0));
wire write_digital_data = w_enter & (buf_addr[15:0] == (`DIGITAL_ADDR + 16'h4));

assign led = led_value;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) led_data <= 32'h0;
    else if (write_led) led_data <= {28'd0, s_wdata[3:0]};
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) sys_timer_cmp <= 32'h0;
    else if (write_timer_cmp) sys_timer_cmp <= s_wdata;
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) sys_timer_en <= 1'b0;
    else if (write_timer_en) sys_timer_en <= s_wdata[0];
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        sys_timer <= 32'h0;
        timer_int <= 1'b0;
    end else if (sys_timer_en) begin
        if (sys_timer >= (sys_timer_cmp - 1'b1)) begin
            sys_timer <= 32'h0;
            timer_int <= 1'b1;
        end else begin
            sys_timer <= sys_timer + 1'b1;
            timer_int <= 1'b0;
        end
    end else begin
        sys_timer <= 32'h0;
        timer_int <= 1'b0;
    end
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) digital_ctrl <= 32'd0;
    else if (write_digital_ctrl) digital_ctrl <= s_wdata;
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) digital_data <= 32'd0;
    else if (write_digital_data) digital_data <= s_wdata;
end

digitaltube_board_controller u_digitaltube_board_controller (
    .control_reg (digital_ctrl),
    .data_reg    (digital_data),
    .clk         (aclk),
    .rst_n       (aresetn),
    .seg_data    (seg_data),
    .seg_an      (seg_an)
);

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) simu_flag <= {32{SIMULATION}};
    else simu_flag <= {32{SIMULATION}};
end

wire write_int_en   = w_enter & (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h0));
wire write_int_edge = w_enter & (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h4));
wire write_int_pol  = w_enter & (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h8));
wire write_int_clr  = w_enter & (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'hc));
wire write_int_set  = w_enter & (buf_addr[15:0] == (`CONFREG_INT_ADDR + 16'h10));

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        confreg_int_en   <= 32'h0;
        confreg_int_edge <= 32'h0;
        confreg_int_pol  <= 32'h0;
        confreg_int_clr  <= 32'h0;
        confreg_int_set  <= 32'h0;
    end else begin
        if (write_int_en)   confreg_int_en   <= s_wdata;
        if (write_int_edge) confreg_int_edge <= s_wdata;
        if (write_int_pol)  confreg_int_pol  <= s_wdata;
        if (write_int_clr)  confreg_int_clr  <= s_wdata;
        if (write_int_set)  confreg_int_set  <= s_wdata;
    end
end

localparam integer INT_SRC_NUM = 8;
wire [INT_SRC_NUM-1:0] int_src = {fft_finish, dma_finish, timer_int, btn_data};
reg  [INT_SRC_NUM-1:0] int_src_d;
reg  [INT_SRC_NUM-1:0] edge_state;
reg  [INT_SRC_NUM-1:0] edge_state_next;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) int_src_d <= {INT_SRC_NUM{1'b0}};
    else int_src_d <= int_src;
end

wire [INT_SRC_NUM-1:0] int_edge_sel = confreg_int_edge[INT_SRC_NUM-1:0];
wire [INT_SRC_NUM-1:0] int_pol_sel  = confreg_int_pol[INT_SRC_NUM-1:0];
wire [INT_SRC_NUM-1:0] int_edge_sel_eff = write_int_edge ? s_wdata[INT_SRC_NUM-1:0] : int_edge_sel;
wire [INT_SRC_NUM-1:0] level_state  = (int_src & int_pol_sel) | ((~int_src) & (~int_pol_sel));
wire [INT_SRC_NUM-1:0] edge_pulse   = ((~int_src_d) & int_src & int_pol_sel) |
                                      (int_src_d & (~int_src) & (~int_pol_sel));

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        edge_state <= {INT_SRC_NUM{1'b0}};
    end else begin
        edge_state_next = edge_state;
        if (write_int_edge) edge_state_next = edge_state_next & s_wdata[INT_SRC_NUM-1:0];
        if (write_int_clr)  edge_state_next = edge_state_next & (~s_wdata[INT_SRC_NUM-1:0]);
        if (write_int_set)  edge_state_next = edge_state_next | s_wdata[INT_SRC_NUM-1:0];
        edge_state_next = edge_state_next | (edge_pulse & int_edge_sel_eff);
        edge_state <= edge_state_next;
    end
end

wire [INT_SRC_NUM-1:0] int_state_bits = (edge_state & int_edge_sel) | (level_state & (~int_edge_sel));
assign confreg_int_state = {{(32-INT_SRC_NUM){1'b0}}, int_state_bits};
assign confreg_int = |(confreg_int_state & confreg_int_en);

endmodule
