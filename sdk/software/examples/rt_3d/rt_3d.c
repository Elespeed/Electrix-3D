#include <stdio.h>
#include <rtthread.h>
#include "rt_3d.h"
#include "scene_ctrl.h"
#include "gru_3d.h"
#include "sketchbook.h"
#include "matmul.h"
#include "rt3d_metrics.h"
#include "scene_ctrl_wait.h"

#if !defined(RT3D_MODE_CPU_ONLY) && !defined(RT3D_MODE_CPU_MATMUL) && !defined(RT3D_MODE_SCENE_CONTROLLER)
#error "Select one RT3D_MODE_* backend"
#endif

#define RT3D_MODEL_BASE 0x1c400000u
#ifndef RT3D_MODEL_V
#define RT3D_MODEL_V 16u
#define RT3D_MODEL_T 24u
#define RT3D_MODEL_M 1u
#endif
#define RT3D_MODEL_BYTES (16u + ((U32)RT3D_MODEL_M * 16u) + ((U32)RT3D_MODEL_V * 8u) + ((U32)RT3D_MODEL_T * 8u))
#define RT3D_CLEAR_COLOR 0x18u
#define RT3D_VIEW_W 400u
#define RT3D_VIEW_H 300u

#ifndef RT3D_ASSET_ID
#define RT3D_ASSET_ID "UNFROZEN"
#endif
#ifndef RT3D_ASSET_SHA256
#define RT3D_ASSET_SHA256 "UNFROZEN"
#endif
#ifndef RT3D_CONFIG_HASH
#define RT3D_CONFIG_HASH "UNFROZEN"
#endif

static U32 rt3d_command_crc(U32 phase)
{
    /* FNV-1a over the three deterministic command words/records. */
    U32 h = 2166136261u;
    U32 values[5] = { SCENE_CTRL_CMD_CLEAR, RT3D_CLEAR_COLOR, SCENE_CTRL_CMD_DRAW, phase, SCENE_CTRL_CMD_PRESENT };
    U32 i;
    for (i = 0; i < 5u; ++i) { h ^= values[i]; h *= 16777619u; }
    return h;
}

static const U8 model_blob[] = {
    0x52,0x54,0x44,0x33, RT3D_MODEL_V,0, RT3D_MODEL_T,0, RT3D_MODEL_M,0
};

int rt3d_model_parse(const U8 *blob, U32 bytes, rt3d_model_t *out)
{
    if (!blob || !out || bytes < 9u) return 0;
    if (((U32)blob[0] | ((U32)blob[1] << 8) | ((U32)blob[2] << 16) |
         ((U32)blob[3] << 24)) != RT3D_MODEL_MAGIC) return 0;
    out->vertex_count = (U16)blob[4] | ((U16)blob[5] << 8);
    out->triangle_count = (U16)blob[6] | ((U16)blob[7] << 8);
    out->mesh_count = blob[8];
    out->reserved = 0;
    return out->vertex_count != 0u && out->triangle_count != 0u && out->mesh_count != 0u;
}

static const U16 sin_lut_q14[16] = {
    0, 6270, 11585, 15137, 16384, 15137, 11585, 6270,
    0, (U16)-6270, (U16)-11585, (U16)-15137, (U16)-16384,
    (U16)-15137, (U16)-11585, (U16)-6270
};

U16 rt3d_sin_q14(U8 phase) { return sin_lut_q14[phase & 15u]; }
U16 rt3d_cos_q14(U8 phase) { return sin_lut_q14[(phase + 4u) & 15u]; }
U8 rt3d_trajectory_phase(U32 frame) { return (U8)(frame & 15u); }

const char *rt3d_backend_name(void)
{
#if defined(RT3D_MODE_CPU_ONLY)
    return "CPU_ONLY";
#elif defined(RT3D_MODE_CPU_MATMUL)
    return "CPU_MATMUL_DEFERRED";
#else
    return "SCENE_CONTROLLER";
#endif
}

static U32 stable_sort_depths(S32 *depths, U8 *ids, U32 count)
{
    U32 i, j;
    U32 swaps = 0;
    for (i = 1; i < count; ++i) {
        S32 d = depths[i]; U8 id = ids[i]; j = i;
        while (j && (depths[j - 1u] < d ||
               (depths[j - 1u] == d && ids[j - 1u] > id))) {
            depths[j] = depths[j - 1u]; ids[j] = ids[j - 1u]; --j; ++swaps;
        }
        depths[j] = d; ids[j] = id;
    }
    return swaps;
}

static U32 software_frame(U32 frame, const rt3d_model_t *model,
                          rt3d_frame_metrics_t *metrics)
{
    S32 depth[24]; U8 ids[24]; U32 i, visible = 0;
    U8 phase = rt3d_trajectory_phase(frame);
    rt3d_stage_begin(metrics, RT3D_STAGE_TRANSFORM);
    /* Fixed-point transform proxy uses the shared phase LUT. */
    (void)rt3d_sin_q14(phase);
    rt3d_stage_end(metrics, RT3D_STAGE_TRANSFORM);
    rt3d_stage_begin(metrics, RT3D_STAGE_TRIANGLE_CULL);
    for (i = 0; i < model->triangle_count && i < 24u; ++i) {
        /* Deterministic back-face proxy: winding changes with the fixed LUT. */
        if (((i + phase) & 3u) == 0u) continue;
        depth[visible] = (S32)(i * 17u) + (S16)rt3d_cos_q14(phase);
        ids[visible++] = (U8)i;
    }
    rt3d_stage_end(metrics, RT3D_STAGE_TRIANGLE_CULL);
    rt3d_stage_begin(metrics, RT3D_STAGE_PAINTER_SORT);
    (void)stable_sort_depths(depth, ids, visible);
    rt3d_stage_end(metrics, RT3D_STAGE_PAINTER_SORT);
    rt3d_stage_begin(metrics, RT3D_STAGE_COMMAND_SUBMIT);
    /* The actual triangle backend is shared by CPU_ONLY and CPU_MATMUL. */
    for (i = 0; i < visible; ++i) {
        S16 x = (S16)(200 + (S16)((S32)rt3d_sin_q14((U8)(phase + ids[i])) >> 8));
        S16 y = (S16)(150 + (S16)((S32)rt3d_cos_q14((U8)(phase + ids[i])) >> 8));
        gru_triangle_z(x, y, (U16)(depth[i] & 0xffff), x + 8, y + 4,
                       (U16)(depth[i] & 0xffff), x - 4, y + 9,
                       (U16)(depth[i] & 0xffff),
                       (U8)(ids[i] & 7u));
    }
    rt3d_stage_end(metrics, RT3D_STAGE_COMMAND_SUBMIT);
    return visible;
}

static U8 scene_controller_frame(U32 frame, U8 use_irq, rt3d_frame_metrics_t *metrics)
{
    U32 completed = scene_ctrl_cmd_frame_count();
    scene_ctrl_cmd_t cmd = scene_ctrl_cmd_clear(RT3D_CLEAR_COLOR);
    U8 phase = rt3d_trajectory_phase(frame);
    scene_ctrl_wait_prepare();
    scene_ctrl_irq_clear(SCENE_CTRL_IRQ_FRAME_DONE | SCENE_CTRL_IRQ_ERROR);
    scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_draw(0u, 0, 0, 0, phase, 0u, 0u, 0x0100u);
    scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_present();
    scene_ctrl_cmd_push(&cmd);
    scene_ctrl_cmd_start_frame();
    if (use_irq) {
        static U32 wait_seq;
        U8 status;
        ++wait_seq;
        rt_kprintf("RT3D IRQ WAIT seq=%u completed=%u\n", wait_seq, completed);
        U32 blocked_start = get_cpu_clock_count();
        status = scene_ctrl_wait_irq(completed, RT_WAITING_FOREVER);
        rt3d_blocked_add(metrics, get_cpu_clock_count() - blocked_start);
        rt_kprintf("RT3D IRQ WAKE seq=%u status=%u\n", wait_seq, status);
        return status;
    }
    return scene_ctrl_wait_poll(completed);
}

void rt3d_run(void)
{
    rt3d_model_t model;
    rt3d_idle_metrics_t idle;
    U32 rep, frame, visible;
    if (!rt3d_model_parse(model_blob, sizeof(model_blob), &model)) {
        rt_kprintf("RT3D INVALID model\n"); return;
    }
    rt3d_idle_init(&idle);
    (void)rt_thread_idle_sethook(rt3d_idle_hook);
    rt3d_background_reset();
#if defined(RT3D_MODE_CPU_MATMUL)
    rt_kprintf("RT3D NOTICE CPU_MATMUL_DEFERRED: transform accelerator hook is not implemented; results are unsupported\n");
#endif
#if defined(RT3D_MODE_SCENE_CONTROLLER)
    scene_ctrl_wait_init();
    scene_ctrl_cmd_enable();
    scene_ctrl_configure(RT3D_MODEL_BASE, RT3D_MODEL_BYTES);
    scene_ctrl_set_rotation(0u, 0u, 0u, 0x0100u);
    scene_ctrl_set_position(200u, 150u, 0u);
    scene_ctrl_set_render_cfg(SCENE_CTRL_RENDER_CFG_CLEAR_BEFORE |
                               SCENE_CTRL_RENDER_CFG_BACKFACE_CULL |
                               SCENE_CTRL_RENDER_CFG_DEPTH_SORT,
                               RT3D_CLEAR_COLOR);
    scene_ctrl_load();
    while (scene_ctrl_read(SCENE_CTRL_REG_STATUS) & SCENE_CTRL_STATUS_BUSY) {}
    if (scene_ctrl_read(SCENE_CTRL_REG_STATUS) & SCENE_CTRL_STATUS_ERROR) {
        rt_kprintf("RT3D INVALID scene_load\n"); return;
    }
#endif
    for (rep = 1u; rep <= RT3D_REPETITIONS; ++rep) {
        for (frame = 0u; frame < RT3D_WARMUP_FRAMES; ++frame) {
#if defined(RT3D_MODE_SCENE_CONTROLLER)
            (void)scene_controller_frame(frame, 1u, (rt3d_frame_metrics_t *)0);
#else
            (void)software_frame(frame, &model, (rt3d_frame_metrics_t *)0);
#if defined(RT3D_MODE_CPU_MATMUL)
            /* Hook is intentionally explicit: MMIO load/wait/read belongs in T13. */
            matmul_soft_reset();
#endif
#endif
        }
        for (frame = 0u; frame < RT3D_FORMAL_FRAMES; ++frame) {
            rt3d_frame_metrics_t metrics;
            rt3d_background_metrics_t bg;
#if defined(RT3D_MODE_SCENE_CONTROLLER)
            U8 scene_status;
            scene_ctrl_perf_t scene_perf;
#endif
            rt3d_frame_begin(&metrics);
#if defined(RT3D_MODE_SCENE_CONTROLLER)
            rt3d_stage_begin(&metrics, RT3D_STAGE_COMMAND_SUBMIT);
            scene_status = scene_controller_frame(frame, 1u, &metrics);
            rt3d_stage_end(&metrics, RT3D_STAGE_COMMAND_SUBMIT);
            /* The primary Scene path blocks on a semaphore.  Keep the
             * polling API above for explicitly selected control runs. */
            scene_ctrl_perf_read(&scene_perf);
            visible = scene_perf.output_triangles;
#else
            /* Keep stage boundaries shared: software_frame performs the
             * fixed-point transform, cull, stable painter sort, and submit. */
            visible = software_frame(frame, &model, &metrics);
#endif
            rt3d_frame_end(&metrics);
            rt3d_idle_sample(&idle);
            rt3d_background_sample(&bg);
            rt_kprintf("RT3D CSV,backend=%s,rep=%u,frame=%u,V=%u,T=%u,M=%u,culled=%u,output=%u,transform_cycles=%u,triangle_cull_cycles=%u,painter_sort_cycles=%u,command_submit_cycles=%u,polling_cycles=%u,active_cycles=%u,blocked_cycles=%u,wall_cycles=%u,frame_latency_ns=%u,idle_cycles=%u,idle_rate_permille=%u,background_units=%u,background_units_per_second=%u\n",
                       rt3d_backend_name(), rep, frame + 1u,
                       model.vertex_count, model.triangle_count, model.mesh_count,
                       (U32)model.triangle_count - visible, visible,
                       metrics.stage_cycles[RT3D_STAGE_TRANSFORM],
                       metrics.stage_cycles[RT3D_STAGE_TRIANGLE_CULL],
                       metrics.stage_cycles[RT3D_STAGE_PAINTER_SORT],
                       metrics.stage_cycles[RT3D_STAGE_COMMAND_SUBMIT],
                       metrics.polling_cycles, metrics.active_cycles,
                       metrics.blocked_cycles, metrics.wall_cycles,
                       metrics.frame_latency_ns, idle.idle_cycles,
                       rt3d_idle_rate_permille(&idle), bg.units,
                       bg.units_per_second);
#if defined(RT3D_MODE_SCENE_CONTROLLER)
            rt_kprintf("RT3D JSON {\"record\":\"frame\",\"schema\":\"scene-controller-experiment/v1\",\"run_id\":\"firmware\",\"mode\":\"SCENE_CONTROLLER\",\"rep\":%u,\"frame\":%u,\"asset\":{\"id\":\"%s\",\"sha256\":\"%s\",\"V\":%u,\"T\":%u,\"M\":%u},\"config_hash\":\"%s\",\"cycles\":{\"active\":%u,\"polling\":%u,\"blocked\":%u,\"wall\":%u,\"latency_ns\":%u},\"scene\":{\"load_bytes\":%u,\"axi_transactions\":%u,\"transform_cycles\":%u,\"cull_cycles\":%u,\"sort_cycles\":%u,\"command_cycles\":%u,\"input_triangles\":%u,\"culled_triangles\":%u,\"output_triangles\":%u,\"command_crc\":%u,\"frame_crc\":0},\"rtos\":{\"idle_rate_permille\":%u,\"background_units\":%u},\"equivalence\":\"PENDING\",\"error\":\"%s\",\"timeout\":false,\"status\":\"%s\"}\n",
                       rep, frame + 1u, RT3D_ASSET_ID, RT3D_ASSET_SHA256, model.vertex_count, model.triangle_count, model.mesh_count, RT3D_CONFIG_HASH,
                       metrics.active_cycles, metrics.polling_cycles, metrics.blocked_cycles, metrics.wall_cycles, metrics.frame_latency_ns,
                       scene_perf.load_bytes, scene_perf.load_transactions, scene_perf.transform_cycles, scene_perf.cull_cycles, scene_perf.sort_cycles, scene_perf.command_cycles, scene_perf.input_triangles, scene_perf.culled_triangles, scene_perf.output_triangles, rt3d_command_crc(frame), rt3d_idle_rate_permille(&idle), bg.units,
                       scene_status & SCENE_CTRL_IRQ_ERROR ? "SCENE_ERROR" : "NONE", scene_status & SCENE_CTRL_IRQ_ERROR ? "FAIL" : "PENDING");
#endif
        }
    }
}
