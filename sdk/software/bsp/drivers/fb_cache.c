#include "fb_cache.h"

#define FB_CACHE_LINE_SIZE 16u

void fb_cache_flush_range(U32 base, U32 bytes)
{
    unsigned long start;
    unsigned long end;
    unsigned long addr;

    if (bytes == 0u) {
        return;
    }

    start = ((unsigned long)base) & ~((unsigned long)FB_CACHE_LINE_SIZE - 1u);
    end = (unsigned long)base + (unsigned long)bytes;
    end = (end + FB_CACHE_LINE_SIZE - 1u) & ~((unsigned long)FB_CACHE_LINE_SIZE - 1u);

    __asm__ volatile("" : : : "memory");
    for (addr = start; addr < end; addr += FB_CACHE_LINE_SIZE) {
        flush_dcache_line(addr);
    }
    __asm__ volatile("" : : : "memory");
}

void fb_cache_flush_frame(U32 fb_base, U16 width, U16 height, U32 stride_bytes)
{
    U32 row_bytes;
    U32 total_bytes;

    row_bytes = stride_bytes;
    if (row_bytes == 0u) {
        row_bytes = (U32)width * 2u;
    }

    total_bytes = row_bytes * (U32)height;
    fb_cache_flush_range(fb_base, total_bytes);
}

void fb_cache_flush_rect(U32 fb_base,
                         U16 x,
                         U16 y,
                         U16 width,
                         U16 height,
                         U32 stride_bytes)
{
    U32 row;
    U32 row_bytes;
    U32 row_stride;
    U32 row_base;

    if ((width == 0u) || (height == 0u)) {
        return;
    }

    row_bytes = (U32)width * 2u;
    row_stride = stride_bytes;
    if (row_stride == 0u) {
        row_stride = row_bytes;
    }

    row_base = fb_base + ((U32)y * row_stride) + ((U32)x * 2u);
    for (row = 0u; row < (U32)height; row++) {
        fb_cache_flush_range(row_base + (row * row_stride), row_bytes);
    }
}
