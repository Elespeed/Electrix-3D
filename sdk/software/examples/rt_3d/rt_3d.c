#include <stdio.h>
#include <rtthread.h>
#include "rt_3d.h"
#include "scene_ctrl.h"
#include "sketchbook.h"
#include "matmul.h"
#include "rt3d_metrics.h"
#include "scene_ctrl_wait.h"

#if !defined(RT3D_MODE_CPU_ONLY) && !defined(RT3D_MODE_CPU_MATMUL) && !defined(RT3D_MODE_SCENE_CONTROLLER)
#error "Select one RT3D_MODE_* backend"
#endif

#define RT3D_MODEL_BASE 0x1c400000u
#define RT3D_CLEAR_COLOR 0x18u
#define RT3D_MAX_VERTICES 128u
#define RT3D_MAX_TRIANGLES 192u
#define Q8_ONE 256
#ifndef RT3D_ASSET_ID
#define RT3D_ASSET_ID "UNFROZEN"
#endif
#ifndef RT3D_ASSET_SHA256
#define RT3D_ASSET_SHA256 "UNFROZEN"
#endif
#ifndef RT3D_CONFIG_HASH
#define RT3D_CONFIG_HASH "UNFROZEN"
#endif
#ifndef RT3D_MODEL_V
#define RT3D_MODEL_V 0u
#define RT3D_MODEL_T 0u
#define RT3D_MODEL_M 0u
#endif

typedef struct { S32 x, y, z; } vec_t;
typedef struct { S16 x, y; S32 z; } screen_t;
typedef struct { U8 i0, i1, i2, color, source; S32 depth; } tri_t;
static vec_t transformed[RT3D_MAX_VERTICES];
static screen_t screen_vertices[RT3D_MAX_VERTICES];
static tri_t visible_triangles[RT3D_MAX_TRIANGLES];
static sketchbook_t display;
static const S16 sin_q8[16] = {0,98,181,237,256,237,181,98,0,-98,-181,-237,-256,-237,-181,-98};

static volatile const U32 *model_words(void) { return (volatile const U32 *)RT3D_MODEL_BASE; }
static S32 signed16(U32 value, U8 high) { return (S32)(S16)(high ? value >> 16 : value); }
static U8 phase_of(U32 frame) { return (U8)(frame & 15u); }
U16 rt3d_sin_q14(U8 phase) { return (U16)((S32)sin_q8[phase & 15u] << 6); }
U16 rt3d_cos_q14(U8 phase) { return rt3d_sin_q14((U8)(phase + 4u)); }
U8 rt3d_trajectory_phase(U32 frame) { return phase_of(frame); }

int rt3d_model_parse(const U8 *ignored, U32 bytes, rt3d_model_t *out)
{
    const volatile U32 *words = model_words();
    U32 format;
    (void)ignored;
    if (!out || bytes < 16u || words[0] != RT3D_MODEL_MAGIC) return 0;
    format = words[3];
    out->vertex_count = (U16)words[1]; out->triangle_count = (U16)words[2];
    out->mesh_count = (U8)(format >> 8); out->reserved = (U8)format;
    return out->reserved == 4u && out->vertex_count > 0u && out->vertex_count <= RT3D_MAX_VERTICES &&
           out->triangle_count > 0u && out->triangle_count <= RT3D_MAX_TRIANGLES && out->mesh_count > 0u;
}

const char *rt3d_backend_name(void)
{
#if defined(RT3D_MODE_CPU_ONLY)
    return "CPU_ONLY";
#elif defined(RT3D_MODE_CPU_MATMUL)
    return "CPU_MATMUL";
#else
    return "SCENE_CONTROLLER";
#endif
}

static void make_matrix(U8 phase, S32 m[4][4])
{
    U32 r, c; S32 s = sin_q8[phase], co = sin_q8[(phase + 4u) & 15u];
    for (r = 0; r < 4u; ++r) for (c = 0; c < 4u; ++c) m[r][c] = 0;
    m[0][0] = co; m[0][2] = s; m[1][1] = Q8_ONE; m[2][0] = -s; m[2][2] = co; m[3][3] = Q8_ONE;
}

static void transform_cpu(const rt3d_model_t *model, const S32 m[4][4])
{
    const volatile U32 *words = model_words();
    U32 base = 4u + 4u * model->mesh_count, i, r, k;
    for (i = 0; i < model->vertex_count; ++i) {
        U32 xy = words[base + i * 2u]; S32 in[4];
        in[0] = signed16(xy, 1u); in[1] = signed16(xy, 0u); in[2] = signed16(words[base + i * 2u + 1u], 0u); in[3] = Q8_ONE;
        for (r = 0; r < 3u; ++r) {
            long long acc = 0; for (k = 0; k < 4u; ++k) acc += (long long)m[r][k] * in[k];
            if (r == 0u) transformed[i].x = (S32)(acc >> 8); else if (r == 1u) transformed[i].y = (S32)(acc >> 8); else transformed[i].z = (S32)(acc >> 8);
        }
    }
}

static U8 transform_matmul(const rt3d_model_t *model, const S32 m[4][4])
{
    const volatile U32 *words = model_words();
    U32 base = 4u + 4u * model->mesh_count, batch, row, col;
    matmul_set_mode_fixed_q8_8();
    for (row = 0; row < 4u; ++row) for (col = 0; col < 4u; ++col) matmul_load_a_word(row * 4u + col, (U32)m[row][col]);
    for (batch = 0; batch < model->vertex_count; batch += 4u) {
        for (col = 0; col < 4u; ++col) {
            U32 i = batch + col; S32 in[4] = {0, 0, 0, 0};
            if (i < model->vertex_count) { U32 xy = words[base + i * 2u]; in[0] = signed16(xy, 1u); in[1] = signed16(xy, 0u); in[2] = signed16(words[base + i * 2u + 1u], 0u); in[3] = Q8_ONE; }
            for (row = 0; row < 4u; ++row) matmul_load_b_word(row * 4u + col, (U32)in[row]);
        }
        matmul_start();
        if (matmul_wait_done() & MATMUL_STATUS_ERROR) return 0u;
        for (col = 0; col < 4u && batch + col < model->vertex_count; ++col) {
            transformed[batch + col].x = (S32)matmul_read_fixed_c_word(col);
            transformed[batch + col].y = (S32)matmul_read_fixed_c_word(4u + col);
            transformed[batch + col].z = (S32)matmul_read_fixed_c_word(8u + col);
        }
    }
    return 1u;
}

static U32 build_triangles(const rt3d_model_t *model)
{
    const volatile U32 *words = model_words();
    U32 vertex_base = 4u + 4u * model->mesh_count, triangle_base = vertex_base + 2u * model->vertex_count, i, count = 0;
    for (i = 0; i < model->vertex_count; ++i) { screen_vertices[i].x = (S16)(200 + (transformed[i].x >> 8)); screen_vertices[i].y = (S16)(150 - (transformed[i].y >> 8)); screen_vertices[i].z = transformed[i].z; }
    for (i = 0; i < model->triangle_count; ++i) {
        U32 packed = words[triangle_base + 2u * i]; U8 i0 = (U8)packed, i1 = (U8)(packed >> 8), i2 = (U8)(packed >> 16); S32 area;
        if (i0 >= model->vertex_count || i1 >= model->vertex_count || i2 >= model->vertex_count) continue;
        area = ((S32)screen_vertices[i1].x - screen_vertices[i0].x) * ((S32)screen_vertices[i2].y - screen_vertices[i0].y) - ((S32)screen_vertices[i1].y - screen_vertices[i0].y) * ((S32)screen_vertices[i2].x - screen_vertices[i0].x);
        if (area >= 0 || count == RT3D_MAX_TRIANGLES) continue;
        /* Preserve the SK3D material byte exactly.  The Scene Controller
         * consumes this byte without the historical CPU-side `| 1` tweak,
         * so forcing the low bit here makes the reference framebuffer differ
         * even for identical geometry. */
        visible_triangles[count].i0 = i0; visible_triangles[count].i1 = i1; visible_triangles[count].i2 = i2; visible_triangles[count].color = (U8)words[triangle_base + 2u * i + 1u]; visible_triangles[count].source = (U8)i; visible_triangles[count].depth = screen_vertices[i0].z + screen_vertices[i1].z + screen_vertices[i2].z; ++count;
    }
    return count;
}

static void sort_triangles(U32 count)
{
    U32 i, j;
    /* Match scene_ctrl_engine's SORT_COMPARE exactly: hold sort_i fixed,
     * scan later records, and immediately exchange on a strictly smaller
     * depth.  This intentionally differs from a stable sort for equal-depth
     * triangles, whose painter order is part of the rendered result. */
    for (i = 0u; i + 1u < count; ++i) {
        for (j = i + 1u; j < count; ++j) {
            if (visible_triangles[j].depth < visible_triangles[i].depth) {
                tri_t temp = visible_triangles[i];
                visible_triangles[i] = visible_triangles[j];
                visible_triangles[j] = temp;
            }
        }
    }
}

static U32 command_crc(U8 phase, U32 count)
{
    U32 h = 2166136261u, i; h ^= RT3D_CLEAR_COLOR; h *= 16777619u;
    for (i = 0; i < count; ++i) { h ^= visible_triangles[i].i0; h *= 16777619u; h ^= visible_triangles[i].i1; h *= 16777619u; h ^= visible_triangles[i].i2; h *= 16777619u; h ^= visible_triangles[i].color; h *= 16777619u; }
    h ^= phase; h *= 16777619u; h ^= SKETCHBOOK_CMD_PRESENT; return h * 16777619u;
}

static U32 cpu_frame(U32 frame, const rt3d_model_t *model, rt3d_frame_metrics_t *metrics, U8 *ok)
{
    S32 matrix[4][4]; U32 count, i; make_matrix(phase_of(frame), matrix); *ok = 1u;
    rt3d_stage_begin(metrics, RT3D_STAGE_TRANSFORM);
#if defined(RT3D_MODE_CPU_MATMUL)
    *ok = transform_matmul(model, matrix);
#else
    transform_cpu(model, matrix);
#endif
    rt3d_stage_end(metrics, RT3D_STAGE_TRANSFORM);
    rt3d_stage_begin(metrics, RT3D_STAGE_TRIANGLE_CULL); count = build_triangles(model); rt3d_stage_end(metrics, RT3D_STAGE_TRIANGLE_CULL);
    rt3d_stage_begin(metrics, RT3D_STAGE_PAINTER_SORT); sort_triangles(count); rt3d_stage_end(metrics, RT3D_STAGE_PAINTER_SORT);
    rt3d_stage_begin(metrics, RT3D_STAGE_COMMAND_SUBMIT); sketchbook_clear(&display, RT3D_CLEAR_COLOR);
    for (i = 0; i < count; ++i) { tri_t *t = &visible_triangles[i]; sketchbook_triangle_flat(&display, screen_vertices[t->i0].x, screen_vertices[t->i0].y, screen_vertices[t->i1].x, screen_vertices[t->i1].y, screen_vertices[t->i2].x, screen_vertices[t->i2].y, t->color); }
    sketchbook_present(&display); rt3d_stage_end(metrics, RT3D_STAGE_COMMAND_SUBMIT);
    rt3d_polling_begin(metrics); sketchbook_wait_frame_done(&display); rt3d_polling_end(metrics); return count;
}

static U8 scene_frame(U32 frame, rt3d_frame_metrics_t *metrics)
{
    U32 completed = scene_ctrl_cmd_frame_count(); scene_ctrl_cmd_t cmd = scene_ctrl_cmd_clear(RT3D_CLEAR_COLOR); U8 phase = phase_of(frame), status; U32 start;
    /* Submission is CPU active work.  The subsequent semaphore wait is not;
     * keep the two intervals disjoint so active + blocked are meaningful. */
    rt3d_stage_begin(metrics, RT3D_STAGE_COMMAND_SUBMIT);
    scene_ctrl_wait_prepare(); scene_ctrl_irq_clear(SCENE_CTRL_IRQ_FRAME_DONE | SCENE_CTRL_IRQ_ERROR); scene_ctrl_cmd_push(&cmd); cmd = scene_ctrl_cmd_draw(0u, 0, 0, 0, phase, 0u, 0u, 0x0100u); scene_ctrl_cmd_push(&cmd); cmd = scene_ctrl_cmd_present(); scene_ctrl_cmd_push(&cmd); scene_ctrl_cmd_start_frame();
    rt3d_stage_end(metrics, RT3D_STAGE_COMMAND_SUBMIT);
    /* Keep the IRQ wait observable in the UART transcript.  The SoC smoke TB
       uses these markers to prove that completion took the intended
       interrupt path, rather than merely observing a later JSON record. */
    rt_kprintf("RT3D IRQ WAIT seq=%u\n", frame + 1u);
    start = get_cpu_clock_count(); status = scene_ctrl_wait_irq(completed, RT_WAITING_FOREVER); rt3d_blocked_add(metrics, get_cpu_clock_count() - start);
    rt_kprintf("RT3D IRQ WAKE seq=%u\n", frame + 1u);
    return status;
}

static void rt3d_emit_frame(const rt3d_frame_metrics_t *m,
                            const rt3d_idle_metrics_t *idle,
                            const rt3d_background_metrics_t *bg,
                            const scene_ctrl_perf_t *before,
                            const scene_ctrl_perf_t *after,
                            U32 rep, U32 frame, U32 command_crc, U32 frame_crc, U32 output_count,
                            U32 error)
{
    U32 load=0, txn=0, transform=0, cull=0, sort=0, command=0;
    U32 in=RT3D_MODEL_T, culled=0, out=0;
#if defined(RT3D_MODE_SCENE_CONTROLLER)
    if (before && after) {
        /* The controller clears render-stage and triangle counters at each
         * RENDER/DRAW start.  They are therefore frame-local snapshots, not
         * cumulative counters: subtracting the previous frame would wrap. */
        (void)before;
        transform=after->transform_cycles; cull=after->cull_cycles;
        sort=after->sort_cycles; command=after->command_cycles;
        in=after->input_triangles; culled=after->culled_triangles; out=after->output_triangles;
        /* Model-load counters belong to initialization, outside frame timing. */
        load=0u; txn=0u;
    }
#else
    (void)before; (void)after;
    transform=m->stage_cycles[RT3D_STAGE_TRANSFORM]; cull=m->stage_cycles[RT3D_STAGE_TRIANGLE_CULL];
    sort=m->stage_cycles[RT3D_STAGE_PAINTER_SORT]; command=m->stage_cycles[RT3D_STAGE_COMMAND_SUBMIT];
    out=output_count; culled=RT3D_MODEL_T > out ? RT3D_MODEL_T - out : 0u;
#endif
    /* RT_CONSOLEBUF_SIZE is 128 in the RT-Thread image.  Each fragment below
     * is bounded independently; the host joins them by (rep, frame), and only
     * emits a row after the final CFG fragment has arrived. */
    rt_kprintf("RT3D FRAME mode=%s rep=%u frame=%u err=%u cmd=%08x asset=%s V=%u T=%u M=%u\n", rt3d_backend_name(),rep,frame,error,command_crc,RT3D_ASSET_ID,RT3D_MODEL_V,RT3D_MODEL_T,RT3D_MODEL_M);
    rt_kprintf("RT3D CYC rep=%u frame=%u active=%u polling=%u blocked=%u wall=%u latency_ns=%u\n",rep,frame,m->active_cycles,m->polling_cycles,m->blocked_cycles,m->wall_cycles,m->frame_latency_ns);
    rt_kprintf("RT3D SCENE rep=%u frame=%u load_bytes=%u axi_transactions=%u\n",rep,frame,load,txn);
    rt_kprintf("RT3D STAGE rep=%u frame=%u transform_cycles=%u cull_cycles=%u\n",rep,frame,transform,cull);
    rt_kprintf("RT3D STAGE2 rep=%u frame=%u sort_cycles=%u command_cycles=%u\n",rep,frame,sort,command);
    rt_kprintf("RT3D TRI rep=%u frame=%u input_triangles=%u culled_triangles=%u output_triangles=%u\n",rep,frame,in,culled,out);
    rt_kprintf("RT3D CRC rep=%u frame=%u frame_crc=%08x\n",rep,frame,frame_crc);
    rt_kprintf("RT3D RTOS rep=%u frame=%u idle_rate_permille=%u background_units=%u\n",rep,frame,rt3d_idle_rate_permille(idle),bg->units);
    rt_kprintf("RT3D RATE rep=%u frame=%u background_units_per_second=%u\n",rep,frame,bg->units_per_second);
    rt_kprintf("RT3D HASH rep=%u frame=%u sha=%s\n",rep,frame,RT3D_ASSET_SHA256);
    rt_kprintf("RT3D CFG rep=%u frame=%u cfg=%s\n",rep,frame,RT3D_CONFIG_HASH);
}

void rt3d_run(void)
{
    rt3d_model_t model; rt3d_idle_metrics_t idle; U32 rep, frame;
    if (!rt3d_model_parse(0, 16u, &model)) { rt_kprintf("RT3D INVALID model\n"); return; }
    rt3d_idle_init(&idle); (void)rt_thread_idle_sethook(rt3d_idle_hook); rt3d_background_reset();
#if defined(RT3D_MODE_SCENE_CONTROLLER)
    scene_ctrl_wait_init(); scene_ctrl_cmd_enable(); scene_ctrl_configure(RT3D_MODEL_BASE, 16u + 16u * model.mesh_count + 8u * model.vertex_count + 8u * model.triangle_count); scene_ctrl_set_rotation(0u, 0u, 0u, 0x0100u); scene_ctrl_set_position(200u, 150u, 0u); scene_ctrl_set_render_cfg(SCENE_CTRL_RENDER_CFG_CLEAR_BEFORE | SCENE_CTRL_RENDER_CFG_BACKFACE_CULL | SCENE_CTRL_RENDER_CFG_DEPTH_SORT, RT3D_CLEAR_COLOR); scene_ctrl_load(); while (scene_ctrl_read(SCENE_CTRL_REG_STATUS) & SCENE_CTRL_STATUS_BUSY) {} if (scene_ctrl_read(SCENE_CTRL_REG_STATUS) & SCENE_CTRL_STATUS_ERROR) { rt_kprintf("RT3D INVALID scene_load\n"); return; }
#else
    sketchbook_init(&display, SKETCHBOOK_BASE_ADDR);
#endif
    for (rep = 1u; rep <= RT3D_REPETITIONS; ++rep) {
        for (frame = 0; frame < RT3D_WARMUP_FRAMES; ++frame) {
            rt3d_frame_metrics_t discard;
            U8 ok;
            rt3d_frame_begin(&discard);
#if defined(RT3D_MODE_SCENE_CONTROLLER)
            (void)scene_frame(frame, &discard);
#else
            (void)cpu_frame(frame, &model, &discard, &ok);
#endif
        }
        for (frame = 0; frame < RT3D_FORMAL_FRAMES; ++frame) {
            rt3d_frame_metrics_t metrics; rt3d_background_metrics_t bg; scene_ctrl_perf_t perf_before, perf_after; U32 count, crc; U8 error = 0u, ok = 1u;
            rt3d_frame_begin(&metrics);
#if defined(RT3D_MODE_SCENE_CONTROLLER)
            scene_ctrl_perf_read(&perf_before);
            /* scene_frame() returns the Scene IRQ status.  FRAME_DONE is a
             * successful completion bit, not an error code; only propagate
             * the actual error bit into the compact UART record consumed by
             * the host-side CRC pipeline. */
            error = scene_frame(frame, &metrics) & SCENE_CTRL_IRQ_ERROR; count = scene_ctrl_read(SCENE_CTRL_REG_PERF_OUTPUT_TRIANGLES); crc = 0u;
#else
            count = cpu_frame(frame, &model, &metrics, &ok); crc = command_crc(phase_of(frame), count); if (!ok) error = SCENE_CTRL_IRQ_ERROR;
#endif
            rt3d_frame_end(&metrics); rt3d_idle_sample(&idle); rt3d_background_sample(&bg);
#if defined(RT3D_MODE_SCENE_CONTROLLER)
            scene_ctrl_perf_read(&perf_after);
#endif
            rt3d_emit_frame(&metrics,&idle,&bg,&perf_before,&perf_after,rep,frame+1u,crc,0u,count,error);
        }
    }
}
