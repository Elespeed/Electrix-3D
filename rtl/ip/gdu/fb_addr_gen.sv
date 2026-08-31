module fb_addr_gen (
    input  logic [31:0] fb_base,
    input  logic [31:0] stride,
    input  logic [15:0] x,
    input  logic [15:0] y,
    output logic [31:0] line_base,
    output logic [31:0] pixel_addr
);

    logic [31:0] y_stride;

    assign y_stride  = y * stride;
    assign line_base = fb_base + y_stride;
    assign pixel_addr = line_base + {15'd0, x, 1'b0};

endmodule
