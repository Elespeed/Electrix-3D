`timescale 1ns/1ps
module sketch_cat1x_3d_shade_tb;
`ifdef MODELSIM_BUILD
    localparam string CAT_MIF = "../../../assets/3d/generated/cat1x/legacy_v3/cat1x_shade.s3d.mif";
`else
    localparam string CAT_MIF = "../../assets/3d/generated/cat1x/legacy_v3/cat1x_shade.s3d.mif";
`endif

    sketch_model_3d_tb #(
        .INIT_FILE(CAT_MIF),
        .TESTCASE("sketch_cat1x_3d_shade_tb")
    ) tb();
endmodule
