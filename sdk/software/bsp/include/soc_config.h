#ifndef SOC_CONFIG_H
#define SOC_CONFIG_H

/*
 * Select the software graphics-memory profile with the same CONFIG_PROFILE
 * used by the simulators.  Remote is intentionally addressless because its
 * display storage belongs privately to SketchBook BRAM; other profiles retain
 * their legacy SOC_FB_* interfaces.
 */
#if defined(SOC_CONFIG_PROFILE_BLADE2X2SIM)
#include "soc_config_blade2x2sim.h"
#elif defined(SOC_CONFIG_PROFILE_BLADE2X2)
#include "soc_config_blade2x2.h"
#elif defined(SOC_CONFIG_PROFILE_REMOTE)
#include "soc_config_remote.h"
#elif defined(SOC_CONFIG_PROFILE_SIM)
#include "soc_config_sim.h"
#elif defined(SOC_CONFIG_PROFILE_SIM320X240)
#include "soc_config_sim320x240.h"
#else
#include "soc_config_complex.h"
#endif

#endif
