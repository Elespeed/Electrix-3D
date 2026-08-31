module gru_depth_tile_cache #(
    parameter int TILE_W = 8,
    parameter int TILE_H = 8
) (
    input  logic                               clk,
    input  logic                               rstn,
    input  logic                               clr,
    input  logic                               load_tile,
    input  logic [15:0]                        tile_x,
    input  logic [15:0]                        tile_y,
    input  logic                               fill_enable,
    input  logic [15:0]                        fill_data,
    input  logic                               access_valid,
    input  logic [15:0]                        access_tile_x,
    input  logic [15:0]                        access_tile_y,
    input  logic [$clog2(TILE_W)-1:0]          access_x,
    input  logic [$clog2(TILE_H)-1:0]          access_y,
    input  logic                               access_we,
    input  logic [15:0]                        access_wdata,
    output logic                               access_hit,
    output logic [15:0]                        access_rdata,
    output logic                               tile_valid,
    output logic                               tile_dirty,
    output logic [15:0]                        resident_tile_x,
    output logic [15:0]                        resident_tile_y,
    input  logic                               flush_clear_dirty
);
    localparam int TILE_PIXELS = TILE_W * TILE_H;
    logic [15:0] tile_mem [0:TILE_PIXELS-1];
    logic [15:0] tile_x_q;
    logic [15:0] tile_y_q;
    logic        tile_valid_q;
    logic        tile_dirty_q;
    integer      idx;

    function automatic int pixel_index(
        input logic [$clog2(TILE_W)-1:0] px,
        input logic [$clog2(TILE_H)-1:0] py
    );
        begin
            pixel_index = (py * TILE_W) + px;
        end
    endfunction

    assign tile_valid = tile_valid_q;
    assign tile_dirty = tile_dirty_q;
    assign resident_tile_x = tile_x_q;
    assign resident_tile_y = tile_y_q;
    assign access_hit = access_valid && tile_valid_q &&
                        (access_tile_x == tile_x_q) &&
                        (access_tile_y == tile_y_q);
    assign access_rdata = access_hit ? tile_mem[pixel_index(access_x, access_y)] : 16'd0;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tile_x_q <= 16'd0;
            tile_y_q <= 16'd0;
            tile_valid_q <= 1'b0;
            tile_dirty_q <= 1'b0;
            for (idx = 0; idx < TILE_PIXELS; idx = idx + 1) begin
                tile_mem[idx] <= 16'd0;
            end
        end else if (clr) begin
            tile_valid_q <= 1'b0;
            tile_dirty_q <= 1'b0;
        end else begin
            if (load_tile) begin
                tile_x_q <= tile_x;
                tile_y_q <= tile_y;
                tile_valid_q <= 1'b1;
                tile_dirty_q <= 1'b0;
                for (idx = 0; idx < TILE_PIXELS; idx = idx + 1) begin
                    tile_mem[idx] <= fill_enable ? fill_data : 16'd0;
                end
            end
            if (access_hit && access_we) begin
                tile_mem[pixel_index(access_x, access_y)] <= access_wdata;
                tile_dirty_q <= 1'b1;
            end
            if (flush_clear_dirty) begin
                tile_dirty_q <= 1'b0;
            end
        end
    end
endmodule
