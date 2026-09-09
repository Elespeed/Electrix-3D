PYTHON ?= python
ROOT := $(abspath ../..)
ROOT_WSL := $(shell wsl wslpath -a "$(ROOT)" 2>/dev/null)
RUN_ID ?= local-$(shell $(PYTHON) -c "import datetime; print(datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))")
MODEL ?= S0
MODE ?= SCENE_CONTROLLER
TB ?= rt_3d_soc_tb
CPU_MATMUL_TB ?= rt_3d_soc_matmul_tb
RT3D_WARMUP ?= 30u
RT3D_FRAMES ?= 300u
RT3D_REPETITIONS ?= 5u
RUN_DIR := $(ROOT)/experiments/3d_scene/runs/$(RUN_ID)/$(MODE)/$(MODEL)

VALID_MODES := CPU_ONLY CPU_MATMUL SCENE_CONTROLLER
ifneq ($(filter $(MODE),$(VALID_MODES)),$(MODE))
$(error MODE must be CPU_ONLY, CPU_MATMUL, or SCENE_CONTROLLER (got '$(MODE)'))
endif

.PHONY: assets build smoke cpu-matmul-smoke run-s0 run-s1 run-s2 run-s3 run-s4 run-matrix verify-cpu-matmul verify-cpu-matmul-s1-s4 validate summarize golden-check

assets:
	@$(PYTHON) scripts/generate_bench_assets.py --root $(ROOT)

build: assets
	@wsl bash -lc "cd '$(ROOT_WSL)/sdk/software/examples/rt_3d' && make BENCH_MODE=$(MODE) RT3D_SIMULATION=1 RT3D_MODEL=$(MODEL) CFLAGS_EXTRA='-DRT3D_WARMUP_FRAMES=$(RT3D_WARMUP) -DRT3D_FORMAL_FRAMES=$(RT3D_FRAMES) -DRT3D_REPETITIONS=$(RT3D_REPETITIONS)'"

# Smoke is deliberately short and produces no formal result set.
smoke:
	@$(MAKE) build MODEL=$(MODEL) MODE=$(MODE) RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u
	@$(MAKE) -C $(ROOT)/fpga/verilator TB=$(TB) run-batch CLEAN_FRAME_OUTPUT=0 RUN_ARGS="+UART_ECHO" VERILATOR_EXTRA="-DRT3D_MODEL_$(MODEL) -DRT3D_MODE_$(MODE)"

# Dedicated S0 smoke for the paper-only CPU + Matmul specialized SoC top.
# Keep this explicit so the shared rt_3d_soc_tb path remains unchanged.
cpu-matmul-smoke:
	@$(MAKE) smoke MODE=CPU_MATMUL MODEL=S0 TB=$(CPU_MATMUL_TB)

run-s0: ; @$(MAKE) run MODEL=S0
run-s1: ; @$(MAKE) run MODEL=S1
run-s2: ; @$(MAKE) run MODEL=S2
run-s3: ; @$(MAKE) run MODEL=S3
run-s4: ; @$(MAKE) run MODEL=S4

run: assets
	@$(PYTHON) scripts/run_scene_matrix.py --root $(ROOT) --model $(MODEL) --mode $(MODE) --run-id $(RUN_ID) --tb $(TB) --warmup $(RT3D_WARMUP) --frames $(RT3D_FRAMES) --repetitions $(RT3D_REPETITIONS)

run-matrix: assets
	@$(PYTHON) scripts/run_scene_matrix.py --root $(ROOT) --models S0 S1 S2 S3 S4 --mode $(MODE) --run-id $(RUN_ID) --tb $(TB) --warmup $(RT3D_WARMUP) --frames $(RT3D_FRAMES) --repetitions $(RT3D_REPETITIONS)

# Short, run-local CPU equivalence gate.  Each model is run once per backend
# with 1 warmup / 1 measured frame / 1 repetition; no approved golden is read
# or modified by this target.
verify-cpu-matmul verify-cpu-matmul-s1-s4: assets
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_ONLY MODEL=S1 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_MATMUL MODEL=S1 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_ONLY MODEL=S2 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_MATMUL MODEL=S2 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_ONLY MODEL=S3 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_MATMUL MODEL=S3 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_ONLY MODEL=S4 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(MAKE) run RUN_ID=$(RUN_ID) MODE=CPU_MATMUL MODEL=S4 RT3D_WARMUP=1u RT3D_FRAMES=1u RT3D_REPETITIONS=1u TB=$(TB)
	@$(PYTHON) scripts/check_cpu_matmul_equivalence.py $(ROOT)/experiments/3d_scene/runs/$(RUN_ID)

validate:
	@$(PYTHON) scripts/validate_run.py $(RUN_DIR)/validated/frames.jsonl

summarize:
	@$(PYTHON) scripts/summarize.py $(RUN_DIR)/validated/frames.jsonl --output-dir $(RUN_DIR)/summary

golden-check:
	@$(PYTHON) scripts/golden_check.py $(RUN_DIR)/validated/frames.jsonl --goldens goldens/approved_v1.json --output $(RUN_DIR)/validated/golden_checked.jsonl
