`timescale 1ns / 1ps

package uart_agent_pkg;
  parameter int unsigned UART_BIT_OVERSAMPLE = 16;
  parameter int unsigned UART_DEFAULT_DIVISOR = 16'd1;
  parameter int unsigned UART_DEFAULT_BIT_CYCLES = UART_DEFAULT_DIVISOR * UART_BIT_OVERSAMPLE;
  parameter int unsigned UART_MAX_TX_BUFFER_CHARS = 4096;
  parameter string UART_LINE_ENDING = {8'h0d, 8'h0a};

  function automatic string uart_strip_cr(input string src);
    string dst;
    byte ch;
    int i;
    begin
      dst = "";
      for (i = 0; i < src.len(); i = i + 1) begin
        ch = byte'(src.getc(i));
        if (ch != 8'h0d) begin
          dst = {dst, $sformatf("%c", ch)};
        end
      end
      uart_strip_cr = dst;
    end
  endfunction

  function automatic bit uart_contains(
    input string text_raw,
    input string pattern_raw,
    input bit ignore_crlf
  );
    string text;
    string pattern;
    int i;
    int j;
    bit matched;
    begin
      text = ignore_crlf ? uart_strip_cr(text_raw) : text_raw;
      pattern = ignore_crlf ? uart_strip_cr(pattern_raw) : pattern_raw;
      uart_contains = 1'b0;

      if (pattern.len() == 0) begin
        uart_contains = 1'b1;
      end else if (text.len() >= pattern.len()) begin
        for (i = 0; i <= (text.len() - pattern.len()); i = i + 1) begin
          matched = 1'b1;
          for (j = 0; j < pattern.len(); j = j + 1) begin
            if (text.getc(i + j) != pattern.getc(j)) begin
              matched = 1'b0;
              break;
            end
          end
          if (matched) begin
            uart_contains = 1'b1;
            break;
          end
        end
      end
    end
  endfunction
endpackage

module uart_agent (
  input  logic       clk,
  input  logic       rst_n,
  inout  wire        uart_rx,
  input  logic       uart_tx,
  input  logic       apb_psel,
  input  logic       apb_penable,
  input  logic       apb_pwrite,
  input  logic [7:0] apb_paddr,
  input  logic [7:0] apb_pwdata
);
  import uart_agent_pkg::*;

  logic uart_rx_o;
  logic dlab_shadow;
  logic [7:0] dll_shadow;
  logic [7:0] dlm_shadow;
  logic [15:0] divisor_shadow;
  logic [31:0] bit_cycles_shadow;

  assign uart_rx = uart_rx_o;
  assign divisor_shadow = ({dlm_shadow, dll_shadow} == 16'd0) ? 16'd1 : {dlm_shadow, dll_shadow};
  assign bit_cycles_shadow = divisor_shadow * UART_BIT_OVERSAMPLE;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dlab_shadow <= 1'b0;
      dll_shadow  <= UART_DEFAULT_DIVISOR[7:0];
      dlm_shadow  <= UART_DEFAULT_DIVISOR[15:8];
    end else if (apb_psel && apb_penable && apb_pwrite) begin
      if (apb_paddr[2:0] == 3'h3) begin
        dlab_shadow <= apb_pwdata[7];
      end
      if (dlab_shadow && (apb_paddr[2:0] == 3'h0)) begin
        dll_shadow <= apb_pwdata;
      end
      if (dlab_shadow && (apb_paddr[2:0] == 3'h1)) begin
        dlm_shadow <= apb_pwdata;
      end
    end
  end

  uart_driver u_driver (
    .clk       (clk),
    .rst_n     (rst_n),
    .bit_cycles(bit_cycles_shadow),
    .uart_rx_o (uart_rx_o)
  );

  uart_monitor u_monitor (
    .clk       (clk),
    .rst_n     (rst_n),
    .bit_cycles(bit_cycles_shadow),
    .uart_tx_i (uart_tx)
  );

  task automatic uart_send_byte(input byte ch);
    u_driver.uart_send_byte(ch);
  endtask

  task automatic uart_send_string(input string s);
    u_driver.uart_send_string(s);
  endtask

  task automatic uart_send_line(
    input string s,
    input string line_ending = UART_LINE_ENDING
  );
    u_driver.uart_send_line(s, line_ending);
  endtask

  task automatic uart_wait_tx_string(
    input string expect_str,
    input int timeout_cycles,
    input bit ignore_crlf = 1'b0
  );
    u_monitor.uart_wait_tx_string(expect_str, timeout_cycles, ignore_crlf);
  endtask

  task automatic uart_wait_tx_string_count(
    input string expect_str,
    input int expected_count,
    input int timeout_cycles,
    input bit ignore_crlf = 1'b0
  );
    u_monitor.uart_wait_tx_string_count(expect_str, expected_count, timeout_cycles, ignore_crlf);
  endtask

  task automatic uart_wait_tx_idle(input int char_times);
    u_monitor.uart_wait_tx_idle(char_times);
  endtask

  task automatic uart_wait_signal(
    ref logic sig,
    input logic value,
    input int timeout_cycles
  );
    int i;
    begin
      for (i = 0; i < timeout_cycles; i = i + 1) begin
        if (sig === value) begin
          return;
        end
        @(posedge clk);
      end
      $fatal(1, "[UART_AGENT] timeout in uart_wait_signal");
    end
  endtask

  task automatic uart_expect_and_send(
    input string expect_str,
    input string send_data,
    input bit append_newline = 1'b1,
    input int timeout_cycles = 1000000
  );
    begin
      uart_wait_tx_string(expect_str, timeout_cycles);
      if (append_newline) begin
        uart_send_line(send_data);
      end else begin
        uart_send_string(send_data);
      end
    end
  endtask

  task automatic uart_clear_tx_buffer();
    u_monitor.uart_clear_tx_buffer();
  endtask

  function automatic string uart_get_tx_buffer();
    uart_get_tx_buffer = u_monitor.uart_get_tx_buffer();
  endfunction
endmodule

module pc_watchdog #(
  parameter string NAME = "pc_watchdog",
  parameter int unsigned STUCK_THRESHOLD = 1_000_000,
  parameter bit FATAL_ON_STUCK = 1'b1,
  parameter bit IGNORE_PC_EN = 1'b0,
  parameter logic [31:0] IGNORE_PC = 32'h0000_0000
) (
  input logic        clk,
  input logic        rst_n,
  input logic        monitor_en,
  input logic [31:0] pc,
  input logic [31:0] inst,
  input logic [3:0]  rf_wen,
  input logic [4:0]  rf_wnum,
  input logic [31:0] rf_wdata
);
  localparam int unsigned EFFECTIVE_THRESHOLD = (STUCK_THRESHOLD < 2) ? 2 : STUCK_THRESHOLD;

  logic [31:0] last_pc;
  int unsigned same_pc_count;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_pc <= 32'h0;
      same_pc_count <= 0;
    end else if (!monitor_en) begin
      last_pc <= pc;
      same_pc_count <= 0;
    end else if (IGNORE_PC_EN && (pc == IGNORE_PC)) begin
      last_pc <= pc;
      same_pc_count <= 0;
    end else if (pc == last_pc) begin
      same_pc_count <= same_pc_count + 1;
      if ((same_pc_count + 1) >= EFFECTIVE_THRESHOLD) begin
        $display("[%s] PC stuck detected at t=%0t pc=0x%08h inst=0x%08h repeat=%0d threshold=%0d rf_wen=0x%0h rf_wnum=%0d rf_wdata=0x%08h",
                 NAME, $time, pc, inst, same_pc_count + 1, EFFECTIVE_THRESHOLD, rf_wen, rf_wnum, rf_wdata);
        if (FATAL_ON_STUCK) begin
          $fatal(1, "[%s] stopping simulation due to stuck PC", NAME);
        end else begin
          $error("[%s] stuck PC warning only", NAME);
        end
        same_pc_count <= 0;
      end
    end else begin
      last_pc <= pc;
      same_pc_count <= 0;
    end
  end
endmodule
