#!/usr/bin/env python3
"""Create immutable run folders and orchestrate a selected RT3D simulation."""
from __future__ import annotations
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
def sha(path:Path)->str: return hashlib.sha256(path.read_bytes()).hexdigest()
MODES = {"CPU_ONLY", "CPU_MATMUL", "SCENE_CONTROLLER"}
def invoke(root:Path,model:str,mode:str,run_id:str,tb:str)->None:
    if mode not in MODES: raise SystemExit(f"unsupported mode {mode!r}; expected {sorted(MODES)}")
    run=root/"experiments/3d_scene/runs"/run_id/mode/model; raw=run/"raw"; out=run/"validated"; raw.mkdir(parents=True,exist_ok=False); out.mkdir()
    config=root/"experiments/3d_scene/configs/formal.json"; asset=root/"experiments/3d_scene/assets"/model/"model.s3d.bin"
    manifest={"schema":"scene-controller-run/v1","run_id":run_id,"model":model,"mode":mode,"asset_sha256":sha(asset),"config_sha256":sha(config),"raw":"raw/transcript.log","frame_dump_limit":0}
    (run/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    # The LoongArch toolchain is hosted in WSL; keep the C-image build there.
    linux_dir="/mnt/" + root.drive[0].lower() + root.as_posix()[2:] + "/sdk/software/examples/rt_3d"
    subprocess.run(["wsl", "bash", "-lc", f"cd '{linux_dir}' && make BENCH_MODE={mode} RT3D_SIMULATION=1 RT3D_MODEL={model}"], cwd=root, check=True)
    # The TB parameter is compile-time; keep MIF selection explicit instead of
    # overwriting the shared default asset.
    command=["make","-C",str(root/"fpga/verilator"),f"TB={tb}","run-batch","CLEAN_FRAME_OUTPUT=0","RUN_ARGS=+UART_ECHO",f"VERILATOR_EXTRA=-DRT3D_MODEL_{model} -DRT3D_MODE_{mode}"]
    with (raw/"driver.log").open("w",encoding="utf-8") as log:
        rc=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT).returncode
    transcript=root/"fpga/verilator/logs"/f"transcript_{tb}.log"
    if transcript.exists(): (raw/"transcript.log").write_bytes(transcript.read_bytes())
    if rc: raise SystemExit(f"simulation failed ({rc}); inspect {raw/'driver.log'}")
    subprocess.run([sys.executable,str(root/"experiments/3d_scene/scripts/parse_rt3d_uart.py"),str(raw/"transcript.log"),"--output",str(out/"frames.jsonl")],check=True)
    subprocess.run([sys.executable,str(root/"experiments/3d_scene/scripts/validate_run.py"),str(out/"frames.jsonl")],check=True)
def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument("--root",type=Path,required=True); ap.add_argument("--model"); ap.add_argument("--models",nargs="+"); ap.add_argument("--mode",default="SCENE_CONTROLLER",choices=sorted(MODES)); ap.add_argument("--run-id",required=True); ap.add_argument("--tb",default="rt_3d_soc_tb"); a=ap.parse_args()
    for model in a.models or [a.model]: invoke(a.root,model,a.mode,a.run_id,a.tb)
    return 0
if __name__ == "__main__": raise SystemExit(main())
