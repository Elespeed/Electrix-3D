# Standalone SketchBook rendering test: no SoC, AXI, or DDR dependencies.
+incdir+../../rtl/ip/sketch_book
+incdir+../../rtl/ip/gru

../../rtl/ip/sketch_book/sketch_timing_800x600.sv
../../rtl/ip/sketch_book/sketch_frame_bram_bank.sv
../../rtl/ip/sketch_book/sketch_frame_ctrl.sv
../../rtl/ip/sketch_book/sketch_bram_writer.sv
../../rtl/ip/sketch_book/sketch_asset_rom.sv
../../rtl/ip/sketch_book/sketch_span_adapter.sv
../../rtl/ip/gru/engine_3d_lite/gru_lite_recip_area.sv
../../rtl/ip/gru/engine_3d_lite/gru_lite_triangle_setup.sv
../../rtl/ip/gru/engine_3d_lite/gru_lite_triangle_raster.sv
../../rtl/ip/sketch_book/sketch_triangle_lite_adapter.sv
../../rtl/ip/gru/gru_font_rom.sv
../../rtl/ip/sketch_book/sketch_gru_top.sv
../../rtl/ip/sketch_book/sketch_gdu_top.sv
../../rtl/ip/sketch_book/sketch_book_top.sv
../../sim/agents/dvi_monitor_800x600.sv
../../sim/test/sketch/sketch_book_tb.sv
