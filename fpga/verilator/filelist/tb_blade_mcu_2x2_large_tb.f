# Independent MCU-equivalence application image; the runner selects its ROM.
# This acceptance TB uses the Blade2x2 contract: 400x240 logical framebuffer
# with 800x480 2x scanout.  Keep the profile local to this TB so other SoC
# regressions using base_soc.f retain their own CONFIG_PROFILE selection.
+define+RTL_USE_BLADE2X2_CONFIG
-f filelist/base_soc.f
../../rtl/soc_top_lv3_board2x2.sv
../../sim/test/blade/blade_mcu_2x2_large_tb.sv
