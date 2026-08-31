#ifndef MATMUL_H
#define MATMUL_H

#include "common_func.h"

#define MATMUL_BASE_ADDR          0xbf500000u

#define MATMUL_CTRL_START_MASK    0x1u
#define MATMUL_CTRL_SOFT_RST_MASK 0x2u

#define MATMUL_STATUS_BUSY        0x1u
#define MATMUL_STATUS_DONE        0x2u
#define MATMUL_STATUS_ERROR       0x4u

void matmul_soft_reset(void);
void matmul_load_a_word(U32 index, U32 value);
void matmul_load_b_word(U32 index, U32 value);
void matmul_start(void);
U32 matmul_get_status(void);
U32 matmul_wait_done(void);
U32 matmul_read_c_word(U32 index);

#endif
