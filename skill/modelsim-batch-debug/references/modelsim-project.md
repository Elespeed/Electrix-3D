# ModelSim Project Reference

Project root:

- `D:\FPGA\ciciec2026_loongson_preliminary\fpga\modelsim`

Default batch command:

```powershell
make -C fpga/modelsim run-batch
```

Stable project facts:

- Batch entrypoint: `scripts/run_batch.do`
- Snapshot entrypoint: `scripts/snapshot.do`
- Transcript path pattern: `logs/transcript_<TB>.log`
- Result path pattern: `logs/result_<TB>.json`
- Base TB file pattern: `filelist/tb_<TB>.f`
- Base VCD preset pattern: `vcdcfg/<TB>.<preset>.lst`
- Manifest path: `vcdcfg/manifest.yaml`

Supported Makefile knobs:

- `TB`
- `VCD`
- `VCD_CFG`
- `VCD_OUT`
- `VCD_START`
- `VCD_END`
- `VCD_TRIGGER`
- `VCD_PRE`
- `VCD_POST`
- `VCDCFG_DIR`
- `VCD_ROOT`
- `PHASE`
- `PROFILES`
- `RESULT_JSON`
- `MANIFEST_PATH`
- `SNAPSHOT_TIME`
- `SNAPSHOT_SIGNALS_FILE`
- `SNAPSHOT_OUT`

VCD naming derived from `scripts/vcd_utils.tcl`:

- full mode: `<VCD_ROOT>/<TB>/<VCD_CFG>.vcd`
- window mode: `<VCD_ROOT>/<TB>/<VCD_CFG>__<start>__<end>.vcd`
- trigger mode: `<VCD_ROOT>/<TB>/<VCD_CFG>__trigger.vcd`

Default escalation policy:

1. `lite` + bounded window
2. `lite` + trigger-centered capture
3. manifest-driven profiles + temporary cfg
4. `debug`
5. `full` only when explicitly requested

Evidence order:

1. `result_<TB>.json`
2. transcript summary
3. VCD metadata summary
4. targeted signal/time queries
5. snapshot
6. temporary cfg expansion
7. rerun
