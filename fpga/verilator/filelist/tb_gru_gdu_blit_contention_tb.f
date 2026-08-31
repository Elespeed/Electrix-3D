# Verilator filelist entry for gru_gdu_blit_contention_tb.
# Verilator resolves nested -f relative to CWD (fpga/verilator), so base.f is
# referenced as filelist/base.f (cf. ModelSim's `-f base.f` run from build/).
-f filelist/base_legacy.f
../../sim/test/gru_gdu_blit_contention_tb.sv
