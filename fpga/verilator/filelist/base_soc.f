# Verilator filelist for SoC-level board testbenches.
# Mirrors fpga/modelsim/filelist/base.f with Verilator-friendly path depth
# adjustments and a DDR wrapper stub in place of the Micron behavioural model.

+incdir+../../rtl
+incdir+../../sim
+incdir+../../sim/agents
+incdir+../../sim/ddr
+incdir+../../rtl/ip/open-la500
+incdir+../../rtl/ip/APB_UART/URT
+incdir+../../rtl/ip/gru
+incdir+../../rtl/ip/gdu
+incdir+../../rtl/ip/perips/apb_i2c

../../sim/agents/uart_agent_pkg.sv
../../sim/agents/uart_driver.sv
../../sim/agents/uart_monitor.sv
../../sim/agents/axi_reg_write_monitor.sv
../../sim/agents/confreg_monitor.sv
../../sim/agents/gru_cmd_monitor.sv
../../sim/agents/cfg_driver.sv
../../sim/agents/dvi_monitor.sv
../../sim/agents/lcd_monitor.sv
../../sim/agents/spi_lcd_monitor.sv
../../sim/model/gru_ref_model.sv
behav/ddr3_model_wrapper_stub.sv

../../rtl/ip/rst_sync/rst_sync.v

../../rtl/ip/Bus_interconnects/axi_err_slave.v
../../rtl/ip/Bus_interconnects/Axi_CDC.v
../../rtl/ip/Bus_interconnects/AxiCrossbar_2x8.v
../../rtl/ip/Bus_interconnects/axi2sram_sp_external.v
../../rtl/ip/Bus_interconnects/axi2sram_sp.v
../../rtl/ip/Bus_interconnects/axi2sram_dp.v

../../rtl/ip/APB_UART/URT/raminfr.v
../../rtl/ip/APB_UART/URT/uart_sync_flops.v
../../rtl/ip/APB_UART/URT/uart_rfifo.v
../../rtl/ip/APB_UART/URT/uart_tfifo.v
../../rtl/ip/APB_UART/URT/uart_regs.v
../../rtl/ip/APB_UART/URT/uart_receiver.v
../../rtl/ip/APB_UART/URT/uart_transmitter.v
../../rtl/ip/APB_UART/URT/uart_top.v
../../rtl/ip/APB_UART/apb_mux2.v
../../rtl/ip/APB_UART/axi2apb.v
../../rtl/ip/APB_UART/axi_uart_controller.v

../../rtl/ip/ram_wrap/fpga_sram_sp.v
../../rtl/ip/ram_wrap/fpga_sram_dp.v
../../rtl/ip/ram_wrap/cache_sram.v
../../rtl/ip/ram_wrap/axi_wrap_ram_sp.v
../../rtl/ip/ram_wrap/axi_wrap_ram_dp.v
../../rtl/ip/ram_wrap/axi_wrap_ram_sp_external.v

../../rtl/ip/gdu/pixel_fifo.sv
../../rtl/ip/gdu/output_adapter.sv
../../rtl/ip/gdu/lcd_adapter.sv
../../rtl/ip/gdu/dvi_adapter.sv
../../rtl/ip/gdu/display_timing_gen.sv
../../rtl/ip/gdu/fb_addr_gen.sv
../../rtl/ip/gdu/fb_axi_reader.sv
../../rtl/ip/gdu/ddr_axi_arbiter_2m1s.sv
../../rtl/ip/gdu/gdu_regs.sv
../../rtl/ip/gdu/gdu_top_spi.sv
../../rtl/ip/gdu/gdu_top.sv
../../rtl/ip/gdu/async_pixel_fifo.sv
../../rtl/ip/gdu/gdu_top_dualclk_test.sv

../../rtl/ip/gru/gru_fifo.sv
../../rtl/ip/gru/gru_colour_lut.sv
../../rtl/ip/gru/gru_cmd_decoder.sv
../../rtl/ip/gru/gru_clipper.sv
../../rtl/ip/gru/gru_span_clipper.sv
../../rtl/ip/gru/gru_blit_engine.sv
../../rtl/ip/gru/gru_clear_engine.sv
../../rtl/ip/gru/gru_line_engine.sv
../../rtl/ip/gru/gru_rect_engine.sv
../../rtl/ip/gru/gru_span_arbiter.sv
../../rtl/ip/gru/gru_seq_tracker.sv
../../rtl/ip/gru/gru_glyph_engine.sv
../../rtl/ip/gru/gru_font_rom.sv
../../rtl/ip/gru/engine_3d/gru_edge_eval.sv
../../rtl/ip/gru/engine_3d/gru_barycentric.sv
../../rtl/ip/gru/engine_3d/gru_attr_interp.sv
../../rtl/ip/gru/engine_3d/gru_texture_addr.sv
../../rtl/ip/gru/engine_3d/gru_texture_sampler.sv
../../rtl/ip/gru/engine_3d/gru_texture_line_cache.sv
../../rtl/ip/gru/engine_3d/gru_color_tile_cache.sv
../../rtl/ip/gru/engine_3d/gru_depth_tile_cache.sv
../../rtl/ip/gru/engine_3d/gru_depth_test.sv
../../rtl/ip/gru/engine_3d/gru_depth_rw.sv
../../rtl/ip/gru/engine_3d/gru_vfetch_dma.sv
../../rtl/ip/gru/engine_3d/gru_index_fetch.sv
../../rtl/ip/gru/engine_3d/gru_vertex_fetch.sv
../../rtl/ip/gru/engine_3d/gru_matrix_transform.sv
../../rtl/ip/gru/engine_3d/gru_reciprocal.sv
../../rtl/ip/gru/engine_3d/gru_viewport_transform.sv
../../rtl/ip/gru/engine_3d/gru_triangle_setup.sv
../../rtl/ip/gru/engine_3d/gru_triangle_raster.sv
../../rtl/ip/gru/engine_3d/gru_triangle_engine.sv
../../rtl/ip/gru/engine_3d_lite/gru_lite_recip_area.sv
../../rtl/ip/gru/engine_3d_lite/gru_lite_triangle_setup.sv
../../rtl/ip/gru/engine_3d_lite/gru_lite_triangle_raster.sv
../../rtl/ip/gru/engine_3d_lite/gru_lite_triangle_engine.sv
../../rtl/ip/gru/gru_axi_writer.sv
../../rtl/ip/gru/gru_regs.sv
../../rtl/ip/gru/gru_top.sv

../../rtl/ip/DVI/axi_dvi.v
../../rtl/ip/ddr/axi_width_adapter_32_to_128.sv
../../rtl/ip/ddr/ddr_axi_cpu_gru_mux.sv
../../rtl/ip/ddr/ddr_ctrl_top.sv

../../rtl/ip/clk_pll_lv2/clk_pll_lv2_stub.v
../../rtl/ip/clk_pll_ddr/clk_pll_ddr_stub.v

../../rtl/ip/confreg/key_debounce.v
../../rtl/ip/confreg/digitaltube_controller.v
../../rtl/ip/confreg/digitaltube_board_controller.v
../../rtl/ip/confreg/confreg.v
../../rtl/ip/confreg/confreg_board.v

../../rtl/ip/open-la500/tools.v
../../rtl/ip/open-la500/regfile.v
../../rtl/ip/open-la500/perf_counter.v
../../rtl/ip/open-la500/alu.v
../../rtl/ip/open-la500/div.v
../../rtl/ip/open-la500/mul.v
../../rtl/ip/open-la500/tlb_entry.v
../../rtl/ip/open-la500/addr_trans.v
../../rtl/ip/open-la500/btb.v
../../rtl/ip/open-la500/lacc_demo.v
../../rtl/ip/open-la500/lacc_core.v
../../rtl/ip/open-la500/csr.v
../../rtl/ip/open-la500/icache.v
../../rtl/ip/open-la500/dcache.v
../../rtl/ip/open-la500/axi_bridge.v
../../rtl/ip/open-la500/if_stage.v
../../rtl/ip/open-la500/id_stage.v
../../rtl/ip/open-la500/exe_stage.v
../../rtl/ip/open-la500/mem_stage.v
../../rtl/ip/open-la500/wb_stage.v
../../rtl/ip/open-la500/mycpu_top.v

../../rtl/ip/sketch_book/model_scene_axi_reader.sv
../../rtl/ip/scene_ctrl/scene_ctrl_math_pkg.sv
../../rtl/ip/scene_ctrl/scene_ctrl_model_fetcher.sv
../../rtl/ip/scene_ctrl/scene_ctrl_vertex_transform.sv
../../rtl/ip/scene_ctrl/scene_ctrl_triangle_frontend.sv
../../rtl/ip/scene_ctrl/scene_ctrl_painter_backend.sv
../../rtl/ip/scene_ctrl/scene_ctrl_model_cache.sv
../../rtl/ip/scene_ctrl/scene_cmd_fifo.sv
../../rtl/ip/scene_ctrl/scene_ctrl_engine.sv
../../rtl/ip/scene_ctrl/scene_ctrl_pipeline.sv
../../rtl/ip/scene_ctrl/scene_ctrl_axi_regs.sv
../../rtl/ip/scene_ctrl/scene_ctrl_top.sv

../../rtl/sub_system/graph_system.sv
