// Compile-time RGB332 asset store.  ID 0 is the built-in cat sprite;
// further descriptors can be added without changing the BLIT datapath.
module sketch_asset_rom #(
    parameter int ASSET_WORDS = 2048,
    parameter string INIT_FILE = ""
) (
    input  logic [7:0]  asset_id,
    input  logic [15:0] src_x,
    input  logic [15:0] src_y,
    output logic        asset_valid,
    output logic [15:0] asset_width,
    output logic [15:0] asset_height,
    output logic [15:0] asset_stride,
    output logic [7:0] pixel
);
    localparam logic [7:0] KEY = 8'he3;
    localparam logic [7:0] FUR = 8'hf4;
    localparam logic [7:0] FUR_D = 8'hcc;
    localparam logic [7:0] CREAM = 8'hff;
    localparam logic [7:0] EYE = 8'h00;
    localparam logic [7:0] PINK = 8'he5;
    logic [7:0] asset_mem [0:ASSET_WORDS-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, asset_mem);
    end

    always_comb begin
        asset_valid = (asset_id == 8'd0) || (asset_id == 8'd1);
        asset_width = 16'd32;
        asset_height = 16'd32;
        asset_stride = 16'd32;
        pixel = KEY;
        if ((asset_id == 8'd1) && (src_x < 32) && (src_y < 32)) begin
            // Asset 1 is the externally initialised 32x32 RGB332 asset.  A
            // deterministic built-in fallback keeps the command usable in
            // standalone simulations where no INIT_FILE is supplied.
            if (INIT_FILE != "")
                pixel = asset_mem[src_y * 32 + src_x];
            else if (src_x[0] ^ src_y[0])
                pixel = FUR_D;
            else
                pixel = CREAM;
        end else if ((asset_id == 8'd0) && (src_x < 32) && (src_y < 32)) begin
            if (((src_y >= 2) && (src_y <= 12) && (src_x >= 4) && (src_x <= 27) &&
                 ((src_x >= 8) || (src_y >= 7)) && ((src_x <= 23) || (src_y >= 7))) ||
                ((src_y >= 12) && (src_y <= 27) && (src_x >= 5) && (src_x <= 26)) ||
                ((src_y >= 24) && (src_y <= 29) && (src_x >= 2) && (src_x <= 29))) pixel = FUR;
            if (((src_y >= 4) && (src_y <= 10) && (src_x >= 5) && (src_x <= 10)) ||
                ((src_y >= 4) && (src_y <= 10) && (src_x >= 21) && (src_x <= 26)) ||
                ((src_y >= 18) && (src_y <= 27) && (src_x >= 8) && (src_x <= 12))) pixel = FUR_D;
            if ((src_y >= 15) && (src_y <= 25) && (src_x >= 9) && (src_x <= 22)) pixel = CREAM;
            if ((src_y >= 13) && (src_y <= 16) && (((src_x >= 10) && (src_x <= 12)) || ((src_x >= 19) && (src_x <= 21)))) pixel = EYE;
            if ((src_y >= 18) && (src_y <= 20) && (src_x >= 15) && (src_x <= 17)) pixel = PINK;
        end
    end
endmodule
