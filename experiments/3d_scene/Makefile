PYTHON ?= python
ROOT := $(abspath ../..)
ROOT_WSL := $(shell wsl wslpath -a "$(ROOT)" 2>/dev/null)
RUN_ID ?= local-$(shell $(PYTHON) -c "import datetime; print(datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))")
MODEL ?= S0
TB ?= rt_3d_soc_tb
RUN_DIR := $(ROOT)/experiments/3d_scene/runs/$(RUN_ID)

.PHONY: assets build smoke run-s0 run-s1 run-s2 run-s3 run-s4 run-matrix validate summarize golden-check

assets:
	@$(PYTHON) scripts/generate_bench_assets.py --root $(ROOT)

build: assets
	@wsl bash -lc "cd '$(ROOT_WSL)/sdk/software/examples/rt_3d' && make BENCH_MODE=SCENE_CONTROLLER RT3D_SIMULATION=1 RT3D_MODEL=$(MODEL)"

# Smoke is deliberately short and produces no formal result set.
smoke:
	@$(MAKE) build MODEL=$(MODEL)
	@$(MAKE) -C $(ROOT)/fpga/verilator TB=$(TB) run-batch CLEAN_FRAME_OUTPUT=0 RUN_ARGS="+UART_ECHO" VERILATOR_EXTRA=-DRT3D_MODEL_$(MODEL)

run-s0: ; @$(MAKE) run MODEL=S0
run-s1: ; @$(MAKE) run MODEL=S1
run-s2: ; @$(MAKE) run MODEL=S2
run-s3: ; @$(MAKE) run MODEL=S3
run-s4: ; @$(MAKE) run MODEL=S4

run: build
	@$(PYTHON) scripts/run_scene_matrix.py --root $(ROOT) --model $(MODEL) --run-id $(RUN_ID) --tb $(TB)

run-matrix: assets
	@$(PYTHON) scripts/run_scene_matrix.py --root $(ROOT) --models S0 S1 S2 S3 S4 --run-id $(RUN_ID) --tb $(TB)

validate:
	@$(PYTHON) scripts/validate_run.py $(RUN_DIR)/validated/frames.jsonl

summarize:
	@$(PYTHON) scripts/summarize.py $(RUN_DIR)/validated/frames.jsonl --output-dir $(RUN_DIR)/summary

golden-check:
	@$(PYTHON) scripts/golden_check.py $(RUN_DIR)/validated/frames.jsonl --goldens goldens/approved_v1.json --output $(RUN_DIR)/validated/golden_checked.jsonl
