`timescale 1ns / 1ps

module uart_monitor #(
  parameter string LOG_FILE = "uart_tx.log",
  parameter int unsigned MAX_TX_BUFFER_CHARS = 4096
) (
  input logic        clk,
  input logic        rst_n,
  input logic [31:0] bit_cycles,
  input logic        uart_tx_i
);
  import uart_agent_pkg::*;

  integer tx_log_fd;
  int unsigned cycle_count;
  int unsigned last_rx_cycle;
  string tx_buffer;
  byte tx_queue[$];
  event tx_char_ev;
  event tx_line_ev;

  task automatic wait_cycles(input int unsigned cycles);
    int unsigned n;
    begin
      n = (cycles == 0) ? 1 : cycles;
      repeat (n) @(posedge clk);
    end
  endtask

  task automatic capture_uart_char(output bit valid, output byte ch);
    int i;
    reg [7:0] sampled;
    int unsigned local_bit_cycles;
    int unsigned half_bit_cycles;
    begin
      valid = 1'b0;
      ch = 8'h00;
      sampled = 8'h00;
      local_bit_cycles = (bit_cycles < 2) ? 2 : bit_cycles;
      half_bit_cycles = (local_bit_cycles >> 1);
      if (half_bit_cycles == 0) begin
        half_bit_cycles = 1;
      end

      // Confirm this falling edge is a real start bit.
      wait_cycles(half_bit_cycles);
      if (uart_tx_i !== 1'b0) begin
        return;
      end

      // Move to the center of data bit[0].
      wait_cycles(local_bit_cycles);
      for (i = 0; i < 8; i = i + 1) begin
        sampled[i] = uart_tx_i;
        wait_cycles(local_bit_cycles);
      end

      // Stop bit should be high.
      if (uart_tx_i === 1'b1) begin
        ch = sampled;
        valid = 1'b1;
      end
    end
  endtask

  task automatic append_tx_char(input byte ch);
    int start_idx;
    begin
      tx_queue.push_back(ch);
      if (tx_queue.size() > MAX_TX_BUFFER_CHARS) begin
        void'(tx_queue.pop_front());
      end

      tx_buffer = {tx_buffer, $sformatf("%c", ch)};
      if (tx_buffer.len() > MAX_TX_BUFFER_CHARS) begin
        start_idx = tx_buffer.len() - MAX_TX_BUFFER_CHARS;
        tx_buffer = tx_buffer.substr(start_idx, tx_buffer.len() - 1);
      end

      if (tx_log_fd != 0) begin
        $fwrite(tx_log_fd, "%c", ch);
      end

      // Opt-in live UART echo for long software-boot simulations.  The normal
      // agent buffer and matching behaviour stay unchanged; pass +UART_ECHO
      // to vsim when the transcript itself should show received characters.
      if ($test$plusargs("UART_ECHO")) begin
        if (ch != 8'h0d) begin
          $write("%c", ch);
        end
      end

      last_rx_cycle = cycle_count;
      ->tx_char_ev;
      if ((ch == 8'h0a) || (ch == 8'h0d)) begin
        ->tx_line_ev;
      end
    end
  endtask

  task automatic uart_wait_tx_string(
    input string expect_str,
    input int timeout_cycles,
    input bit ignore_crlf = 1'b0
  );
    int unsigned start_cycle;
    begin
      if (expect_str.len() == 0) begin
        return;
      end

      start_cycle = cycle_count;
      forever begin
        if (uart_contains(tx_buffer, expect_str, ignore_crlf)) begin
          return;
        end

        if ((timeout_cycles >= 0) && ((cycle_count - start_cycle) >= timeout_cycles)) begin
          $display("[UART_AGENT] wait_tx_string timeout. expect='%s'", expect_str);
          $display("[UART_AGENT] tx_buffer='%s'", tx_buffer);
          $fatal(1, "[UART_AGENT] uart_wait_tx_string timeout");
        end

        @(tx_char_ev or posedge clk);
      end
    end
  endtask

  task automatic uart_wait_tx_idle(input int char_times);
    int unsigned local_char_times;
    int unsigned local_bit_cycles;
    int unsigned idle_cycles;
    begin
      local_char_times = (char_times <= 0) ? 1 : char_times;
      local_bit_cycles = (bit_cycles < 2) ? 2 : bit_cycles;
      idle_cycles = local_char_times * local_bit_cycles * 10;

      while ((cycle_count - last_rx_cycle) < idle_cycles) begin
        @(tx_char_ev or posedge clk);
      end
    end
  endtask

  task automatic uart_clear_tx_buffer();
    begin
      tx_buffer = "";
      tx_queue.delete();
    end
  endtask

  function automatic string uart_get_tx_buffer();
    uart_get_tx_buffer = tx_buffer;
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
      last_rx_cycle <= 0;
      tx_buffer = "";
      tx_queue.delete();
    end else begin
      cycle_count <= cycle_count + 1'b1;
    end
  end

  initial begin
    tx_buffer = "";
    cycle_count = 0;
    last_rx_cycle = 0;
    tx_log_fd = $fopen(LOG_FILE, "w");
  end

  initial begin
    bit valid;
    byte ch;
    wait (rst_n === 1'b1);
    forever begin
      @(negedge uart_tx_i);
      if (!rst_n) begin
        continue;
      end
      capture_uart_char(valid, ch);
      if (valid) begin
        append_tx_char(ch);
      end
    end
  end
endmodule
