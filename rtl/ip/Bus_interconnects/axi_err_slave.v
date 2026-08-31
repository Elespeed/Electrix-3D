// Simple AXI4 slave which always completes transactions with an error response.
// Purpose: avoid bus deadlock when a decoded AXI target is not implemented.
//
// - Read  : returns rdata=0, rresp=DECERR for each beat, with proper rlast.
// - Write : accepts all write data beats, then returns bresp=DECERR.
//
// Notes:
// - Supports INCR bursts (len beats) by counting beats; address is ignored.
// - ID is returned as received.

module axi_err_slave #(
  parameter integer ID_WIDTH   = 5,
  parameter integer ADDR_WIDTH = 32,
  parameter integer DATA_WIDTH = 32
) (
  input  wire                    clk,
  input  wire                    resetn,

  // AR
  input  wire                    arvalid,
  output wire                    arready,
  input  wire [ADDR_WIDTH-1:0]   araddr,
  input  wire [ID_WIDTH-1:0]     arid,
  input  wire [7:0]              arlen,
  input  wire [2:0]              arsize,
  input  wire [1:0]              arburst,
  input  wire                    arlock,
  input  wire [3:0]              arcache,
  input  wire [2:0]              arprot,

  // R
  output reg                     rvalid,
  input  wire                    rready,
  output reg  [DATA_WIDTH-1:0]   rdata,
  output reg  [ID_WIDTH-1:0]     rid,
  output reg  [1:0]              rresp,
  output reg                     rlast,

  // AW
  input  wire                    awvalid,
  output wire                    awready,
  input  wire [ADDR_WIDTH-1:0]   awaddr,
  input  wire [ID_WIDTH-1:0]     awid,
  input  wire [7:0]              awlen,
  input  wire [2:0]              awsize,
  input  wire [1:0]              awburst,
  input  wire                    awlock,
  input  wire [3:0]              awcache,
  input  wire [2:0]              awprot,

  // W
  input  wire                    wvalid,
  output wire                    wready,
  input  wire [DATA_WIDTH-1:0]   wdata,
  input  wire [(DATA_WIDTH/8)-1:0] wstrb,
  input  wire                    wlast,

  // B
  output reg                     bvalid,
  input  wire                    bready,
  output reg  [ID_WIDTH-1:0]     bid,
  output reg  [1:0]              bresp
);

  // Unused payload fields (kept for a consistent AXI pinout)
  wire _unused = &{araddr, arsize, arburst, arlock, arcache, arprot,
                   awaddr, awsize, awburst, awlock, awcache, awprot,
                   wdata, wstrb};

  // Read burst state
  reg [7:0]  rd_len;
  reg [7:0]  rd_cnt;
  reg        rd_active;

  // Write burst state
  reg [7:0]  wr_len;
  reg [7:0]  wr_cnt;
  reg        wr_active;

  // Always ready to take address/data when not holding a response.
  assign arready = resetn && (!rvalid); // single outstanding read burst
  assign awready = resetn && (!bvalid) && (!wr_active); // single outstanding write burst
  assign wready  = resetn && wr_active; // accept beats once AW accepted

  always @(posedge clk) begin
    if (!resetn) begin
      rvalid    <= 1'b0;
      rdata     <= {DATA_WIDTH{1'b0}};
      rid       <= {ID_WIDTH{1'b0}};
      rresp     <= 2'b11; // DECERR
      rlast     <= 1'b0;
      rd_len    <= 8'd0;
      rd_cnt    <= 8'd0;
      rd_active <= 1'b0;

      bvalid    <= 1'b0;
      bid       <= {ID_WIDTH{1'b0}};
      bresp     <= 2'b11; // DECERR
      wr_len    <= 8'd0;
      wr_cnt    <= 8'd0;
      wr_active <= 1'b0;
    end else begin
      // -------------------------
      // Read address handshake
      // -------------------------
      if (arvalid && arready) begin
        rd_active <= 1'b1;
        rd_len    <= arlen;
        rd_cnt    <= 8'd0;

        rid       <= arid;
        rdata     <= {DATA_WIDTH{1'b0}};
        rresp     <= 2'b11; // DECERR
        rlast     <= (arlen == 8'd0);
        rvalid    <= 1'b1;
      end else if (rvalid && rready) begin
        // Advance within the burst
        if (rd_active) begin
          if (rd_cnt == rd_len) begin
            // Last beat just accepted
            rvalid    <= 1'b0;
            rlast     <= 1'b0;
            rd_active <= 1'b0;
          end else begin
            rd_cnt <= rd_cnt + 8'd1;
            rlast  <= ((rd_cnt + 8'd1) == rd_len);
            rvalid <= 1'b1;
          end
        end else begin
          rvalid <= 1'b0;
          rlast  <= 1'b0;
        end
      end

      // -------------------------
      // Write address handshake
      // -------------------------
      if (awvalid && awready) begin
        wr_active <= 1'b1;
        wr_len    <= awlen;
        wr_cnt    <= 8'd0;
        bid       <= awid;
      end

      // -------------------------
      // Write data handshake
      // -------------------------
      if (wvalid && wready) begin
        if (wr_active) begin
          // Prefer wlast to end early; otherwise end when count reaches len.
          if (wlast || (wr_cnt == wr_len)) begin
            wr_active <= 1'b0;
            bvalid    <= 1'b1;
            bresp     <= 2'b11; // DECERR
          end else begin
            wr_cnt <= wr_cnt + 8'd1;
          end
        end
      end

      // -------------------------
      // Write response handshake
      // -------------------------
      if (bvalid && bready) begin
        bvalid <= 1'b0;
      end
    end
  end

endmodule
