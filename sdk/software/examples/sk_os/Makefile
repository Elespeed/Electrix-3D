TARGET = sk_os
RTTHREAD_APP = 1

CFLAGS += -O3 -g

CFLAGS += -DRTThread

C_SRCS := $(wildcard ./*.c )
# `common.mk` already builds `$(COMMON_DIR)/drivers/led.c`; avoid duplicate symbols.
C_SRCS := $(filter-out ./led.c ./blade_os.c ./terminal_display.c,$(C_SRCS))

C_SRCS += $(wildcard	./src/*.c \
						./libcpu/loongarch32r/common/*.c \
						./libcpu/loongarch32r/OpenLA500/*.c \
						./components/finsh/*.c ) 

ASM_SRCS := $(wildcard	./libcpu/loongarch32r/common/*.S \
						./libcpu/loongarch32r/OpenLA500/*.S ) 

INCLUDES := -I. \
			-I./include \
			-I./include/libc \
			-I./libcpu/loongarch32r/common \
			-I./libcpu/loongarch32r/OpenLA500 \
			-I./components/finsh \
			-I$(COMMON_DIR)/include

OBJDIR = obj
COMMON_DIR = ../../bsp
GCC_DIR=../../../toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0
PICOLIBC_DIR=../../../toolchains/picolibc
include ../../bsp/common.mk
