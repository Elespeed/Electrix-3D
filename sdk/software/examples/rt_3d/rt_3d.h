#ifndef RT_3D_BENCHMARK_H
#define RT_3D_BENCHMARK_H

#include "common_func.h"

#ifndef RT3D_WARMUP_FRAMES
#define RT3D_WARMUP_FRAMES 30u
#endif
#ifndef RT3D_FORMAL_FRAMES
#define RT3D_FORMAL_FRAMES 300u
#endif
#ifndef RT3D_REPETITIONS
#define RT3D_REPETITIONS 5u
#endif
#define RT3D_TRAJECTORY_LENGTH 16u
#define RT3D_MODEL_MAGIC 0x534b3344u /* SK3D, little endian */

typedef enum {
    RT3D_BACKEND_CPU_ONLY = 0,
    RT3D_BACKEND_CPU_MATMUL = 1,
    RT3D_BACKEND_SCENE_CONTROLLER = 2
} rt3d_backend_kind_t;

typedef struct {
    U16 vertex_count;
    U16 triangle_count;
    U8 mesh_count;
    U8 reserved;
} rt3d_model_t;

typedef struct {
    U32 frame;
    U32 repetition;
    U32 input_triangles;
    U32 culled_triangles;
    U32 output_triangles;
    U32 command_count;
} rt3d_frame_result_t;

/* The parser is shared by all three backends; the benchmark uses a fixed blob. */
int rt3d_model_parse(const U8 *blob, U32 bytes, rt3d_model_t *out);
U16 rt3d_sin_q14(U8 phase);
U16 rt3d_cos_q14(U8 phase);
U8 rt3d_trajectory_phase(U32 frame);
void rt3d_run(void);
const char *rt3d_backend_name(void);

#endif
