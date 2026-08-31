// Serializes the CPU AXI wrapper and Scene Controller command producers before
// the single SketchBook MMIO port.  Scene ownership is held for its whole busy
// interval so a five-word command packet cannot be interleaved with CPU writes.
module sketch_mmio_arbiter (
    input logic scene_busy,
    input logic cpu_valid, input logic cpu_we, input logic [31:0] cpu_addr, input logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata, output logic cpu_ready,
    input logic scene_valid, input logic scene_we, input logic [31:0] scene_addr, input logic [31:0] scene_wdata,
    output logic [31:0] scene_rdata, output logic scene_ready,
    output logic sk_valid, output logic sk_we, output logic [31:0] sk_addr, output logic [31:0] sk_wdata,
    input logic [31:0] sk_rdata, input logic sk_ready
);
    always_comb begin
        sk_valid = 1'b0; sk_we = 1'b0; sk_addr = '0; sk_wdata = '0;
        cpu_ready = 1'b0; scene_ready = 1'b0;
        cpu_rdata = sk_rdata; scene_rdata = sk_rdata;
        if (scene_busy) begin
            sk_valid = scene_valid; sk_we = scene_we; sk_addr = scene_addr; sk_wdata = scene_wdata;
            scene_ready = sk_ready;
        end else begin
            sk_valid = cpu_valid; sk_we = cpu_we; sk_addr = cpu_addr; sk_wdata = cpu_wdata;
            cpu_ready = sk_ready;
        end
    end
endmodule
