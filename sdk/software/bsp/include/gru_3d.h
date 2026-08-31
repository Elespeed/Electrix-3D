#ifndef GRU_3D_H
#define GRU_3D_H

#include "gru.h"

typedef struct {
    S32 x;
    S32 y;
    S32 z;
    S32 w;
} gru_vec4_q16_16_t;

typedef struct {
    S16 m[4][4];
} gru_mat4_q2_14_t;

typedef struct {
    S16 x;
    S16 y;
    U16 z;
    U8  valid;
} gru_screen_vertex_t;

typedef struct {
    const gru_vec4_q16_16_t *vertices;
    U32 vertex_count;
    const U8 *indices;
    U32 index_count;
} gru_mesh_view_t;

typedef enum {
    GRU_3D_VERTEX_FORMAT_XYZW_Q16_16 = 0
} gru_vertex_format_t;

typedef struct {
    const U8 *base;
    U32 stride_bytes;
    U32 vertex_count;
    U8  vertex_format;
} gru_vertex_buffer_view_t;

typedef struct {
    const U8 *base;
    U32 index_count;
} gru_index_buffer_view_t;

#define GRU_3D_Q16_ONE   ((S32)0x00010000)
#define GRU_3D_Q14_ONE   ((S16)0x4000)

void gru_3d_mat4_identity(gru_mat4_q2_14_t *m);
void gru_3d_project_vertex(
    const gru_mat4_q2_14_t *mvp,
    const gru_vec4_q16_16_t *in_vertex,
    U16 viewport_w,
    U16 viewport_h,
    gru_screen_vertex_t *out_vertex
);
void gru_3d_draw_indexed_wireframe(
    const gru_mesh_view_t *mesh,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    U8 color_idx
);
void gru_3d_draw_indexed_flat(
    const gru_mesh_view_t *mesh,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    const U8 *face_color_idx
);
void gru_3d_draw_arrays_flat_buffer(
    const gru_vertex_buffer_view_t *vb,
    U32 first_vertex,
    U32 vertex_count,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    const U8 *face_color_idx
);
void gru_3d_draw_indexed_flat_buffer(
    const gru_vertex_buffer_view_t *vb,
    const gru_index_buffer_view_t *ib,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    const U8 *face_color_idx
);

#endif
