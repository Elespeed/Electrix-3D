module scene_ctrl_painter_backend (
    input logic [1:0] cmd_kind, input logic [7:0] clear_color, input logic [7:0] triangle_color,
    input logic [15:0] x0,input logic [15:0] y0,input logic [15:0] x1,input logic [15:0] y1,input logic [15:0] x2,input logic [15:0] y2,
    input logic [15:0] clear_x,input logic [15:0] clear_y,input logic [15:0] clear_w,input logic [15:0] clear_h,
    output logic [31:0] w0,output logic [31:0] w1,output logic [31:0] w2,output logic [31:0] w3
);
    always_comb begin
        w0=0;w1=0;w2=0;w3=0;
        case(cmd_kind)
            0: w0={19'd0,clear_color,5'd0};
            1: begin w0={19'd0,triangle_color,5'd5}; w1={y0,x0}; w2={y1,x1}; w3={y2,x2}; end
            2: w0={27'd0,5'd6};
            default: begin w0={19'd0,clear_color,5'd1}; w1={clear_y,clear_x}; w2={clear_h,clear_w}; end
        endcase
    end
endmodule
