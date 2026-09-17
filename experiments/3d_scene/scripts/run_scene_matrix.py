#!/usr/bin/env python3
"""Create immutable run folders and orchestrate a selected RT3D simulation."""
from __future__ import annotations
import argparse,hashlib,json,subprocess,sys
import shutil
from pathlib import Path
def sha(path:Path)->str: return hashlib.sha256(path.read_bytes()).hexdigest()
MODES = {"CPU_ONLY", "CPU_MATMUL", "SCENE_CONTROLLER"}
def count_arg(value: str) -> int:
    value = value.strip().lower()
    if value.endswith("u"):
        value = value[:-1]
    return int(value)
def nonnegative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed

def invoke(root:Path,model:str,mode:str,run_id:str,tb:str,warmup:str,frames:str,repetitions:str,frame_dump_limit:int,reuse_verilator:bool)->None:
    if mode not in MODES: raise SystemExit(f"unsupported mode {mode!r}; expected {sorted(MODES)}")
    run=root/"experiments/3d_scene/runs"/run_id/mode/model; raw=run/"raw"; out=run/"validated"; raw.mkdir(parents=True,exist_ok=False); out.mkdir()
    config=root/"experiments/3d_scene/configs/formal.json"; asset=root/"experiments/3d_scene/assets"/model/"model.s3d.bin"
    warmup_n, frames_n, repetitions_n = map(count_arg, (warmup, frames, repetitions))
    expected_frames = frames_n * repetitions_n
    run_upper = run_id.upper()
    # A restricted dump is always a regression artifact, irrespective of the
    # caller's freely chosen RUN_ID prefix.  This keeps names ergonomic (for
    # example `test-S0-4F-...`) without allowing the result to masquerade as a
    # complete formal image-dump run.
    run_class = "PILOT" if run_upper.startswith("PILOT") else ("REGRESSION" if frame_dump_limit or run_upper.startswith("REG") else "FORMAL")
    manifest={"schema":"scene-controller-run/v1","run_id":run_id,"run_class":run_class,"model":model,"mode":mode,"asset_sha256":sha(asset),"config_sha256":sha(config),"raw":"raw/transcript.log","frame_dump_limit":frame_dump_limit,"warmup_frames":warmup_n,"formal_frames":frames_n,"repetitions":repetitions_n,"expected_formal_frames":expected_frames,"test_timeout_cycles":None}
    (run/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    # The LoongArch toolchain is hosted in WSL; keep the C-image build there.
    linux_dir="/mnt/" + root.drive[0].lower() + root.as_posix()[2:] + "/sdk/software/examples/rt_3d"
    cflags = (f"-DRT3D_WARMUP_FRAMES={warmup} "
              f"-DRT3D_FORMAL_FRAMES={frames} "
              f"-DRT3D_REPETITIONS={repetitions} "
              f"-DRT3D_ASSET_SHA256=\\\"{sha(asset)}\\\" "
              f"-DRT3D_CONFIG_HASH=\\\"{sha(config)}\\\"")
    subprocess.run(["wsl", "bash", "-lc", f"cd '{linux_dir}' && make BENCH_MODE={mode} RT3D_SIMULATION=1 RT3D_MODEL={model} CFLAGS_EXTRA='{cflags}'"], cwd=root, check=True)
    # The TB parameter is compile-time; keep MIF selection explicit instead of
    # overwriting the shared default asset.
    frame_dir = run / "raw" / "frames"
    frame_dir.mkdir()
    frame_dir_rel = "../../" + frame_dir.relative_to(root).as_posix()
    model_file_rel = "../../" + (root/"experiments/3d_scene/assets"/model/"model.s3d.mif").relative_to(root).as_posix()
    verilator_extra = f"-DRT3D_MODE_{mode} -GRT3D_EXPECT_FORMAL_FRAMES={expected_frames} -GFRAME_DUMP_LIMIT={frame_dump_limit}"
    if not reuse_verilator:
        # Preserve the historical compile-time model selection in normal runs.
        verilator_extra = f"-DRT3D_MODEL_{model} " + verilator_extra
    make_args=["make","-C",str(root/"fpga/verilator"),f"TB={tb}","CLEAN_FRAME_OUTPUT=0",f"RUN_ARGS=+UART_ECHO +RT3D_EXT_INIT_FILE={model_file_rel}",f"DVI_OUT_DIR_REL={frame_dir_rel}",f"VERILATOR_EXTRA={verilator_extra}"]
    # Existing runs deliberately preserve their historical compile-per-model
    # behavior.  Reuse mode omits the model macro and lets run-batch retain one
    # binary for all S0..S4 executions of the same backend mode; axi_ram.mif
    # and the external model MIF are read when that binary starts.
    if not reuse_verilator:
        subprocess.run(make_args + ["compile"], cwd=root, check=True)
    command=make_args + ["run-batch"]
    with (raw/"driver.log").open("w",encoding="utf-8") as log:
        rc=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT).returncode
    transcript=root/"fpga/verilator/logs"/f"transcript_{tb}.log"
    if transcript.exists(): (raw/"transcript.log").write_bytes(transcript.read_bytes())
    result=root/"fpga/verilator/logs"/f"result_{tb}.json"
    if result.exists(): shutil.copy2(result, raw/"result.json")
    if rc: raise SystemExit(f"simulation failed ({rc}); inspect {raw/'driver.log'}")
    subprocess.run([sys.executable,str(root/"experiments/3d_scene/scripts/parse_rt3d_uart.py"),str(raw/"transcript.log"),"--model",model,"--output",str(out/"frames.jsonl")],check=True)
    subprocess.run([sys.executable,str(root/"experiments/3d_scene/scripts/validate_run.py"),str(out/"frames.jsonl")],check=True)
def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument("--root",type=Path,required=True); ap.add_argument("--model"); ap.add_argument("--models",nargs="+"); ap.add_argument("--mode",default="SCENE_CONTROLLER",choices=sorted(MODES)); ap.add_argument("--run-id",required=True); ap.add_argument("--tb",default="rt_3d_soc_tb"); ap.add_argument("--warmup",default="30u"); ap.add_argument("--frames",default="300u"); ap.add_argument("--repetitions",default="5u"); ap.add_argument("--frame-dump-limit",type=nonnegative_int,default=0); ap.add_argument("--reuse-verilator",action="store_true",help="reuse one Verilator binary across models of this mode"); a=ap.parse_args()
    a.root = a.root.resolve()
    for model in a.models or [a.model]: invoke(a.root,model,a.mode,a.run_id,a.tb,a.warmup,a.frames,a.repetitions,a.frame_dump_limit,a.reuse_verilator)
    return 0
if __name__ == "__main__": raise SystemExit(main())
