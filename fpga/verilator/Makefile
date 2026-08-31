# Verilator batch flow for gru_gdu_blit_contention_tb (task book §5).
#
# Transparent WSL bridge: Verilator + g++ live only in WSL, so every compile/
# run target shells into WSL (cd via wslpath) and runs scripts/verilator_build.sh.
# The transcript + result JSON land under fpga/verilator/{logs} on the shared
# DrvFs, where the Windows python helpers read them. Plain
#   make -C fpga/verilator TB=gru_gdu_blit_contention_tb run-batch
# works from the repo root on Windows with no `wsl` prefix.

VERILATOR_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT      := $(abspath $(VERILATOR_ROOT)/../..)
FILELIST_DIR   := $(VERILATOR_ROOT)/filelist
SCRIPT_DIR     := $(VERILATOR_ROOT)/scripts
BUILD_DIR      := $(VERILATOR_ROOT)/build
LOG_DIR        ?= $(VERILATOR_ROOT)/logs
VCD_ROOT       ?= $(VERILATOR_ROOT)/vcd

# Windows path of this dir (mingw make gives forward slashes already). wslpath
# consumes this directly.
VERILATOR_ROOT_WIN := $(VERILATOR_ROOT)

TB       ?= gru_gdu_blit_contention_tb
VERILATOR ?= verilator
PYTHON   ?= python
JOBS     ?= 8
CONFIG_PROFILE ?= remote
ifeq ($(CONFIG_PROFILE),remote)
VERILATOR_CONFIG_DEFINE := -DRTL_USE_REMOTE_CONFIG
else ifeq ($(CONFIG_PROFILE),blade2x2)
VERILATOR_CONFIG_DEFINE := -DRTL_USE_BLADE2X2_CONFIG
else ifeq ($(CONFIG_PROFILE),blade2x2sim)
VERILATOR_CONFIG_DEFINE := -DRTL_USE_BLADE2X2SIM_CONFIG
else ifeq ($(CONFIG_PROFILE),complex)
VERILATOR_CONFIG_DEFINE := -DRTL_USE_COMPLEX_CONFIG
else ifeq ($(CONFIG_PROFILE),sim)
VERILATOR_CONFIG_DEFINE := -DRTL_USE_SIM_CONFIG
else ifeq ($(CONFIG_PROFILE),sim320x240)
VERILATOR_CONFIG_DEFINE := -DRTL_USE_SIM320X240_CONFIG
else
$(error Unsupported CONFIG_PROFILE '$(CONFIG_PROFILE)'; expected 'remote', 'complex', 'sim320x240', or legacy 'sim')
endif

# Extra args appended to the verilator command line (e.g. -Wno-... or -Gparam=val).
VERILATOR_EXTRA ?=
VERILATOR_ALL_EXTRA := $(VERILATOR_CONFIG_DEFINE) $(VERILATOR_EXTRA)
# Stream Verilator output to the caller while retaining the per-TB transcript.
# Set LIVE_LOG=0 for CI or callers that require a quiet terminal.
LIVE_LOG ?= 1

VCD ?= 0
VCD_CFG ?= lite
VCD_OUT ?=
VCD_START ?=
VCD_END ?=
PHASE ?=
PROFILES ?=
# Runtime arguments for the generated Verilator binary.  This is useful for
# TB plusargs such as +UART_ECHO, which makes the UART monitor mirror received
# characters into the batch transcript.
RUN_ARGS ?=
# Canonical VCD path on the shared DrvFs. VCD_OUT_REL is the WSL-cwd-relative
# twin verilator_build.sh writes (cwd = fpga/verilator). VCD_OUT overrides the
# absolute path when explicitly set.
VCD_OUT_REL ?= vcd/$(TB)/$(VCD_CFG).vcd
VCD_FILE ?= $(VCD_ROOT)/$(TB)/$(VCD_CFG).vcd

PERF_MODE ?= 0
PERF_REPEAT_COUNT ?= 3
PERF_WARMUP_FRAMES ?= 0
PERF_FRAME_COUNT ?= 8
PERF_RUN_ID ?= 0
PERF_RESULT_JSON ?= $(LOG_DIR)/perf_result_$(TB).json
PERF_RECIPE_TB ?= gru_gdu_blit_contention_tb

CLEAN_FRAME_OUTPUT ?= 1
FRAME_OUTPUT_DIR ?= $(REPO_ROOT)/sim/frame_output
# The WSL runner starts in fpga/verilator.  Keep this relative so the flow is
# portable across workspaces and teammates' machines.
DVI_OUT_DIR_REL ?= ../../sim/frame_output
RESULT_JSON ?= $(LOG_DIR)/result_$(TB).json

FRAME_VIEWER ?= 0
FRAME_VIEWER_PYTHON ?= $(PYTHON)
FRAME_VIEWER_FPS ?= 12
FRAME_VIEWER_MODE ?= loop
FRAME_VIEWER_GLOB ?= *.ppm
FRAME_VIEWER_TITLE ?= Virtual DVI Frame Viewer
FRAME_VIEWER_ARGS ?=

# Perf-mode -> verilator -G parameter overrides (functional mode = PERF_MODE 0).
PERF_G_FLAGS :=
ifeq ($(PERF_MODE),1)
PERF_G_FLAGS := -GPERF_MODE=1 -GPERF_REPEAT_COUNT=$(PERF_REPEAT_COUNT) -GPERF_WARMUP_FRAMES=$(PERF_WARMUP_FRAMES) -GPERF_FRAME_COUNT=$(PERF_FRAME_COUNT) -GPERF_RUN_ID=$(PERF_RUN_ID)
endif

.PHONY: all lint compile run run-batch run-perf perf-result clean clean-logs print-vars clean-frame-output launch-frame-viewer

PRE_RUN_TARGETS :=
ifeq ($(CLEAN_FRAME_OUTPUT),1)
PRE_RUN_TARGETS += clean-frame-output
endif
ifeq ($(FRAME_VIEWER),1)
PRE_RUN_TARGETS += launch-frame-viewer
endif

all: run-batch

# One WSL invocation: `wsl --cd <winpath>` sets the WSL cwd to fpga/verilator,
# then the driver script runs with that cwd (its relative filelist/build/logs
# paths resolve correctly). MSYS_NO_PATHCONV=1 stops Git Bash mangling the
# /mnt-style and D:/ arguments passed to wsl.exe. The trailing 2>/dev/null
# suppresses wsl.exe's own UTF-16 proxy banner (real output is in the transcript).
# VCD/VCD_CFG/VCD_OUT_REL are exported so verilator_build.sh can pick its trace
# flags; VCD tracing is a compile-time choice in Verilator (task §11). NOTE: WSL
# does NOT forward arbitrary env vars by default — WSLENV must list them, else
# VCD arrives as empty inside WSL and tracing silently never engages. (PERF_G_FLAGS
# sidesteps this by crossing as positional args.)
define WSL_RUN
WSLENV=VCD:VCD_CFG:VCD_OUT_REL:VCD_START:VCD_END:RUN_ARGS:DVI_OUT_DIR_REL:LIVE_LOG VCD="$(VCD)" VCD_CFG="$(VCD_CFG)" VCD_OUT_REL="$(VCD_OUT_REL)" VCD_START="$(VCD_START)" VCD_END="$(VCD_END)" RUN_ARGS="$(RUN_ARGS)" DVI_OUT_DIR_REL="$(DVI_OUT_DIR_REL)" LIVE_LOG="$(LIVE_LOG)" MSYS_NO_PATHCONV=1 wsl --cd "$(VERILATOR_ROOT_WIN)" bash scripts/verilator_build.sh $(1) $(TB) $(JOBS) $(PERF_G_FLAGS) $(VERILATOR_ALL_EXTRA) 2>/dev/null
endef

lint:
	@$(call WSL_RUN,lint)

compile:
	@$(call WSL_RUN,compile)

run: run-batch

# Full batch run: WSL compile+simulate (transcript written), then ALWAYS build
# the result JSON (even on failure), then propagate the simulator exit code.
# PERF_MODE=1 additionally builds the perf matrix JSON. VCD capture_mode is
# "window" when VCD=1 + both VCD_START/VCD_END given (custom main crops the dump
# in ps), else "full_run" (VCD=1, no window) or "disabled" (VCD=0).
run-batch: $(PRE_RUN_TARGETS)
	@rc=0; \
	$(call WSL_RUN,run) || rc=$$?; \
	echo "[make] verilator run-batch rc=$$rc (tb=$(TB))"; \
	"$(PYTHON)" "$(SCRIPT_DIR)/build_result_json.py" \
	    --transcript "$(LOG_DIR)/transcript_$(TB).log" \
	    --result "$(RESULT_JSON)" \
	    --tb "$(TB)" \
	    --exit-code $$rc \
	    --mode run \
	    $(if $(findstring 1,$(VCD)),--vcd-path "$(if $(VCD_OUT),$(VCD_OUT),$(VCD_FILE))") \
	    --selected-cfg "$(VCD_CFG)" \
	    --capture-mode "$(if $(findstring 1,$(VCD)),$(if $(VCD_START),$(if $(VCD_END),window,full_run),full_run),disabled)" \
	    --phase "$(PHASE)" \
	    || echo "[make] warning: build_result_json.py failed"; \
	$(if $(findstring 1,$(PERF_MODE)),"$(PYTHON)" "$(SCRIPT_DIR)/build_perf_result_json.py" \
	    --transcript "$(LOG_DIR)/transcript_$(TB).log" \
	    --result "$(PERF_RESULT_JSON)" \
	    --tb "$(TB)" --run-id $(PERF_RUN_ID) \
	    || echo "[make] warning: build_perf_result_json.py failed";) \
	exit $$rc

# Performance benchmark entry points (task §12). PERF_MODE=1 + PERF_* override
# the contention TB's top-level parameters via PERF_G_FLAGS (-G...), re-entering
# run-batch. Verilator --timing + PERF_TIMEOUT(4000ms) make this slower than
# ModelSim wall-clock; reduce PERF_REPEAT_COUNT/PERF_FRAME_COUNT for a quick smoke.
run-perf:
	@$(MAKE) TB=$(PERF_RECIPE_TB) PERF_MODE=1 PERF_REPEAT_COUNT=$(PERF_REPEAT_COUNT) PERF_WARMUP_FRAMES=$(PERF_WARMUP_FRAMES) PERF_FRAME_COUNT=$(PERF_FRAME_COUNT) PERF_RUN_ID=$(PERF_RUN_ID) run-batch

# Rebuild the perf result JSON from an existing transcript without rerunning sim.
perf-result:
	@"$(PYTHON)" "$(SCRIPT_DIR)/build_perf_result_json.py" \
	    --transcript "$(LOG_DIR)/transcript_$(TB).log" \
	    --result "$(PERF_RESULT_JSON)" \
	    --tb "$(TB)" --run-id $(PERF_RUN_ID)

clean-frame-output:
	@target='$(FRAME_OUTPUT_DIR)'; \
	case "$$target" in \
	  "$(REPO_ROOT)"*) ;; \
	  *) echo "refusing to clean frame output outside repo: $$target"; exit 1 ;; \
	esac; \
	mkdir -p "$$target"; \
	find "$$target" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; \
	echo "[make] cleaned frame output: $$target"

launch-frame-viewer:
	@mkdir -p "$(FRAME_OUTPUT_DIR)"; \
	"$(FRAME_VIEWER_PYTHON)" "$(SCRIPT_DIR)/frame_viewer.py" \
	    --dir "$(FRAME_OUTPUT_DIR)" \
	    --fps "$(FRAME_VIEWER_FPS)" \
	    --mode "$(FRAME_VIEWER_MODE)" \
	    --glob "$(FRAME_VIEWER_GLOB)" \
	    --title "$(FRAME_VIEWER_TITLE)" \
	    $(FRAME_VIEWER_ARGS) & \
	echo "[make] launched frame viewer: $(FRAME_OUTPUT_DIR) (mode=$(FRAME_VIEWER_MODE), fps=$(FRAME_VIEWER_FPS))"

clean:
	@rm -rf "$(BUILD_DIR)" "$(VERILATOR_ROOT)/obj_dir"
	@echo "[make] removed build/ obj_dir/"

clean-logs:
	@rm -rf "$(LOG_DIR)"

print-vars:
	@echo "VERILATOR_ROOT=$(VERILATOR_ROOT)"
	@echo "VERILATOR_ROOT_WIN=$(VERILATOR_ROOT_WIN)"
	@echo "REPO_ROOT=$(REPO_ROOT)"
	@echo "TB=$(TB)"
	@echo "CONFIG_PROFILE=$(CONFIG_PROFILE)"
	@echo "VERILATOR=$(VERILATOR)"
	@echo "PYTHON=$(PYTHON)"
	@echo "JOBS=$(JOBS)"
	@echo "VERILATOR_EXTRA=$(VERILATOR_EXTRA)"
	@echo "LIVE_LOG=$(LIVE_LOG)"
	@echo "VERILATOR_ALL_EXTRA=$(VERILATOR_ALL_EXTRA)"
	@echo "BUILD_DIR=$(BUILD_DIR)"
	@echo "LOG_DIR=$(LOG_DIR)"
	@echo "VCD_ROOT=$(VCD_ROOT)"
	@echo "VCD=$(VCD) VCD_CFG=$(VCD_CFG)"
	@echo "VCD_OUT_REL=$(VCD_OUT_REL)"
	@echo "VCD_FILE=$(VCD_FILE)"
	@echo "RUN_ARGS=$(RUN_ARGS)"
	@echo "FRAME_OUTPUT_DIR=$(FRAME_OUTPUT_DIR)"
	@echo "DVI_OUT_DIR_REL=$(DVI_OUT_DIR_REL)"
	@echo "CLEAN_FRAME_OUTPUT=$(CLEAN_FRAME_OUTPUT)"
	@echo "FRAME_VIEWER=$(FRAME_VIEWER)"
	@echo "FRAME_VIEWER_PYTHON=$(FRAME_VIEWER_PYTHON)"
	@echo "FRAME_VIEWER_FPS=$(FRAME_VIEWER_FPS)"
	@echo "FRAME_VIEWER_MODE=$(FRAME_VIEWER_MODE)"
	@echo "FRAME_VIEWER_GLOB=$(FRAME_VIEWER_GLOB)"
	@echo "FRAME_VIEWER_TITLE=$(FRAME_VIEWER_TITLE)"
	@echo "FRAME_VIEWER_ARGS=$(FRAME_VIEWER_ARGS)"
	@echo "RESULT_JSON=$(RESULT_JSON)"
	@echo "PERF_MODE=$(PERF_MODE)"
	@echo "PERF_G_FLAGS=$(PERF_G_FLAGS)"
	@echo "PERF_RESULT_JSON=$(PERF_RESULT_JSON)"
	@echo "PHASE=$(PHASE) PROFILES=$(PROFILES)"
