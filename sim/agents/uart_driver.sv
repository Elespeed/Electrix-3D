`timescale 1ns / 1ps

module uart_driver #(
  parameter bit VERBOSE_SEND = 1'b1,
  parameter string SEND_LOG_FILE = "uart_send.log",
  parameter int unsigned INTER_BYTE_IDLE_BITS = 1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] bit_cycles,
  output logic        uart_rx_o
);
  import uart_agent_pkg::*;

  integer send_log_fd;
  int unsigned tx_cycle_count;

  task automatic uart_log_send_byte(input byte ch);
    begin
      if (VERBOSE_SEND) begin
        if (ch == 8'h0d) begin
          $display("[UART_AGENT][SEND][t=%0t][cyc=%0d] \\r (0x%02h)", $time, tx_cycle_count, ch);
        end else if (ch == 8'h0a) begin
          $display("[UART_AGENT][SEND][t=%0t][cyc=%0d] \\n (0x%02h)", $time, tx_cycle_count, ch);
        end else if ((ch >= 8'h20) && (ch <= 8'h7e)) begin
          $display("[UART_AGENT][SEND][t=%0t][cyc=%0d] '%c' (0x%02h)", $time, tx_cycle_count, ch, ch);
        end else begin
          $display("[UART_AGENT][SEND][t=%0t][cyc=%0d] 0x%02h", $time, tx_cycle_count, ch);
        end
      end

      if (send_log_fd != 0) begin
        $fwrite(send_log_fd, "[SEND t=%0t cyc=%0d] 0x%02h\n", $time, tx_cycle_count, ch);
      end
    end
  endtask

  task automatic wait_cycles(input int unsigned cycles);
    int unsigned n;
    begin
      n = (cycles == 0) ? 1 : cycles;
      repeat (n) @(posedge clk);
    end
  endtask

  task automatic wait_one_uart_bit();
    int unsigned local_bit_cycles;
    begin
      local_bit_cycles = (bit_cycles < 2) ? 2 : bit_cycles;
      wait_cycles(local_bit_cycles);
    end
  endtask

  task automatic drive_uart_bit(input logic bit_value);
    begin
      // Drive on negedge to avoid same-edge race with DUT sampling logic.
      @(negedge clk);
      uart_rx_o <= bit_value;
      wait_one_uart_bit();
    end
  endtask

  task automatic uart_send_byte(input byte ch);
    int i;
    int gap_i;
    begin
      if (!rst_n) begin
        @(posedge rst_n);
      end

      uart_log_send_byte(ch);

      drive_uart_bit(1'b0);

      for (i = 0; i < 8; i = i + 1) begin
        drive_uart_bit(ch[i]);
      end

      drive_uart_bit(1'b1);
      for (gap_i = 0; gap_i < INTER_BYTE_IDLE_BITS; gap_i = gap_i + 1) begin
        drive_uart_bit(1'b1);
      end
    end
  endtask

  task automatic uart_send_string(input string s);
    int i;
    byte ch;
    begin
      for (i = 0; i < s.len(); i = i + 1) begin
        ch = byte'(s.getc(i));
        uart_send_byte(ch);
      end
    end
  endtask

  task automatic uart_send_line(
    input string s,
    input string line_ending = UART_LINE_ENDING
  );
    begin
      uart_send_string(s);
      uart_send_string(line_ending);
    end
  endtask

  initial begin
    uart_rx_o = 1'b1;
    tx_cycle_count = 0;
    send_log_fd = $fopen(SEND_LOG_FILE, "w");
  end

  always @(negedge rst_n) begin
    uart_rx_o <= 1'b1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_cycle_count <= 0;
    end else begin
      tx_cycle_count <= tx_cycle_count + 1'b1;
    end
  end
endmodule
