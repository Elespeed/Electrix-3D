module scene_ctrl_triangle_frontend #(
    parameter logic [15:0] FRAME_W = 400, parameter logic [15:0] FRAME_H = 300
) (
    input logic signed [25:0] x0, input logic signed [25:0] y0, input logic signed [25:0] z0,
    input logic signed [25:0] x1, input logic signed [25:0] y1, input logic signed [25:0] z1,
    input logic signed [25:0] x2, input logic signed [25:0] y2, input logic signed [25:0] z2,
    input logic [15:0] center_x, input logic [15:0] center_y, input logic enable_backface_cull,
    input logic viewport_enable, input logic [15:0] viewport_x, input logic [15:0] viewport_y, input logic [15:0] viewport_w, input logic [15:0] viewport_h,
    output logic visible, output logic [15:0] sx0, output logic [15:0] sy0, output logic [15:0] sx1, output logic [15:0] sy1,
    output logic [15:0] sx2, output logic [15:0] sy2, output logic signed [25:0] depth
);
    logic signed [25:0] area;
    function automatic logic [15:0] clamp_x(input logic signed [25:0] v);
        logic signed [25:0] q, lo, hi; begin q=v+$signed({1'b0,center_x}); lo=viewport_enable ? $signed({1'b0,viewport_x}) : 0; hi=viewport_enable ? $signed({1'b0,viewport_x})+$signed({1'b0,viewport_w})-1 : FRAME_W-1; if(q<lo)clamp_x=lo[15:0]; else if(q>hi)clamp_x=hi[15:0]; else clamp_x=q[15:0]; end
    endfunction
    function automatic logic [15:0] clamp_y(input logic signed [25:0] v);
        logic signed [25:0] q, lo, hi; begin q=$signed({1'b0,center_y})-v; lo=viewport_enable ? $signed({1'b0,viewport_y}) : 0; hi=viewport_enable ? $signed({1'b0,viewport_y})+$signed({1'b0,viewport_h})-1 : FRAME_H-1; if(q<lo)clamp_y=lo[15:0]; else if(q>hi)clamp_y=hi[15:0]; else clamp_y=q[15:0]; end
    endfunction
    always_comb begin
        area=(x1-x0)*(y2-y0)-(x2-x0)*(y1-y0);
        visible=!enable_backface_cull || area>0;
        sx0=clamp_x(x0); sy0=clamp_y(y0); sx1=clamp_x(x1); sy1=clamp_y(y1); sx2=clamp_x(x2); sy2=clamp_y(y2);
        depth=z0+z1+z2;
    end
endmodule
