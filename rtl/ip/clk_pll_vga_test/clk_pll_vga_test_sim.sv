`timescale 1ns/1ps
// ModelSim-only replacement for the Clock Wizard IP.  Do not add this file to
// Vivado synthesis; the board build uses the user-generated .xci instead.
module clk_pll_vga_test (
    input logic clk_in1, input logic reset, output logic clk_out1, output logic locked
);
    initial begin clk_out1 = 1'b0; locked = 1'b0; #100ns locked = 1'b1; end
    always #15152ps clk_out1 = ~clk_out1; // 33.000 MHz (30.303... ns period)
    always @(posedge reset) locked <= 1'b0;
    always @(negedge reset) #100ns locked <= 1'b1;
endmodule
