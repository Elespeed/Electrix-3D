#include "matmul.h"

#define MATMUL_CTRL_REG       (*(volatile U32 *)(MATMUL_BASE_ADDR + 0x00))
#define MATMUL_STATUS_REG     (*(volatile U32 *)(MATMUL_BASE_ADDR + 0x04))
#define MATMUL_A_BASE_REG     (MATMUL_BASE_ADDR + 0x10)
#define MATMUL_B_BASE_REG     (MATMUL_BASE_ADDR + 0x50)
#define MATMUL_C_BASE_REG     (MATMUL_BASE_ADDR + 0x90)

static volatile U32 *matmul_word_ptr(U32 base, U32 index)
{
    return (volatile U32 *)(base + (index << 2));
}

void matmul_soft_reset(void)
{
    MATMUL_CTRL_REG = MATMUL_CTRL_SOFT_RST_MASK;
    __asm__ volatile("" : : : "memory");
    MATMUL_CTRL_REG = 0u;
    __asm__ volatile("" : : : "memory");
}

void matmul_load_a_word(U32 index, U32 value)
{
    *matmul_word_ptr(MATMUL_A_BASE_REG, index) = value;
}

void matmul_load_b_word(U32 index, U32 value)
{
    *matmul_word_ptr(MATMUL_B_BASE_REG, index) = value;
}

void matmul_start(void)
{
    MATMUL_CTRL_REG = MATMUL_CTRL_START_MASK;
    __asm__ volatile("" : : : "memory");
    MATMUL_CTRL_REG = 0u;
    __asm__ volatile("" : : : "memory");
}

U32 matmul_get_status(void)
{
    return MATMUL_STATUS_REG;
}

U32 matmul_wait_done(void)
{
    U32 status;
    do {
        status = matmul_get_status();
    } while ((status & (MATMUL_STATUS_DONE | MATMUL_STATUS_ERROR)) == 0u);
    return status;
}

U32 matmul_read_c_word(U32 index)
{
    return *matmul_word_ptr(MATMUL_C_BASE_REG, index);
}
