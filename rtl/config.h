// Select the shared RTL config profile explicitly when possible.  System-level
// flows now distinguish "remote" and "complex"; the legacy sim profile is kept
// only for lightweight local demos/TBs that still include config.h directly.
//
// NOTE: Keep this header re-evaluable. ModelSim compiles the source list with
// -mfcu, so the config selection must be refreshed for each source file rather
// than being frozen by the first include in the shared compilation unit.

`include "config_remote.h"
