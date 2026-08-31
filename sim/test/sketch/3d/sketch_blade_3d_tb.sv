`timescale 1ns/1ps
module sketch_blade_3d_tb;
`ifdef MODELSIM_BUILD
    localparam string BLADE_MIF = "../../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`else
    localparam string BLADE_MIF = "../../assets/3d/generated/blade/legacy_v3/blade_shade.s3d.mif";
`endif

    sketch_model_3d_tb #(
        .INIT_FILE(BLADE_MIF),
        .TESTCASE("sketch_blade_3d_tb")
    ) tb();
endmodule
