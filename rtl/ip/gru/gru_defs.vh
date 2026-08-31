`ifndef GRU_DEFS_VH
`define GRU_DEFS_VH

`define GRU_OPCODE_W      5
`define GRU_COLOR_W       8
`define GRU_FONT_W        2
`define GRU_X_W           9
// 2D framebuffers can be up to 512 lines.  Keep the command, engine-command
// and span encodings in lockstep when changing this width.
`define GRU_Y_W           9
`define GRU_LEN_W         10
`define GRU_SEQ_W         8
`define GRU_CMD_W         64
`define GRU_ENGINE_CMD_W  64
`define GRU_SPAN_W        64

`define GRU_CMD_FIFO_DEPTH        16
`define GRU_ENGINE_FIFO_DEPTH      8
`define GRU_SPAN_FIFO_DEPTH       16

`define GRU_OP_CLEAR      5'd0
`define GRU_OP_FILL_RECT  5'd1
`define GRU_OP_DRAW_LINE  5'd2
`define GRU_OP_DRAW_GLYPH 5'd3
`define GRU_OP_FENCE      5'd4
`define GRU_OP_BLIT       5'd5
`define GRU_OP_TRIANGLE_FLAT 5'd6
`define GRU_OP_CLEAR_DEPTH 5'd7
`define GRU_OP_TRIANGLE_Z 5'd8
`define GRU_OP_TRIANGLE_GOURAUD 5'd9
`define GRU_OP_SET_TEXTURE 5'd10
`define GRU_OP_TRIANGLE_TEXTURED 5'd11
`define GRU_OP_TRIANGLE_TEXTURED_PC 5'd12

`define GRU_REG_CTRL          8'h00
`define GRU_REG_STATUS        8'h04
`define GRU_REG_FB_BASE       8'h08
`define GRU_REG_STRIDE        8'h0c
`define GRU_REG_WIDTH_HEIGHT  8'h10
`define GRU_REG_PIXEL_FORMAT  8'h14
`define GRU_REG_CMD_W0        8'h18
`define GRU_REG_CMD_W1        8'h1c
`define GRU_REG_CMD_PUSH      8'h20
`define GRU_REG_CMD_LEVEL     8'h24
`define GRU_REG_EXT_W0        8'h30
`define GRU_REG_EXT_W1        8'h34
`define GRU_REG_EXT_W2        8'h38
`define GRU_REG_EXT_W3        8'h3c
`define GRU_REG_EXT_W4        8'h40
`define GRU_REG_EXT_PUSH      8'h44

// Phase-3 depth-buffer interface hook (RESERVED — not yet wired into gru_regs).
// A future 16-bit depth/Z buffer will live at a driver-programmed base address
// written to this register, mirroring GRU_REG_FB_BASE.  Storage layout:
// depth_base + y*stride + x*2, 8 samples / 128-bit beat (same granularity as
// RGB565).  The Z path reuses gru_axi_writer's dirty-beat + flush machinery as
// a second tagged line buffer (read-beat -> merge -> dirty -> flush), sharing
// the GRU write mux.  See doc/04_phase3_memory_pipeline_for_3d_results.md.
`define GRU_REG_DEPTH_BASE    8'h48
`define GRU_REG_DEPTH_CTRL    8'h4c

`define GRU_DEPTH_CTRL_ENABLE_BIT 0
`define GRU_DEPTH_CTRL_WRITE_BIT  1
`define GRU_DEPTH_CTRL_LEQUAL_BIT 2

// Phase-4 GRU performance counter window (read-only).  Counters are cumulative
// since hard reset; software samples a window by differencing two reads.
// Layout mirrors the writer(WCB) + blit cumulative counters fanned into gru_regs.
`define GRU_REG_PERF_WCB_SPAN_IN     8'h50
`define GRU_REG_PERF_WCB_PIX_IN      8'h54
`define GRU_REG_PERF_WCB_AW_TXN      8'h58
`define GRU_REG_PERF_WCB_BEAT_OUT    8'h5c
`define GRU_REG_PERF_WCB_FULL_BEAT   8'h60
`define GRU_REG_PERF_WCB_PARTIAL     8'h64
`define GRU_REG_PERF_WCB_FLUSH       8'h68
`define GRU_REG_PERF_BLIT_COUNT      8'h6c
`define GRU_REG_PERF_BLIT_RD_BEAT    8'h70
`define GRU_REG_PERF_BLIT_WR_BEAT    8'h74
`define GRU_REG_PERF_BLIT_PIXEL      8'h78
`define GRU_REG_PERF_BLIT_CYCLE      8'h7c
`define GRU_REG_TEX_BASE             8'h80
`define GRU_REG_TEX_SIZE             8'h84
`define GRU_REG_TEX_STRIDE           8'h88
`define GRU_REG_TEX_CTRL             8'h8c
`define GRU_REG_CB_BASE              8'h90
`define GRU_REG_CB_WORD_COUNT        8'h94
`define GRU_REG_CB_CTRL              8'h98
`define GRU_REG_CB_STATUS            8'h9c

`define GRU_CB_CTRL_EXEC_BIT         0
`define GRU_CB_CTRL_IRQ_EN_BIT       1

`define GRU_CB_STATUS_BUSY_BIT       0
`define GRU_CB_STATUS_DONE_BIT       1
`define GRU_CB_STATUS_CFG_ERROR_BIT  2
`define GRU_CB_STATUS_AXI_ERROR_BIT  3
`define GRU_CB_STATUS_PRESENT_BIT    4

`define GRU_CB_OP_RAW_CMD            8'h20
`define GRU_CB_OP_RAW_EXT_CMD        8'h21
`define GRU_CB_OP_FENCE              8'h7e
`define GRU_CB_OP_PRESENT            8'h7f

`define GRU_TEX_CTRL_FORMAT_MSB      2
`define GRU_TEX_CTRL_FORMAT_LSB      0
`define GRU_TEX_CTRL_WRAP_BIT        3
`define GRU_TEX_CTRL_FILTER_BIT      4
`define GRU_TEX_WRAP_CLAMP           1'b0
`define GRU_TEX_WRAP_REPEAT          1'b1
`define GRU_TEX_FILTER_NEAREST       1'b0
`define GRU_TEX_FILTER_BILINEAR      1'b1

// Phase-4 GDU performance counter window (read-only, cumulative since hard
// reset).  Defined here (not a separate gdu_defs.vh) so the cfg_driver, the
// phase-4 perf testbench and the RTL all see one shared definition via the
// single proven-resolved include path.  Reader counters come from
// fb_axi_reader; arbiter counters from ddr_axi_arbiter_2m1s (routed via
// gdu_top).  Decoded by gdu_regs on req_addr[7:0].
`define GDU_REG_PERF_RD_AR_TXN       8'h20
`define GDU_REG_PERF_RD_BEAT         8'h24
`define GDU_REG_PERF_RD_WAIT         8'h28
`define GDU_REG_PERF_ARB_GRU_GRANT   8'h2c
`define GDU_REG_PERF_ARB_GDU_GRANT   8'h30
`define GDU_REG_PERF_ARB_GRU_WAIT    8'h34
`define GDU_REG_PERF_ARB_GDU_WAIT    8'h38
`define GDU_REG_PERF_ARB_GRU_MAXWAIT 8'h3c
`define GDU_REG_PERF_ARB_GDU_MAXWAIT 8'h40
`define GDU_REG_PERF_ARB_QOS         8'h44
`define GDU_REG_PERF_ARB_CRITICAL    8'h48
`define GDU_REG_PERF_ARB_STARVE      8'h4c

`define GRU_STATUS_BUSY       0
`define GRU_STATUS_CMD_FULL   1
`define GRU_STATUS_CMD_EMPTY  2
`define GRU_STATUS_DONE       3
`define GRU_STATUS_AXI_ERROR  4
`define GRU_STATUS_CFG_ERROR  5
`define GRU_STATUS_FENCE_DONE 6
`define GRU_STATUS_ENGINE_STALL 7

`define GRU_PIXFMT_RGB565     3'd0
`define GRU_PIXFMT_RGB332     3'd1
`define GRU_PIXFMT_INDEX8     3'd2

`define GRU_CMD0_OPCODE_MSB   4
`define GRU_CMD0_OPCODE_LSB   0
`define GRU_CMD0_COLOR_MSB   12
`define GRU_CMD0_COLOR_LSB    5
`define GRU_CMD0_FONT_MSB    14
`define GRU_CMD0_FONT_LSB    13
`define GRU_CMD0_X0_MSB      23
`define GRU_CMD0_X0_LSB      15
`define GRU_CMD0_Y0_MSB      31
`define GRU_CMD0_Y0_LSB      24

`define GRU_CMD1_X1_MSB       8
`define GRU_CMD1_X1_LSB       0
`define GRU_CMD1_Y1_MSB      16
`define GRU_CMD1_Y1_LSB       9
`define GRU_CMD1_Y0_HI_BIT   17
`define GRU_CMD1_Y1_HI_BIT   18
`define GRU_CMD1_ASCII_MSB    7
`define GRU_CMD1_ASCII_LSB    0

`define GRU_ECMD_OPCODE_MSB    4
`define GRU_ECMD_OPCODE_LSB    0
`define GRU_ECMD_COLOR_MSB    12
`define GRU_ECMD_COLOR_LSB     5
`define GRU_ECMD_FONT_MSB     14
`define GRU_ECMD_FONT_LSB     13
`define GRU_ECMD_X0_MSB       23
`define GRU_ECMD_X0_LSB       15
`define GRU_ECMD_Y0_MSB       31
`define GRU_ECMD_Y0_LSB       24
`define GRU_ECMD_X1_MSB       40
`define GRU_ECMD_X1_LSB       32
`define GRU_ECMD_Y1_MSB       48
`define GRU_ECMD_Y1_LSB       41
`define GRU_ECMD_Y0_HI_BIT   57
`define GRU_ECMD_Y1_HI_BIT   58
`define GRU_ECMD_SEQ_MSB      56
`define GRU_ECMD_SEQ_LSB      49

`define GRU_SPAN_SEQ_MSB       7
`define GRU_SPAN_SEQ_LSB       0
`define GRU_SPAN_Y_MSB        16
`define GRU_SPAN_Y_LSB         8
`define GRU_SPAN_X_MSB        25
`define GRU_SPAN_X_LSB        17
`define GRU_SPAN_LEN_MSB      35
`define GRU_SPAN_LEN_LSB      26
`define GRU_SPAN_COLOR_MSB    51
`define GRU_SPAN_COLOR_LSB    36
`define GRU_SPAN_LAST_BIT     52

`define GRU_TRI_CMD_W             256
`define GRU_TRI_CMD_SEQ_MSB       255
`define GRU_TRI_CMD_SEQ_LSB       248
`define GRU_TRI_CMD_OPCODE_MSB    247
`define GRU_TRI_CMD_OPCODE_LSB    243
`define GRU_TRI_CMD_X0_MSB        242
`define GRU_TRI_CMD_X0_LSB        227
`define GRU_TRI_CMD_Y0_MSB        226
`define GRU_TRI_CMD_Y0_LSB        211
`define GRU_TRI_CMD_X1_MSB        210
`define GRU_TRI_CMD_X1_LSB        195
`define GRU_TRI_CMD_Y1_MSB        194
`define GRU_TRI_CMD_Y1_LSB        179
`define GRU_TRI_CMD_X2_MSB        178
`define GRU_TRI_CMD_X2_LSB        163
`define GRU_TRI_CMD_Y2_MSB        162
`define GRU_TRI_CMD_Y2_LSB        147
`define GRU_TRI_CMD_ATTR0_LO_MSB  146
`define GRU_TRI_CMD_ATTR0_LO_LSB  131
`define GRU_TRI_CMD_ATTR0_HI_MSB  130
`define GRU_TRI_CMD_ATTR0_HI_LSB  115
`define GRU_TRI_CMD_ATTR1_LO_MSB  114
`define GRU_TRI_CMD_ATTR1_LO_LSB   99
`define GRU_TRI_CMD_ATTR1_HI_MSB   98
`define GRU_TRI_CMD_ATTR1_HI_LSB   83
`define GRU_TRI_CMD_ATTR2_LO_MSB   82
`define GRU_TRI_CMD_ATTR2_LO_LSB   67
`define GRU_TRI_CMD_ATTR2_HI_MSB   66
`define GRU_TRI_CMD_ATTR2_HI_LSB   51
`define GRU_TRI_CMD_EXTRA0_MSB     50
`define GRU_TRI_CMD_EXTRA0_LSB     35
`define GRU_TRI_CMD_EXTRA1_MSB     34
`define GRU_TRI_CMD_EXTRA1_LSB     19
`define GRU_TRI_CMD_EXTRA2_MSB     18
`define GRU_TRI_CMD_EXTRA2_LSB      3

`define GRU_DEPTH_CMD_W                144
`define GRU_DEPTH_CMD_SEQ_MSB            7
`define GRU_DEPTH_CMD_SEQ_LSB            0
`define GRU_DEPTH_CMD_OPCODE_MSB        12
`define GRU_DEPTH_CMD_OPCODE_LSB         8
`define GRU_DEPTH_CMD_COLOR_MSB         20
`define GRU_DEPTH_CMD_COLOR_LSB         13
`define GRU_DEPTH_CMD_X0_MSB            29
`define GRU_DEPTH_CMD_X0_LSB            21
`define GRU_DEPTH_CMD_Y0_MSB            37
`define GRU_DEPTH_CMD_Y0_LSB            30
`define GRU_DEPTH_CMD_X1_MSB            46
`define GRU_DEPTH_CMD_X1_LSB            38
`define GRU_DEPTH_CMD_Y1_MSB            54
`define GRU_DEPTH_CMD_Y1_LSB            47
`define GRU_DEPTH_CMD_X2_MSB            63
`define GRU_DEPTH_CMD_X2_LSB            55
`define GRU_DEPTH_CMD_Y2_MSB            71
`define GRU_DEPTH_CMD_Y2_LSB            64
`define GRU_DEPTH_CMD_Z0_MSB            87
`define GRU_DEPTH_CMD_Z0_LSB            72
`define GRU_DEPTH_CMD_Z1_MSB           103
`define GRU_DEPTH_CMD_Z1_LSB            88
`define GRU_DEPTH_CMD_Z2_MSB           119
`define GRU_DEPTH_CMD_Z2_LSB           104
`define GRU_DEPTH_CMD_DEPTH_EN_BIT     120
`define GRU_DEPTH_CMD_DEPTH_WR_BIT     121
`define GRU_DEPTH_CMD_DEPTH_LEQUAL_BIT 122

`define GRU_BLIT_MAX_BURST    8'd15
`define GRU_BLIT_FIFO_DEPTH   32

`endif
