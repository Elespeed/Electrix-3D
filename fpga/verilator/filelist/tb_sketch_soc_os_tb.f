# RT-Thread Sketch SoC: CPU -> SketchBook BRAM renderer -> RGB332 DVI.
-f filelist/base_soc.f

+incdir+../../rtl/ip/sketch_book
../../sim/sram.v
../../rtl/ip/matmul/matmul_axi_slave.v
../../rtl/ip/sketch_book/sketch_book_axi.sv
../../rtl/ip/sketch_book/sketch_timing_800x600.sv
../../rtl/ip/sketch_book/sketch_frame_bram_bank.sv
../../rtl/ip/sketch_book/sketch_frame_ctrl.sv
../../rtl/ip/sketch_book/sketch_bram_writer.sv
../../rtl/ip/sketch_book/sketch_asset_rom.sv
../../rtl/ip/sketch_book/sketch_span_adapter.sv
../../rtl/ip/sketch_book/sketch_triangle_lite_adapter.sv
../../rtl/ip/sketch_book/sketch_gru_top.sv
../../rtl/ip/sketch_book/sketch_gdu_top.sv
../../rtl/ip/sketch_book/sketch_book_top.sv
../../rtl/soc_top_sketch.sv
../../sim/agents/dvi_monitor_800x600.sv
../../sim/test/sketch_soc/os/sketch_soc_os_tb.sv
