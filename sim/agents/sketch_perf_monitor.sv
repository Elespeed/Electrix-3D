// Passive simulation-only performance monitor for SketchBook command paths.
// The owning testbench defines the measurement window and supplies DUT events;
// this module deliberately contains no renderer implementation details.
module sketch_perf_monitor (
    input  logic        clk,
    input  logic        resetn,
    input  logic        measure_enable,
    input  logic        renderer_active,
    input  logic        span_valid,
    input  logic        span_ready,
    input  logic        pixel_write,
    input  logic [7:0]  pixel_write_mask,
    output logic [31:0] total_cycles,
    output logic [31:0] renderer_cycles,
    output logic [31:0] span_count,
    output logic [31:0] pixel_write_count
);
    logic measure_enable_q;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            measure_enable_q <= 1'b0;
            total_cycles <= '0;
            renderer_cycles <= '0;
            span_count <= '0;
            pixel_write_count <= '0;
        end else begin
            measure_enable_q <= measure_enable;
            if (measure_enable && !measure_enable_q) begin
                total_cycles <= '0;
                renderer_cycles <= '0;
                span_count <= '0;
                pixel_write_count <= '0;
            end else if (measure_enable) begin
                total_cycles <= total_cycles + 1'b1;
                if (renderer_active)
                    renderer_cycles <= renderer_cycles + 1'b1;
                if (span_valid && span_ready)
                    span_count <= span_count + 1'b1;
                // A span beat can carry up to eight pixels; count valid
                // lanes rather than beat-level write enables.
                if (pixel_write)
                    pixel_write_count <= pixel_write_count + $countones(pixel_write_mask);
            end
        end
    end

    task automatic report(
        input string scenario,
        input integer legacy_renderer_cycles
    );
        integer pixels_per_cycle_milli;
        integer pixels_per_span_milli;
        integer speedup_milli;
        begin
            pixels_per_cycle_milli = (renderer_cycles == 0) ? 0 :
                                     (pixel_write_count * 1000) / renderer_cycles;
            pixels_per_span_milli = (span_count == 0) ? 0 :
                                    (pixel_write_count * 1000) / span_count;
            speedup_milli = (renderer_cycles == 0) ? 0 :
                            (legacy_renderer_cycles * 1000) / renderer_cycles;
            $display("[SKETCH_PERF] scenario=%0s total_cycles=%0d renderer_cycles=%0d pixel_writes=%0d spans=%0d pixels_per_cycle_milli=%0d pixels_per_span_milli=%0d legacy_renderer_cycles=%0d speedup_milli=%0d",
                     scenario, total_cycles, renderer_cycles, pixel_write_count,
                     span_count, pixels_per_cycle_milli, pixels_per_span_milli,
                     legacy_renderer_cycles, speedup_milli);
        end
    endtask
endmodule
