`timescale 1ns/1ps

// Independent AXI4-lite regression for matmul_axi_slave.  This deliberately
// avoids the SoC/CPU/ROM path so matrix arithmetic and status semantics remain
// directly attributable to the peripheral.
module matmul_peripheral_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg resetn = 1'b0;

  reg s_awvalid; wire s_awready; reg [31:0] s_awaddr; reg [4:0] s_awid;
  reg [7:0] s_awlen; reg [2:0] s_awsize; reg [1:0] s_awburst; reg s_awlock;
  reg [3:0] s_awcache; reg [2:0] s_awprot;
  reg s_wvalid; wire s_wready; reg [31:0] s_wdata; reg [3:0] s_wstrb; reg s_wlast;
  wire s_bvalid; reg s_bready; wire [4:0] s_bid; wire [1:0] s_bresp;
  reg s_arvalid; wire s_arready; reg [31:0] s_araddr; reg [4:0] s_arid;
  reg [7:0] s_arlen; reg [2:0] s_arsize; reg [1:0] s_arburst; reg s_arlock;
  reg [3:0] s_arcache; reg [2:0] s_arprot;
  wire s_rvalid; reg s_rready; wire [31:0] s_rdata; wire [4:0] s_rid;
  wire [1:0] s_rresp; wire s_rlast;
  integer errors = 0;
  integer i;
  integer poll_count;
  reg [31:0] rd;

  matmul_axi_slave dut (.*);

  task automatic write_reg(input [7:0] addr, input [31:0] data);
    begin
      @(posedge clk); s_awaddr <= {24'b0,addr}; s_awid <= 5'h12;
      s_awlen <= 0; s_awsize <= 3'b010; s_awburst <= 2'b01;
      s_awvalid <= 1; s_wdata <= data; s_wstrb <= 4'hf; s_wlast <= 1; s_bready <= 0;
      while (!s_awready) @(posedge clk);
      @(posedge clk); s_awvalid <= 0; s_wvalid <= 1;
      while (!s_wready) @(posedge clk);
      @(posedge clk); s_wvalid <= 0; s_bready <= 1;
      while (!s_bvalid) @(posedge clk);
      if (s_bresp !== 2'b00) begin $display("[MATMUL] write response error addr=%02x",addr); errors = errors + 1; end
      @(posedge clk); s_bready <= 0;
    end
  endtask

  task automatic write_bad_burst(input [7:0] addr, input [31:0] data);
    begin
      @(posedge clk); s_awaddr <= {24'b0,addr}; s_awid <= 5'h13;
      s_awlen <= 1; s_awsize <= 3'b010; s_awburst <= 2'b01; s_awvalid <= 1;
      s_wdata <= data; s_wstrb <= 4'hf; s_wlast <= 1; s_bready <= 0;
      while (!s_awready) @(posedge clk);
      @(posedge clk); s_awvalid <= 0; s_wvalid <= 1;
      while (!s_wready) @(posedge clk);
      @(posedge clk); s_wvalid <= 0; s_bready <= 1;
      while (!s_bvalid) @(posedge clk);
      @(posedge clk); s_bready <= 0;
    end
  endtask

  task automatic read_reg(input [7:0] addr, output [31:0] data);
    begin
      @(posedge clk); s_araddr <= {24'b0,addr}; s_arid <= 5'h14;
      s_arlen <= 0; s_arsize <= 3'b010; s_arburst <= 2'b01; s_arvalid <= 1; s_rready <= 0;
      while (!s_arready) @(posedge clk);
      @(posedge clk); s_arvalid <= 0; s_rready <= 1;
      while (!s_rvalid) @(posedge clk);
      data = s_rdata;
      @(posedge clk); s_rready <= 0;
    end
  endtask

  task automatic poll_done(output [31:0] status);
    begin
      status = 0;
      for (poll_count = 0; poll_count < 8; poll_count = poll_count + 1) begin
        read_reg(8'h04, status);
        if (status[1]) begin
          $display("[MATMUL] PASS done poll=%0d busy=%0d error=%0d mode=%0d",
                   poll_count, status[0], status[2], status[3]);
          poll_count = 8;
        end
      end
      if (!status[1]) begin
        $display("[MATMUL] FAIL done polling timed out status=%08x", status);
        errors = errors + 1;
      end
    end
  endtask

  task automatic check_expect(input [31:0] actual, input [31:0] wanted, input [8*40-1:0] label);
    begin
      if (actual !== wanted) begin
        $display("[MATMUL] FAIL %0s got=%08x wanted=%08x", label, actual, wanted);
        errors = errors + 1;
      end else $display("[MATMUL] PASS %0s = %08x", label, actual);
    end
  endtask

  initial begin
    s_awvalid=0; s_wvalid=0; s_bready=0; s_arvalid=0; s_rready=0;
    s_awaddr=0; s_awid=0; s_awlen=0; s_awsize=0; s_awburst=0; s_awlock=0; s_awcache=0; s_awprot=0;
    s_wdata=0; s_wstrb=0; s_wlast=0; s_araddr=0; s_arid=0; s_arlen=0; s_arsize=0; s_arburst=0; s_arlock=0; s_arcache=0; s_arprot=0;
    repeat (3) @(posedge clk); resetn <= 1;
    repeat (2) @(posedge clk);

    read_reg(8'h08, rd); check_expect(rd, 32'h4d544d31, "version");

    // Legacy unsigned: diagonal A times a 4x4 B, then verify 3-word/C layout.
    write_reg(8'h10, 1); write_reg(8'h14, 0); write_reg(8'h18, 0); write_reg(8'h1c, 0);
    write_reg(8'h20, 0); write_reg(8'h24, 2); write_reg(8'h28, 0); write_reg(8'h2c, 0);
    write_reg(8'h30, 0); write_reg(8'h34, 0); write_reg(8'h38, 3); write_reg(8'h3c, 0);
    write_reg(8'h40, 0); write_reg(8'h44, 0); write_reg(8'h48, 0); write_reg(8'h4c, 4);
    for (i=0; i<16; i=i+1) write_reg(8'h50 + i*4, (i<4)?11+i:(i<8)?21+i-4:(i<12)?31+i-8:41+i-12);
    write_reg(8'h00, 1);
    poll_done(rd); check_expect(rd & 32'h7, 32'h2, "legacy done");
    check_expect(rd & 32'h1, 0, "legacy idle");
    check_expect(rd & 32'h4, 0, "legacy no error");
    check_expect(rd, 32'h00000002, "legacy status");
    check_expect(dut.c_regs[0], 11, "legacy C00"); check_expect(dut.c_regs[3], 12, "legacy C01");
    check_expect(dut.c_regs[12], 42, "legacy C10"); check_expect(dut.c_regs[45], 176, "legacy C33");

    // Fixed signed Q8.8: A is a scale/translation matrix and B is four
    // vertices stored column-wise (B[k*4+column]); C is row-major.
    write_reg(8'h00, 2); // soft reset, clearing C and status
    write_reg(8'h10, 256); write_reg(8'h14, 0); write_reg(8'h18, 0); write_reg(8'h1c, 128);
    write_reg(8'h20, 0); write_reg(8'h24, 256); write_reg(8'h28, 0); write_reg(8'h2c, 32'hffff_ff00);
    write_reg(8'h30, 0); write_reg(8'h34, 0); write_reg(8'h38, 256); write_reg(8'h3c, 64);
    write_reg(8'h40, 0); write_reg(8'h44, 0); write_reg(8'h48, 0); write_reg(8'h4c, 256);
    // B rows: [v0..v3] for each coordinate, i.e. four vertex columns.
    write_reg(8'h50, 256); write_reg(8'h54, 32'hffff_ff00); write_reg(8'h58, 512); write_reg(8'h5c, 32'hffff_ff80);
    write_reg(8'h60, 256); write_reg(8'h64, 128); write_reg(8'h68, 32'hffff_ff00); write_reg(8'h6c, 32'hffff_ff80);
    write_reg(8'h70, 0);   write_reg(8'h74, 0);   write_reg(8'h78, 256); write_reg(8'h7c, 128);
    write_reg(8'h80, 256); write_reg(8'h84, 256); write_reg(8'h88, 256); write_reg(8'h8c, 256);
    write_reg(8'h00, 5);
    poll_done(rd); check_expect(rd, 32'h0000000a, "fixed done/mode");
    check_expect(dut.c_regs[0], 384, "fixed C00"); check_expect(dut.c_regs[1], 32'hffff_ff80, "fixed C01");
    check_expect(dut.c_regs[2], 640, "fixed C02"); check_expect(dut.c_regs[3], 0, "fixed C03");
    check_expect(dut.c_regs[4], 0, "fixed C10"); check_expect(dut.c_regs[5], 32'hffff_ff80, "fixed C11");
    check_expect(dut.c_regs[6], 32'hffff_fe00, "fixed C12"); check_expect(dut.c_regs[7], 32'hffff_fe80, "fixed C13");
    check_expect(dut.c_regs[8], 64, "fixed C20"); check_expect(dut.c_regs[9], 64, "fixed C21");
    check_expect(dut.c_regs[10], 320, "fixed C22"); check_expect(dut.c_regs[11], 192, "fixed C23");
    check_expect(dut.c_regs[12], 256, "fixed C30"); check_expect(dut.c_regs[15], 256, "fixed C33");

    // Protocol error is sticky and surfaced through STATUS.error.
    write_bad_burst(8'h00, 0);
    read_reg(8'h04, rd); check_expect(rd & 32'h4, 32'h4, "error status");
    if (errors == 0) $display("[MATMUL] PASS: legacy, signed Q8.8, column B/C, polling, and error regression");
    else $fatal(1, "[MATMUL] FAIL: %0d checks", errors);
    $finish;
  end
endmodule
