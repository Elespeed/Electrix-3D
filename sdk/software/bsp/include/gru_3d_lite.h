#ifndef GRU_3D_LITE_H
#define GRU_3D_LITE_H

#include "gru.h"

/* ==========================================================================
 *  Phase 3x0 -- CPU low-poly 3D frontend for the GRU Lite engine.
 *
 *  See docs/3dlite/phase3x0_CPU前端与Demo开发.md.  Hard constraints honoured:
 *    - Orthographic projection only.
 *    - NO 64-bit division (rotations, projection and shading are multiply +
 *      arithmetic-shift only; the painter sort compares raw vertex-Z sums so
 *      even the /3 "average Z" is never computed).
 *    - Each unique mesh vertex is transformed exactly once per frame.
 *    - Back-face cull via the screen-space signed-area cross product.
 *    - Painter sort by summed vertex Z, far-to-near.
 *    - Exactly one Fence + one idle-wait per rendered frame.
 *
 *  The Lite engine accepts TRIANGLE_GOURAUD and rejects the depth opcodes
 *  (CLEAR_DEPTH / TRIANGLE_Z raise cfg_error at dispatch), so this frontend
 *  submits Gouraud triangles exclusively and never touches the depth path.
 * ========================================================================== */

/* Angle representation: 8-bit "brads" -- 256 brads == 360 degrees. */
#define GRU_LITE_BRADS_FULL  256u
#define GRU_LITE_BRADS_90    64u
#define GRU_LITE_Q15_ONE     32767

/* Model-space vertex in Q8 fixed point (256 == 1.0 model unit).  A unit cube
 * is therefore stored as (+/-256, +/-256, +/-256); one model unit maps to
 * `scale` screen pixels under orthographic projection. */
typedef struct {
    S16 x;
    S16 y;
    S16 z;
} gru_lite_vec3_t;

/* One triangle face.  `normal` is the outward unit normal in model space with
 * components in {-1, 0, +1} (axis-aligned for a cube) used for directional
 * shading.  `base_rgb565` is the face base colour, modulated by lighting. */
typedef struct {
    U8  i0;
    U8  i1;
    U8  i2;
    gru_lite_vec3_t normal;
    U16 base_rgb565;
} gru_lite_face_t;

typedef struct {
    const gru_lite_vec3_t *vertices;
    U16 vertex_count;
    const gru_lite_face_t *faces;
    U16 face_count;
} gru_lite_mesh_t;

/* Inclusive screen-space rectangle.  `valid == 0` means "empty / no region". */
typedef struct {
    S16 x0;
    S16 y0;
    S16 x1;
    S16 y1;
    U8  valid;
} gru_lite_rect_t;

typedef struct {
    U16 total_faces;          /* mesh faces considered this frame */
    U16 visible_tris;         /* front-facing triangles actually submitted */
    gru_lite_rect_t dirty;    /* this frame's object bbox (the dirtied region) */
    gru_lite_rect_t cleared;  /* region actually erased (union of prev + dirty) */
    U32 gru_status;           /* GRU status after the single fence + idle wait */
} gru_lite_frame_stats_t;

/* Fixed-point trig helpers (exposed for tests / reuse).
 * 256 brads == 2*pi; output is signed Q15 in [-32767, +32767]. */
S16 gru_lite_sin_q15(U8 brads);
S16 gru_lite_cos_q15(U8 brads);

/* Render one animation frame into the GRU back buffer.
 *
 *   mesh        : vertex + triangle-face mesh (e.g. a unit cube).
 *   yaw_brads   : per-frame yaw angle (rotation about model Y).
 *   pitch_brads : pitch angle (rotation about model X); typically a fixed tilt.
 *   cx, cy      : projection centre in screen pixels.
 *   scale       : screen pixels per model unit (Q8 -> px).
 *   bg_color_idx: palette index used to erase the dirty region.
 *   screen_w/h  : framebuffer extents (for dirty-rect clamping).
 *   prev_dirty  : this back-buffer's previous object bbox, or NULL if none.
 *   stats       : filled with frame statistics (may be NULL).
 *
 * The caller is responsible for pointing the GRU at the intended back buffer
 * (via gfx_swap / gru_config_fb) before calling.  This function erases the
 * union of `prev_dirty` and the new object bbox (local refresh -- never a
 * full-screen clear), then culls, painter-sorts and shade-submits the visible
 * Gouraud triangles, issues one Fence and waits once for idle.  Returns the
 * post-fence GRU status. */
U32 gru_lite_render_frame(
    const gru_lite_mesh_t *mesh,
    U8 yaw_brads,
    U8 pitch_brads,
    U16 cx,
    U16 cy,
    U16 scale,
    U8 bg_color_idx,
    U16 screen_w,
    U16 screen_h,
    const gru_lite_rect_t *prev_dirty,
    gru_lite_frame_stats_t *stats
);

#endif /* GRU_3D_LITE_H */
