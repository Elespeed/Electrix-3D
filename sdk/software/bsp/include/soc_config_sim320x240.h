#ifndef SOC_CONFIG_SIM320X240_H
#define SOC_CONFIG_SIM320X240_H

#include "soc_config_common.h"

#define SOC_FB_WIDTH         320u
#define SOC_FB_HEIGHT        240u
#define SOC_FB_STRIDE_BYTES  640u
#define SOC_FB_BASE_B        (SOC_FB_BASE_A + (SOC_FB_WIDTH * SOC_FB_HEIGHT * SOC_FB_PIXEL_BYTES))

#endif
