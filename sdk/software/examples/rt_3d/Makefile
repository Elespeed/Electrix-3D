TARGET = rt_3d
RTTHREAD_APP = 1

# Select exactly one reproducible benchmark backend at compile time.
BENCH_MODE ?= CPU_MATMUL
RT3D_MODEL ?= S0
ifeq ($(RT3D_MODEL),S0)
CFLAGS += -DRT3D_MODEL_V=16 -DRT3D_MODEL_T=24 -DRT3D_MODEL_M=1
else ifeq ($(RT3D_MODEL),S1)
CFLAGS += -DRT3D_MODEL_V=32 -DRT3D_MODEL_T=48 -DRT3D_MODEL_M=2
else ifeq ($(RT3D_MODEL),S2)
CFLAGS += -DRT3D_MODEL_V=64 -DRT3D_MODEL_T=96 -DRT3D_MODEL_M=4
else ifeq ($(RT3D_MODEL),S3)
CFLAGS += -DRT3D_MODEL_V=96 -DRT3D_MODEL_T=144 -DRT3D_MODEL_M=8
else ifeq ($(RT3D_MODEL),S4)
CFLAGS += -DRT3D_MODEL_V=128 -DRT3D_MODEL_T=192 -DRT3D_MODEL_M=16
else
$(error RT3D_MODEL must be S0, S1, S2, S3, or S4)
endif
CFLAGS += -DRT3D_ASSET_ID=\"$(RT3D_MODEL)\"
ifeq ($(BENCH_MODE),CPU_ONLY)
CFLAGS += -DRT3D_MODE_CPU_ONLY
else ifeq ($(BENCH_MODE),CPU_MATMUL)
CFLAGS += -DRT3D_MODE_CPU_MATMUL
else ifeq ($(BENCH_MODE),SCENE_CONTROLLER)
CFLAGS += -DRT3D_MODE_SCENE_CONTROLLER
else
$(error BENCH_MODE must be CPU_ONLY, CPU_MATMUL, or SCENE_CONTROLLER)
endif

CFLAGS += -O2 -g -DRTThread -DRT_USING_IDLE_HOOK
C_SRCS := ./main.c ./rt_3d.c ./board.c ./rt3d_metrics.c ../../bsp/drivers/scene_ctrl_wait.c
C_SRCS += $(wildcard ../sk_os/src/*.c)
C_SRCS += $(wildcard ../sk_os/libcpu/loongarch32r/common/*.c)
C_SRCS += $(wildcard ../sk_os/libcpu/loongarch32r/OpenLA500/*.c)
C_SRCS += $(wildcard ../sk_os/components/finsh/*.c)
ASM_SRCS := $(wildcard ../sk_os/libcpu/loongarch32r/common/*.S \
                    ../sk_os/libcpu/loongarch32r/OpenLA500/*.S)
INCLUDES := -I./ -I../sk_os -I../sk_os/include \
            -I../sk_os/libcpu/loongarch32r/common \
            -I../sk_os/libcpu/loongarch32r/OpenLA500 \
            -I../sk_os/components/finsh \
            -I$(COMMON_DIR)/include
OBJDIR = obj
COMMON_DIR = ../../bsp
GCC_DIR = ../../../toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0
PICOLIBC_DIR = ../../../toolchains/picolibc
include ../../bsp/common.mk
# The lightweight SoC CPU used by the Verilator integration does not
# implement the cache-maintenance CACOP startup sequence; keep this image
# uncached so reset reaches the RT-Thread scheduler in simulation.
RT3D_SIMULATION ?= 0
ifeq ($(RT3D_SIMULATION),1)
CFLAGS += -Dhas_cache=0
endif
