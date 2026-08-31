# Blender OBJ/MTL -> SK3D assets -> offline reference frames.
# Example: make -f tools/3d_gen/Makefile ASSET=plane SCALE=0.8

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
PYTHON ?= python
ASSET ?=
MODEL_ROOT ?= $(ROOT)/assets/3d/sources
ASSET_ROOT ?= $(ROOT)/assets/3d/generated
PACKAGE_ROOT ?= $(ROOT)/assets/3d/packages/br01
ASSET_DIR ?= $(ASSET_ROOT)/$(ASSET)
V3_ASSET_ROOT ?= $(ASSET_DIR)/v3
V4_ASSET_ROOT ?= $(ASSET_DIR)/v4
FRAME_ROOT ?= $(ROOT)/assets/3d/previews/frame
TARGET_HEIGHT ?= 120
SCALE ?= 1.0
RENDER_PROFILES ?= no_zbuffer zbuffer zbuffer_object_outline

CONVERTER := $(ROOT)/tools/3d_gen/obj2sk3d.py
V4_CONVERTER := $(ROOT)/tools/3d_gen/obj2sk3d_v4.py
RENDERER := $(ROOT)/tools/3d_gen/render_cli.py
ROBOTSS_WALK := $(ROOT)/tools/3d_gen/robotss_articulation/robotss_walk.py
MODEL_DIR := $(MODEL_ROOT)/$(ASSET)
OBJ := $(MODEL_DIR)/$(ASSET).obj
MTL := $(MODEL_DIR)/$(ASSET).mtl
V4_MANIFEST := $(MODEL_DIR)/$(ASSET).v4.json

ifneq ($(wildcard $(V4_MANIFEST)),)
V4_SOURCE_ARGS := --manifest "$(V4_MANIFEST)"
else
V4_SOURCE_ARGS := --single-mesh
endif

.PHONY: all convert convert-v3 convert-v4 package-br01 render render-normal render-shade render-gif help

all: render render-gif

convert: convert-v3 convert-v4

convert-v3:
	@test -n "$(ASSET)" || (echo "ASSET is required, e.g. make -f tools/3d_gen/Makefile ASSET=plane" >&2; exit 2)
	@test -f "$(OBJ)" || (echo "OBJ not found: $(OBJ)" >&2; exit 2)
	@test -f "$(MTL)" || (echo "MTL not found: $(MTL)" >&2; exit 2)
	$(PYTHON) "$(CONVERTER)" "$(OBJ)" --mtl "$(MTL)" --target-height "$(TARGET_HEIGHT)" --scale "$(SCALE)" --center --output "$(V3_ASSET_ROOT)/$(ASSET).s3d.mif"

convert-v4:
	@test -n "$(ASSET)" || (echo "ASSET is required, e.g. make -f tools/3d_gen/Makefile ASSET=robotss" >&2; exit 2)
	@if [ -f "$(V4_MANIFEST)" ]; then echo "V4 mesh manifest: $(V4_MANIFEST)"; else echo "V4 mesh manifest absent; exporting one root mesh"; fi
	$(PYTHON) "$(V4_CONVERTER)" "$(OBJ)" --mtl "$(MTL)" $(V4_SOURCE_ARGS) --target-height "$(TARGET_HEIGHT)" --scale "$(SCALE)" --center --output "$(V4_ASSET_ROOT)/$(ASSET)_shade.s3d.mif"

package-br01:
	$(PYTHON) "$(ROOT)/tools/3d_gen/sk3d_package.py" --name br01 --output-dir "$(PACKAGE_ROOT)" blade="$(ASSET_ROOT)/blade/v4/blade_shade.s3d.bin" robot_rigid="$(ASSET_ROOT)/robotss/v3/robotss_shade.s3d.bin" robotss="$(ASSET_ROOT)/robotss/v4/robotss_shade.s3d.bin"

render: convert
	@for asset in "$(ASSET)" "$(ASSET)_shade"; do \
		for profile in $(RENDER_PROFILES); do \
			$(PYTHON) "$(RENDERER)" "$(V3_ASSET_ROOT)/$$asset.json" --preserve-scale --profile "$$profile" --output-root "$(FRAME_ROOT)" || exit $$?; \
		done; \
	done

render-normal: convert
	@for profile in $(RENDER_PROFILES); do \
		$(PYTHON) "$(RENDERER)" "$(V3_ASSET_ROOT)/$(ASSET).json" --preserve-scale --profile "$$profile" --output-root "$(FRAME_ROOT)" || exit $$?; \
	done

render-shade: convert
	@for profile in $(RENDER_PROFILES); do \
		$(PYTHON) "$(RENDERER)" "$(V3_ASSET_ROOT)/$(ASSET)_shade.json" --preserve-scale --profile "$$profile" --output-root "$(FRAME_ROOT)" || exit $$?; \
	done

render-gif: convert-v3
	@if [ "$(ASSET)" = "robotss" ]; then \
		$(PYTHON) "$(ROBOTSS_WALK)" --skip-v4 --v3-asset-root "$(V3_ASSET_ROOT)" --output "$(FRAME_ROOT)/$(ASSET)/walk_v3"; \
	else \
		echo "GIF preview is currently available only for ASSET=robotss; V3 PNG renders were generated."; \
	fi

help:
	@echo "Usage: make -f tools/3d_gen/Makefile ASSET=plane [SCALE=1.0]"
	@echo "Defaults: MODEL_ROOT=assets/3d/sources ASSET_DIR=assets/3d/generated/<asset> V3_ASSET_ROOT=<asset>/v3 V4_ASSET_ROOT=<asset>/v4 PACKAGE_ROOT=assets/3d/packages/br01 FRAME_ROOT=assets/3d/previews/frame"
	@echo "Targets: all (default), convert, render, render-normal, render-shade, render-gif"
	@echo "RENDER_PROFILES may override the default list of the three supported renderer profiles."
