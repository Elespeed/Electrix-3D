#ifndef SOC_CONFIG_COMPLEX_H
#define SOC_CONFIG_COMPLEX_H

#include "soc_config_common.h"

#define SOC_FB_WIDTH         800u
#define SOC_FB_HEIGHT        480u
#define SOC_FB_STRIDE_BYTES  1600u
#define SOC_FB_BASE_B        (SOC_FB_BASE_A + (SOC_FB_WIDTH * SOC_FB_HEIGHT * SOC_FB_PIXEL_BYTES))

#endif
