#ifndef SOC_CONFIG_REMOTE_H
#define SOC_CONFIG_REMOTE_H

/*
 * Remote displays are driven solely by SketchBook's command MMIO window.
 * Its double-buffered 400x300 RGB565 storage is private BRAM, so this profile
 * intentionally exports no SOC_FB_* address, geometry, stride, or ExtRAM
 * reservation API.  Use sketchbook.h / SKETCHBOOK_BASE_ADDR instead.
 */

#endif
