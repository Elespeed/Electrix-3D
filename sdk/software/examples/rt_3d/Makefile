TARGET = rt_3d
RTTHREAD_APP = 1

# Select exactly one reproducible benchmark backend at compile time.
BENCH_MODE ?= CPU_MATMUL
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
C_SRCS := ./main.c ./rt_3d.c ./board.c ./rt3d_metrics.c
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
