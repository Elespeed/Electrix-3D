`ifndef RTL_CONFIG_COMMON_H
`define RTL_CONFIG_COMMON_H

`ifdef RTL_SRAM_INIT_FILE
`define SRAM_Init_File `RTL_SRAM_INIT_FILE
`elsif FPGA_BUILD
`define SRAM_Init_File "axi_ram.mif"
`elsif MODELSIM_BUILD
`define SRAM_Init_File "../../../sdk/axi_ram.mif"
`elsif VERILATOR_BUILD
`define SRAM_Init_File "../../sdk/axi_ram.mif"
`else
`define SRAM_Init_File "../../../../../../sdk/axi_ram.mif"
`endif


// Frame output paths for simulation monitors
`define DVI_FRAME_OUTPUT_ROOT_REPO_REL "sim/frame_output"
`ifdef MODELSIM_BUILD
`define DVI_FRAME_OUTPUT_ROOT "../../../sim/frame_output"
`elsif VERILATOR_BUILD
`define DVI_FRAME_OUTPUT_ROOT "../../sim/frame_output"
`else
`define DVI_FRAME_OUTPUT_ROOT "../../../../../../sim/frame_output"
`endif
`define DVI_FRAME_OUTPUT_ROOT_FALLBACK_1 "."
`define DVI_FRAME_OUTPUT_ROOT_FALLBACK_2 "."
`define DVI_FRAME_OUTPUT_ROOT_FALLBACK_3 "."
`define DVI_FRAME_OUTPUT_ROOT_FALLBACK_4 "."
`define DVI_FRAME_OUTPUT_ROOT_FALLBACK_5 "."
`define DVI_FRAME_OUTPUT_ROOT_FALLBACK_6 "."
`define DVI_FRAME_OUTPUT_ROOT_FALLBACK_7 "."

`define USE_CACHE

`define Lawcmd 4
`define Lawdirqid 4
`define Lawstate 2
`define Lawscseti 2
`define Lawid 4
`define Lawaddr 32
`define Lawlen 8
`define Lawsize 3
`define Lawburst 2
`define Lawlock 2
`define Lawcache 4
`define Lawprot 3
`define Lawvalid 1
`define Lawready 1
`define Lwid 4
`define Lwdata 32
`define Lwstrb 4
`define Lwlast 1
`define Lwvalid 1
`define Lwready 1
`define Lbid 4
`define Lbresp 2
`define Lbvalid 1
`define Lbready 1
`define Larcmd 4
`define Larcpuno 10
`define Larid 4
`define Laraddr 32
`define Larlen 8
`define Larsize 3
`define Larburst 2
`define Larlock 2
`define Larcache 4
`define Larprot 3
`define Larvalid 1
`define Larready 1
`define Lrstate 2
`define Lrscseti 2
`define Lrid 4
`define Lrdata 32
`define Lrresp 2
`define Lrlast 1
`define Lrvalid 1
`define Lrready 1
`define Lrrequest 1

`define LID 4
`define LADDR 32
`define LLEN 8
`define LSIZE 3
`define LDATA 32
`define LSTRB 4
`define LBURST 2
`define LLOCK 2
`define LCACHE 4
`define LPROT 3
`define LRESP 2

`define FB_BASE_ADDR        32'ha0000000
`define PIXEL_FORMAT_RGB565 2'b01
`define GDU_DEFAULT_FB_BASE 32'ha0000000
`define GDU_DEFAULT_PIXEL_FMT 2'd1
`define GDU_FIFO_DEPTH      12'd2048

`define DDR_CALIB_TIMEOUT_CYCLES 100_000_000
`define TEST_TIMEOUT_CYCLES      300_000_000

`define LCD_OUTPUT_MODE_PARALLEL 1'b0
`define LCD_OUTPUT_MODE_SPI      1'b1

`endif
