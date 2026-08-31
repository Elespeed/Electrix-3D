# Verilator filelist for gru_gdu_blit_contention_tb.
# Slimmed from fpga/modelsim/filelist/base.f per task book §6.2: only the RTL
# this TB actually reaches is kept. CPU (open-la500), UART, confreg, board-level
# SoC tops, sirv/apb peripherals and clk_pll stubs are dropped — they are not
# instantiated by graph_system.
#
# Path-depth note: ModelSim runs vlog from fpga/modelsim/build (3 levels deep),
# so its base.f uses ../../../ to reach the repo root. The Verilator driver runs
# from fpga/verilator (2 levels deep), so this file uses ../../ instead.
# Verilator also resolves nested -f relative to CWD (not the including file),
# hence tb_*.f references this as `filelist/base.f`. This filelist is otherwise a
# mirror of modelsim/base.f minus the unreachable modules.

+incdir+../../rtl
+incdir+../../sim
+incdir+../../sim/agents
+incdir+../../sim/ddr
+incdir+../../rtl/ip/gru
+incdir+../../rtl/ip/gdu
+incdir+../../rtl/ip/gru/engine_3d
+incdir+../../rtl/ip/gru/engine_3d_lite

# --- TB agents / reference model actually instantiated by this TB ---
../../sim/agents/axi_reg_write_monitor.sv
../../sim/agents/gru_cmd_monitor.sv
../../sim/agents/cfg_driver.sv
../../sim/agents/lcd_monitor.sv
../../sim/model/gru_ref_model.sv

# --- DDR3 behavioural model. The real Micron model (sim/ddr/{wiredly,ddr3_model,
# ddr3_model_wrapper}) uses tristate/strength constructs Verilator cannot parse,
# and is inert under SIM_USE_FAST_RAM anyway (DDR pins tied off by gen_sim).
# Per task §7.3 we use a Verilator behavioural no-op stub with the same ports.
# ModelSim still uses the real model via its own filelist. ---
behav/ddr3_model_wrapper_stub.sv

# --- reset synchroniser (pulled in by GRU/GDU internals) ---
../../rtl/ip/rst_sync/rst_sync.v

# --- RAM wrappers used by the SIM_USE_FAST_RAM datapath (framebuffer store) ---
../../rtl/ip/ram_wrap/fpga_sram_sp.v
../../rtl/ip/ram_wrap/axi_wrap_ram_sp.v
# axi_wrap_ram_sp instantiates axi2sram_sp (single-port AXI SRAM controller).
../../rtl/ip/Bus_interconnects/axi2sram_sp.v

# --- GDU RTL (includes ddr_axi_arbiter_2m1s — the contention arbiter) ---
../../rtl/ip/gdu/pixel_fifo.sv
../../rtl/ip/gdu/output_adapter.sv
../../rtl/ip/gdu/lcd_adapter.sv
../../rtl/ip/gdu/dvi_adapter.sv
../../rtl/ip/gdu/display_timing_gen.sv
../../rtl/ip/gdu/fb_addr_gen.sv
../../rtl/ip/gdu/fb_axi_reader.sv
../../rtl/ip/gdu/ddr_axi_arbiter_2m1s.sv
../../rtl/ip/gdu/gdu_regs.sv
../../rtl/ip/gdu/gdu_top.sv

# --- GRU RTL ---
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
../../rtl/ip/gru/gru_axi_writer.sv
../../rtl/ip/gru/gru_regs.sv
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
../../rtl/ip/gru/gru_top.sv

# --- DDR controller top (gen_sim branch = axi_wrap_ram_sp fast RAM) ---
../../rtl/ip/ddr/axi_width_adapter_32_to_128.sv
../../rtl/ip/ddr/ddr_axi_cpu_gru_mux.sv
../../rtl/ip/ddr/ddr_ctrl_top.sv

# --- DUT top ---
../../rtl/sub_system/graph_system.sv
