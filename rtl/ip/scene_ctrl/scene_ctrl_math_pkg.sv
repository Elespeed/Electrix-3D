package scene_ctrl_math_pkg;
    // Q1.6 sine table shared by the Scene vertex transform and face shading.
    function automatic logic signed [7:0] sin16(input logic [3:0] a);
        case (a)
            0: sin16 = 0; 1: sin16 = 24; 2: sin16 = 45; 3: sin16 = 59;
            4: sin16 = 64; 5: sin16 = 59; 6: sin16 = 45; 7: sin16 = 24;
            8: sin16 = 0; 9: sin16 = -24; 10: sin16 = -45; 11: sin16 = -59;
            12: sin16 = -64; 13: sin16 = -59; 14: sin16 = -45; default: sin16 = -24;
        endcase
    endfunction
endpackage
