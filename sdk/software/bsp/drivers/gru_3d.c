#include "gru_3d.h"

static U32 gru_3d_read_le32(const U8 *p)
{
    return ((U32)p[0]) |
           ((U32)p[1] << 8) |
           ((U32)p[2] << 16) |
           ((U32)p[3] << 24);
}

static U8 gru_3d_fetch_vertex_buffer(
    const gru_vertex_buffer_view_t *vb,
    U32 vertex_index,
    gru_vec4_q16_16_t *out_vertex
)
{
    const U8 *p;

    if ((vb == 0) || (out_vertex == 0) || (vb->base == 0)) {
        return 0u;
    }
    if ((vb->vertex_format != GRU_3D_VERTEX_FORMAT_XYZW_Q16_16) ||
        (vb->stride_bytes < 16u) ||
        (vertex_index >= vb->vertex_count)) {
        return 0u;
    }

    p = vb->base + (vertex_index * vb->stride_bytes);
    out_vertex->x = (S32)gru_3d_read_le32(&p[0]);
    out_vertex->y = (S32)gru_3d_read_le32(&p[4]);
    out_vertex->z = (S32)gru_3d_read_le32(&p[8]);
    out_vertex->w = (S32)gru_3d_read_le32(&p[12]);
    return 1u;
}

static S32 gru_3d_mul_q16_q14(S32 a_q16_16, S16 b_q2_14)
{
    S64 prod;

    prod = (S64)a_q16_16 * (S64)b_q2_14;
    return (S32)(prod >> 14);
}

static S32 gru_3d_dot4(
    const S16 row[4],
    const gru_vec4_q16_16_t *v
)
{
    return gru_3d_mul_q16_q14(v->x, row[0]) +
           gru_3d_mul_q16_q14(v->y, row[1]) +
           gru_3d_mul_q16_q14(v->z, row[2]) +
           gru_3d_mul_q16_q14(v->w, row[3]);
}

static S32 gru_3d_clamp_s32(S32 value, S32 lo, S32 hi)
{
    if (value < lo) {
        return lo;
    }
    if (value > hi) {
        return hi;
    }
    return value;
}

void gru_3d_mat4_identity(gru_mat4_q2_14_t *m)
{
    int r;
    int c;

    if (m == 0) {
        return;
    }

    for (r = 0; r < 4; r++) {
        for (c = 0; c < 4; c++) {
            m->m[r][c] = (r == c) ? GRU_3D_Q14_ONE : 0;
        }
    }
}

void gru_3d_project_vertex(
    const gru_mat4_q2_14_t *mvp,
    const gru_vec4_q16_16_t *in_vertex,
    U16 viewport_w,
    U16 viewport_h,
    gru_screen_vertex_t *out_vertex
)
{
    gru_vec4_q16_16_t clip;
    S64 ndc_x;
    S64 ndc_y;
    S64 ndc_z;
    S32 sx;
    S32 sy;
    S32 sz;

    if ((mvp == 0) || (in_vertex == 0) || (out_vertex == 0)) {
        return;
    }

    clip.x = gru_3d_dot4(mvp->m[0], in_vertex);
    clip.y = gru_3d_dot4(mvp->m[1], in_vertex);
    clip.z = gru_3d_dot4(mvp->m[2], in_vertex);
    clip.w = gru_3d_dot4(mvp->m[3], in_vertex);

    if (clip.w <= 0) {
        out_vertex->valid = 0u;
        out_vertex->x = 0;
        out_vertex->y = 0;
        out_vertex->z = 0u;
        return;
    }

    ndc_x = ((S64)clip.x << 16) / clip.w;
    ndc_y = ((S64)clip.y << 16) / clip.w;
    ndc_z = ((S64)clip.z << 16) / clip.w;

    sx = (S32)((((ndc_x + GRU_3D_Q16_ONE) * viewport_w) >> 1) >> 16);
    sy = (S32)((((GRU_3D_Q16_ONE - ndc_y) * viewport_h) >> 1) >> 16);
    sz = (S32)((ndc_z + GRU_3D_Q16_ONE) >> 1);

    out_vertex->valid = 1u;
    out_vertex->x = (S16)gru_3d_clamp_s32(sx, -32768, 32767);
    out_vertex->y = (S16)gru_3d_clamp_s32(sy, -32768, 32767);
    out_vertex->z = (U16)gru_3d_clamp_s32(sz >> 16, 0, 65535);
}

void gru_3d_draw_indexed_wireframe(
    const gru_mesh_view_t *mesh,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    U8 color_idx
)
{
    gru_screen_vertex_t sv[64];
    U32 i;

    if ((mesh == 0) || (mvp == 0) || (mesh->vertices == 0) || (mesh->indices == 0)) {
        return;
    }
    if ((mesh->vertex_count > 64u) || ((mesh->index_count & 1u) != 0u)) {
        return;
    }

    for (i = 0; i < mesh->vertex_count; i++) {
        gru_3d_project_vertex(mvp, &mesh->vertices[i], viewport_w, viewport_h, &sv[i]);
    }

    for (i = 0; i < mesh->index_count; i += 2u) {
        U8 i0 = mesh->indices[i];
        U8 i1 = mesh->indices[i + 1u];
        if ((i0 >= mesh->vertex_count) || (i1 >= mesh->vertex_count)) {
            continue;
        }
        if (sv[i0].valid && sv[i1].valid) {
            gru_draw_line((U16)sv[i0].x, (U16)sv[i0].y, (U16)sv[i1].x, (U16)sv[i1].y, color_idx);
        }
    }
}

void gru_3d_draw_indexed_flat(
    const gru_mesh_view_t *mesh,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    const U8 *face_color_idx
)
{
    gru_screen_vertex_t sv[64];
    U32 i;
    U32 face_id;

    if ((mesh == 0) || (mvp == 0) || (mesh->vertices == 0) || (mesh->indices == 0)) {
        return;
    }
    if ((mesh->vertex_count > 64u) || ((mesh->index_count % 3u) != 0u)) {
        return;
    }

    for (i = 0; i < mesh->vertex_count; i++) {
        gru_3d_project_vertex(mvp, &mesh->vertices[i], viewport_w, viewport_h, &sv[i]);
    }

    for (i = 0, face_id = 0; i < mesh->index_count; i += 3u, face_id++) {
        U8 i0 = mesh->indices[i];
        U8 i1 = mesh->indices[i + 1u];
        U8 i2 = mesh->indices[i + 2u];
        U8 color_idx = (face_color_idx != 0) ? face_color_idx[face_id] : 1u;
        if ((i0 >= mesh->vertex_count) || (i1 >= mesh->vertex_count) || (i2 >= mesh->vertex_count)) {
            continue;
        }
        if (sv[i0].valid && sv[i1].valid && sv[i2].valid) {
            gru_triangle_z(
                sv[i0].x, sv[i0].y, sv[i0].z,
                sv[i1].x, sv[i1].y, sv[i1].z,
                sv[i2].x, sv[i2].y, sv[i2].z,
                color_idx
            );
        }
    }
}

void gru_3d_draw_arrays_flat_buffer(
    const gru_vertex_buffer_view_t *vb,
    U32 first_vertex,
    U32 vertex_count,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    const U8 *face_color_idx
)
{
    gru_screen_vertex_t sv0;
    gru_screen_vertex_t sv1;
    gru_screen_vertex_t sv2;
    gru_vec4_q16_16_t v0;
    gru_vec4_q16_16_t v1;
    gru_vec4_q16_16_t v2;
    U32 tri_idx;

    if ((vb == 0) || (mvp == 0) || (vb->base == 0)) {
        return;
    }

    for (tri_idx = 0; tri_idx + 2u < vertex_count; tri_idx += 3u) {
        U32 i0 = first_vertex + tri_idx + 0u;
        U32 i1 = first_vertex + tri_idx + 1u;
        U32 i2 = first_vertex + tri_idx + 2u;
        U8 color_idx = (face_color_idx != 0) ? face_color_idx[tri_idx / 3u] : 1u;

        if (!gru_3d_fetch_vertex_buffer(vb, i0, &v0) ||
            !gru_3d_fetch_vertex_buffer(vb, i1, &v1) ||
            !gru_3d_fetch_vertex_buffer(vb, i2, &v2)) {
            continue;
        }

        gru_3d_project_vertex(mvp, &v0, viewport_w, viewport_h, &sv0);
        gru_3d_project_vertex(mvp, &v1, viewport_w, viewport_h, &sv1);
        gru_3d_project_vertex(mvp, &v2, viewport_w, viewport_h, &sv2);
        if (sv0.valid && sv1.valid && sv2.valid) {
            gru_triangle_z(
                sv0.x, sv0.y, sv0.z,
                sv1.x, sv1.y, sv1.z,
                sv2.x, sv2.y, sv2.z,
                color_idx
            );
        }
    }
}

void gru_3d_draw_indexed_flat_buffer(
    const gru_vertex_buffer_view_t *vb,
    const gru_index_buffer_view_t *ib,
    const gru_mat4_q2_14_t *mvp,
    U16 viewport_w,
    U16 viewport_h,
    const U8 *face_color_idx
)
{
    gru_screen_vertex_t sv0;
    gru_screen_vertex_t sv1;
    gru_screen_vertex_t sv2;
    gru_vec4_q16_16_t v0;
    gru_vec4_q16_16_t v1;
    gru_vec4_q16_16_t v2;
    U32 tri_idx;

    if ((vb == 0) || (ib == 0) || (mvp == 0) || (vb->base == 0) || (ib->base == 0)) {
        return;
    }

    for (tri_idx = 0; tri_idx + 2u < ib->index_count; tri_idx += 3u) {
        U32 i0 = ib->base[tri_idx + 0u];
        U32 i1 = ib->base[tri_idx + 1u];
        U32 i2 = ib->base[tri_idx + 2u];
        U8 color_idx = (face_color_idx != 0) ? face_color_idx[tri_idx / 3u] : 1u;

        if (!gru_3d_fetch_vertex_buffer(vb, i0, &v0) ||
            !gru_3d_fetch_vertex_buffer(vb, i1, &v1) ||
            !gru_3d_fetch_vertex_buffer(vb, i2, &v2)) {
            continue;
        }

        gru_3d_project_vertex(mvp, &v0, viewport_w, viewport_h, &sv0);
        gru_3d_project_vertex(mvp, &v1, viewport_w, viewport_h, &sv1);
        gru_3d_project_vertex(mvp, &v2, viewport_w, viewport_h, &sv2);
        if (sv0.valid && sv1.valid && sv2.valid) {
            gru_triangle_z(
                sv0.x, sv0.y, sv0.z,
                sv1.x, sv1.y, sv1.z,
                sv2.x, sv2.y, sv2.z,
                color_idx
            );
        }
    }
}
