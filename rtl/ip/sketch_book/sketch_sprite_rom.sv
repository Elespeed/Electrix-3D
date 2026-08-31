// Small fixed RGB332 sprite store for the BRAM-native SketchBook path.
// sprite_id 0 is a 32x32 cat; the magenta background is intentionally kept
// in the ROM so the BLIT command can exercise colour-key transparency.
module sketch_sprite_rom (
    input  logic [7:0] sprite_id,
    input  logic [5:0] x,
    input  logic [5:0] y,
    output logic       sprite_valid,
    output logic [7:0] pixel
);
    localparam logic [7:0] KEY    = 8'he3;
    localparam logic [7:0] FUR    = 8'hf4;
    localparam logic [7:0] FUR_D  = 8'hcc;
    localparam logic [7:0] CREAM  = 8'hff;
    localparam logic [7:0] EYE    = 8'h00;
    localparam logic [7:0] PINK   = 8'he5;

    always_comb begin
        sprite_valid = (sprite_id == 8'd0) && (x < 32) && (y < 32);
        pixel = KEY;
        if (sprite_valid) begin
            // Ears, head and body form a deliberately compact, multi-colour
            // benchmark sprite.  All remaining pixels stay colour-keyed.
            if (((y >= 2) && (y <= 12) && (x >= 4) && (x <= 27) &&
                 ((x >= 8) || (y >= 7)) && ((x <= 23) || (y >= 7))) ||
                ((y >= 12) && (y <= 27) && (x >= 5) && (x <= 26)) ||
                ((y >= 24) && (y <= 29) && (x >= 2) && (x <= 29)))
                pixel = FUR;
            if (((y >= 4) && (y <= 10) && ((x >= 5) && (x <= 10))) ||
                ((y >= 4) && (y <= 10) && ((x >= 21) && (x <= 26))) ||
                ((y >= 18) && (y <= 27) && (x >= 8) && (x <= 12)))
                pixel = FUR_D;
            if ((y >= 15) && (y <= 25) && (x >= 9) && (x <= 22))
                pixel = CREAM;
            if ((y >= 13) && (y <= 16) && ((x >= 10) && (x <= 12)))
                pixel = EYE;
            if ((y >= 13) && (y <= 16) && ((x >= 19) && (x <= 21)))
                pixel = EYE;
            if ((y >= 18) && (y <= 20) && (x >= 15) && (x <= 17))
                pixel = PINK;
        end
    end
endmodule
