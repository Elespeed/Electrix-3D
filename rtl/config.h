// Select the shared RTL config profile explicitly when possible.  System-level
// flows now distinguish "remote" and "complex"; the legacy sim profile is kept
// only for lightweight local demos/TBs that still include config.h directly.
//
// NOTE: Keep this header re-evaluable. ModelSim compiles the source list with
// -mfcu, so the config selection must be refreshed for each source file rather
// than being frozen by the first include in the shared compilation unit.
`ifdef RTL_USE_BLADE2X2SIM_CONFIG
`include "config_blade2x2sim.h"
`elsif RTL_USE_MCU_SMALL_SIM_CONFIG
`include "config_mcu_small_sim.h"
`elsif RTL_USE_MCU_SIM_CONFIG
`include "config_mcu_sim.h"
`elsif RTL_USE_BLADE2X2_CONFIG
`include "config_blade2x2.h"
`elsif RTL_USE_SIM320X240_CONFIG
`include "config_sim320x240.h"
`elsif RTL_USE_REMOTE_CONFIG
`include "config_remote.h"
`elsif RTL_USE_COMPLEX_CONFIG
`include "config_complex.h"
`elsif RTL_USE_BOARD_CONFIG
`include "config_complex.h"
`elsif RTL_USE_SIM_CONFIG
`include "config_sim.h"
`elsif RTL_DEFAULT_REMOTE_CONFIG
`include "config_remote.h"
`elsif FPGA_BUILD
`include "config_complex.h"
`else
`include "config_remote.h"
`endif
