#include "sketch_os.h"

#include <rthw.h>
#include <rtthread.h>

#include "led.h"
#include "regaddr.h"
#include "scene_asset.h"
#include "scene_ctrl.h"
#include "sketchbook.h"

#define SK_OS_CARD_COUNT       3u
#define SK_OS_MQ_DEPTH          16u
#define SK_OS_INPUT_POLL_MS     1u
#define SK_OS_3D_PERIOD_MS      50u
#define SK_OS_SYSTEM_PERIOD_MS  1000u
#define SK_OS_HOME_PERIOD_MS    50u

#define COLOR_BG       0x02u
#define COLOR_PANEL    0x09u
#define COLOR_CARD     0x12u
#define COLOR_TEXT     0xffu
#define COLOR_MUTED    0xb6u
#define COLOR_YELLOW   0xfcu
#define COLOR_RED      0xe0u
#define COLOR_GREEN    0x1cu
#define COLOR_BLUE     0x03u
#define COLOR_CYAN     0x1fu

#define SK_OS_PREVIEW_X       192u
#define SK_OS_PREVIEW_Y       64u
#define SK_OS_PREVIEW_W       184u
#define SK_OS_PREVIEW_H       190u
#define SK_OS_VIEWPORT_X      200u
#define SK_OS_VIEWPORT_Y      72u
#define SK_OS_VIEWPORT_W      168u
#define SK_OS_VIEWPORT_H      174u
#define SK_OS_MODEL_EXT_BASE  0x1c400000u
#define SK_OS_MODEL_BLADE      0u
#define SK_OS_MODEL_ROBOT_RIGID 1u
#define SK_OS_MODEL_ROBOTSS     2u
#define SK_OS_ROBOT_MESH_COUNT 5u
#define SK_OS_WALK_FRAMES      16u
#define SK_OS_DEMO_VIEWPORT_X  108u
#define SK_OS_DEMO_VIEWPORT_Y  64u
#define SK_OS_DEMO_VIEWPORT_W  184u
#define SK_OS_DEMO_VIEWPORT_H  174u

typedef enum {
    SK_OS_EVENT_UP = 1,
    SK_OS_EVENT_DOWN,
    SK_OS_EVENT_AUX,
    SK_OS_EVENT_CONFIRM
} sketch_os_event_t;

typedef enum {
    SK_OS_HOME = 0,
    SK_OS_CARD_ANIMATION,
    SK_OS_CARD_ROBOT_WALK,
    SK_OS_CARD_SYSTEM
} sketch_os_scene_t;

typedef enum {
    SK_OS_ROBOT_MOTION_WALK = 0,
    SK_OS_ROBOT_MOTION_JUMP_OPEN
} sketch_os_robot_motion_t;

static sketchbook_t g_display;
static rt_mq_t g_event_mq;
static rt_thread_t g_ui_thread;
static rt_thread_t g_input_thread;
static volatile U32 g_pending_buttons;
static U8 g_selected;
static U8 g_page_cursor[2];
static U8 g_page_ui_valid[2];
static U8 g_switch_stable;
static U8 g_switch_candidate;
static U8 g_switch_debounce;
static sketch_os_scene_t g_scene;
static U32 g_present_count;
static rt_tick_t g_last_anim_tick;
static rt_tick_t g_last_system_tick;
static rt_tick_t g_last_home_tick;
static U8 g_scene_model_loaded;
static U8 g_scene_model_entry;
static U8 g_home_dirty;
static U8 g_home_yaw;
static U8 g_demo_yaw;
static U8 g_demo_pitch;
static U8 g_demo_model;
static U8 g_walk_frame;
static sketch_os_robot_motion_t g_robot_motion;

static const char *const g_card_names[SK_OS_CARD_COUNT] = {
    "3D DEMO", "ROBOT WALK", "SYSTEM"
};
static const S16 g_robot_mesh_x[SK_OS_ROBOT_MESH_COUNT] = { -11, 11, -18, 18, 0 };
static const S16 g_robot_mesh_y[SK_OS_ROBOT_MESH_COUNT] = { -25, -25, 11, 11, 31 };

static rt_tick_t ms_to_tick(U32 ms)
{
    rt_tick_t ticks = rt_tick_from_millisecond(ms);
    return (ticks == 0u) ? 1u : ticks;
}

static U8 back_page(void)
{
    return (U8)((* (volatile U32 *)(g_display.base_addr + SKETCHBOOK_REG_PAGE_STATUS) >> 1) & 1u);
}

static void draw_text(S16 x, S16 y, const char *text, U8 color)
{
    while (*text != '\0') {
        sketchbook_draw_glyph(&g_display, x, y, *text, SKETCHBOOK_FONT_6X8, color);
        x = (S16)(x + 6);
        text++;
    }
}

static void draw_box(S16 x, S16 y, U16 w, U16 h, U8 color)
{
    sketchbook_draw_line(&g_display, x, y, (S16)(x + w - 1u), y, color);
    sketchbook_draw_line(&g_display, x, (S16)(y + h - 1u), (S16)(x + w - 1u), (S16)(y + h - 1u), color);
    sketchbook_draw_line(&g_display, x, y, x, (S16)(y + h - 1u), color);
    sketchbook_draw_line(&g_display, (S16)(x + w - 1u), y, (S16)(x + w - 1u), (S16)(y + h - 1u), color);
}

static S16 card_y(U8 index)
{
    return (S16)(72 + ((S16)index * 58));
}

static void draw_cursor(U8 index, U8 color)
{
    draw_box(22, (S16)(card_y(index) - 4), 158, 62, color);
}

static void present_wait(void)
{
    sketchbook_present(&g_display);
    sketchbook_wait_frame_done(&g_display);
    g_present_count++;
}

static void draw_home_static(void)
{
    U8 i;

    sketchbook_clear(&g_display, COLOR_BG);
    sketchbook_fill_rect(&g_display, 16, 12, 368, 28, COLOR_PANEL);
    draw_text(30, 22, "SKETCH SOC / RT-THREAD", COLOR_TEXT);
    draw_text(30, 42, "BTN1 UP  BTN2 DOWN  SW0 ENTER/BACK", COLOR_MUTED);
    for (i = 0u; i < SK_OS_CARD_COUNT; i++) {
        sketchbook_fill_rect(&g_display, 28, card_y(i), 146, 54, COLOR_CARD);
        draw_text(40, (S16)(card_y(i) + 12), g_card_names[i], COLOR_TEXT);
        if (i == 0u) {
            draw_text(40, (S16)(card_y(i) + 30), "interactive blade", COLOR_MUTED);
        } else if (i == 1u) {
            draw_text(40, (S16)(card_y(i) + 30), "5-mesh animation", COLOR_MUTED);
        } else {
            draw_text(40, (S16)(card_y(i) + 30), "kernel info", COLOR_MUTED);
        }
    }
    sketchbook_fill_rect(&g_display, SK_OS_VIEWPORT_X, SK_OS_VIEWPORT_Y,
                         SK_OS_VIEWPORT_W, SK_OS_VIEWPORT_H, COLOR_CARD);
    draw_box(SK_OS_PREVIEW_X, SK_OS_PREVIEW_Y, SK_OS_PREVIEW_W, SK_OS_PREVIEW_H, COLOR_TEXT);
    draw_text(214, 82, "3D BLADE", COLOR_TEXT);
}

static void scene_stop(void)
{
    U32 status;

    status = scene_ctrl_read(SCENE_CTRL_REG_STATUS);
    if ((status & SCENE_CTRL_STATUS_BUSY) != 0u) {
        scene_ctrl_abort();
        do { status = scene_ctrl_read(SCENE_CTRL_REG_STATUS); } while ((status & SCENE_CTRL_STATUS_BUSY) != 0u);
    }
    // An aborted Scene may already have submitted PRESENT.  Let that pending
    // page swap retire, then discard its completion bit so the following UI
    // present cannot mistake the Scene's old FRAME_DONE for its own.
    do { status = sketchbook_get_status(&g_display); } while ((status & SKETCHBOOK_STATUS_SWAP_PENDING) != 0u);
    sketchbook_clear_status(&g_display, SKETCHBOOK_STATUS_FRAME_DONE);
    // ABORT invalidates the Scene controller's model cache.  The next home
    // preview must reload it before issuing RENDER; otherwise the controller
    // correctly rejects RENDER_START because MODEL_VALID is low.
    g_scene_model_loaded = 0u;
}

static U8 scene_load_asset(U8 entry_index, U8 expected_mesh_count, U8 command_mode)
{
    U32 status;
    scene_asset_t asset;
    scene_asset_status_t asset_status;

    if ((g_scene_model_loaded != 0u) && (g_scene_model_entry == entry_index)) return 1u;
    asset_status = scene_asset_resolve_entry(SK_OS_MODEL_EXT_BASE, entry_index, &asset);
    if (asset_status != SCENE_ASSET_OK) {
        rt_kprintf("SK_OS SCENE ASSET FAIL %s\n", scene_asset_status_text(asset_status));
        return 0u;
    }
    rt_kprintf("SK_OS SCENE ASSET entry=%u base=%08x size=%u\n",
               (unsigned int)entry_index, (unsigned int)asset.base,
               (unsigned int)asset.size);
    scene_ctrl_write(SCENE_CTRL_REG_CMD_CFG, command_mode ? 1u : 0u);
    scene_ctrl_configure(asset.base, asset.size);
    scene_ctrl_load();
    do { status = scene_ctrl_read(SCENE_CTRL_REG_STATUS); } while ((status & SCENE_CTRL_STATUS_BUSY) != 0u);
    if ((status & (SCENE_CTRL_STATUS_ERROR | SCENE_CTRL_STATUS_MODEL_VALID)) != SCENE_CTRL_STATUS_MODEL_VALID) {
        rt_kprintf("SK_OS SCENE LOAD FAIL %u\n", (unsigned int)scene_ctrl_error_code());
        return 0u;
    }
    if ((expected_mesh_count != 0u) && (scene_ctrl_cmd_mesh_count() != expected_mesh_count)) {
        rt_kprintf("SK_OS SCENE MESH FAIL %u\n", (unsigned int)scene_ctrl_cmd_mesh_count());
        return 0u;
    }
    g_scene_model_loaded = 1u;
    g_scene_model_entry = entry_index;
    return 1u;
}

static U8 scene_render_rigid(U8 entry_index, U8 yaw, U8 pitch)
{
    U32 status;

    if (scene_load_asset(entry_index, 0u, 0u) == 0u) return 0u;
    scene_ctrl_set_rotation(yaw, pitch, 0u, 0x0100u);
    scene_ctrl_render();
    do { status = scene_ctrl_read(SCENE_CTRL_REG_STATUS); } while ((status & SCENE_CTRL_STATUS_BUSY) != 0u);
    if ((status & (SCENE_CTRL_STATUS_ERROR | SCENE_CTRL_STATUS_RENDER_DONE)) != SCENE_CTRL_STATUS_RENDER_DONE) {
        rt_kprintf("SK_OS SCENE RENDER FAIL %u\n", (unsigned int)scene_ctrl_error_code());
        return 0u;
    }
    return 1u;
}

static U8 scene_render_home_frame(void)
{
    U8 render_result;

    scene_ctrl_set_position(284u, 159u, 0u);
    scene_ctrl_set_viewport(SK_OS_VIEWPORT_X, SK_OS_VIEWPORT_Y,
                            SK_OS_VIEWPORT_W, SK_OS_VIEWPORT_H,
                            SCENE_CTRL_VIEWPORT_ENABLE | SCENE_CTRL_VIEWPORT_LOCAL_CLEAR);
    // The UI thread owns PRESENT.  Scene only submits one frame into the
    // current back page, then returns idle so the UI can finish composition.
    scene_ctrl_set_render_cfg(SCENE_CTRL_RENDER_CFG_BACKFACE_CULL |
                              SCENE_CTRL_RENDER_CFG_DEPTH_SORT,
                              COLOR_CARD);
    render_result = scene_render_rigid(SK_OS_MODEL_BLADE, g_home_yaw, 0u);
    return render_result;
}

static void seed_home_pages(void)
{
    draw_home_static();
    present_wait();
    draw_home_static();
    present_wait();
    g_page_ui_valid[0] = 0u;
    g_page_ui_valid[1] = 0u;
}

static void render_home_frame(void)
{
    U8 page = back_page();

    if (g_page_ui_valid[page] == 0u) {
        draw_home_static();
        draw_cursor(g_selected, COLOR_YELLOW);
        g_page_cursor[page] = g_selected;
        g_page_ui_valid[page] = 1u;
    } else if (g_page_cursor[page] != g_selected) {
        draw_cursor(g_page_cursor[page], COLOR_BG);
        draw_cursor(g_selected, COLOR_YELLOW);
        g_page_cursor[page] = g_selected;
    }

    // The previous 3D frame is not part of the UI shadow state.  It must be
    // restored on every back page before Scene draws the next model pose.
    sketchbook_fill_rect(&g_display, SK_OS_VIEWPORT_X, SK_OS_VIEWPORT_Y,
                         SK_OS_VIEWPORT_W, SK_OS_VIEWPORT_H, COLOR_CARD);
    if (scene_render_home_frame() == 0u) {
        g_page_ui_valid[page] = 0u;
        return;
    }
    present_wait();
    g_home_yaw = (U8)((g_home_yaw + 1u) & 0x0fu);
    g_home_dirty = 0u;
    g_last_home_tick = rt_tick_get();
}

static void update_home_cursor(U8 next)
{
    g_selected = next;
    g_home_dirty = 1u;
    rt_kprintf("SK_OS HOME selected=%u\n", (unsigned int)g_selected);
}

static void draw_card_header(const char *title, const char *subtitle)
{
    sketchbook_clear(&g_display, COLOR_BG);
    sketchbook_fill_rect(&g_display, 16, 12, 368, 28, COLOR_PANEL);
    draw_text(30, 22, title, COLOR_TEXT);
    draw_text(24, 270, "SW0 TO RETURN", COLOR_YELLOW);
    draw_text(24, 42, subtitle, COLOR_MUTED);
}

static void draw_3d_demo_card(void)
{
    const char *subtitle = (g_demo_model == SK_OS_MODEL_ROBOT_RIGID) ?
        "Interactive rigid robot preview" : "Interactive local-refresh blade preview";
    const char *model_label = (g_demo_model == SK_OS_MODEL_ROBOT_RIGID) ?
        "MODEL ROBOT RIGID" : "MODEL BLADE";

    draw_card_header("3D DEMO", subtitle);
    sketchbook_fill_rect(&g_display, SK_OS_DEMO_VIEWPORT_X, SK_OS_DEMO_VIEWPORT_Y,
                         SK_OS_DEMO_VIEWPORT_W, SK_OS_DEMO_VIEWPORT_H, COLOR_CARD);
    draw_box((S16)(SK_OS_DEMO_VIEWPORT_X - 4u), (S16)(SK_OS_DEMO_VIEWPORT_Y - 4u),
             (U16)(SK_OS_DEMO_VIEWPORT_W + 8u), (U16)(SK_OS_DEMO_VIEWPORT_H + 8u), COLOR_TEXT);
    draw_text(24, 242, "SW1 DIR  BTN1/2 PITCH  BTN3 MODEL", COLOR_MUTED);
    draw_text(24, 254, model_label, COLOR_CYAN);
}

static void draw_robot_walk_card(void)
{
    const char *motion_label = (g_robot_motion == SK_OS_ROBOT_MOTION_WALK) ?
        "MODE WALK / BTN1 JUMP OPEN" : "MODE JUMP OPEN / BTN1 WALK";

    draw_card_header("ROBOT WALK", "5-mesh articulated walking solution");
    sketchbook_fill_rect(&g_display, SK_OS_DEMO_VIEWPORT_X, SK_OS_DEMO_VIEWPORT_Y,
                         SK_OS_DEMO_VIEWPORT_W, SK_OS_DEMO_VIEWPORT_H, COLOR_CARD);
    draw_box((S16)(SK_OS_DEMO_VIEWPORT_X - 4u), (S16)(SK_OS_DEMO_VIEWPORT_Y - 4u),
             (U16)(SK_OS_DEMO_VIEWPORT_W + 8u), (U16)(SK_OS_DEMO_VIEWPORT_H + 8u), COLOR_TEXT);
    draw_text(24, 242, motion_label, COLOR_MUTED);
    draw_text(24, 254, "S3PK BR01 / 16-FRAME MULTI-MESH", COLOR_CYAN);
}

static void draw_system_card(void)
{
    draw_card_header("SYSTEM", "RT-Thread kernel and SketchBook status");
    sketchbook_fill_rect(&g_display, 24, 68, 352, 154, COLOR_CARD);
    draw_text(42, 92, "RT-THREAD NANO ACTIVE", COLOR_GREEN);
    draw_text(42, 122, "FINSH: skstatus", COLOR_TEXT);
}

static void draw_system_value(void)
{
    char value[32];
    U32 ticks = (U32)rt_tick_get();

    sketchbook_fill_rect(&g_display, 42, 152, 250, 20, COLOR_CARD);
    rt_snprintf(value, sizeof(value), "TICKS %lu  FRAME %lu", (unsigned long)ticks,
                (unsigned long)sketchbook_get_frame_counter(&g_display));
    draw_text(42, 156, value, COLOR_CYAN);
}

static void seed_card_pages(void)
{
    if (g_scene == SK_OS_CARD_ANIMATION) {
        draw_3d_demo_card();
    } else if (g_scene == SK_OS_CARD_ROBOT_WALK) {
        draw_robot_walk_card();
    } else {
        draw_system_card();
        draw_system_value();
    }
    present_wait();

    if (g_scene == SK_OS_CARD_ANIMATION) {
        draw_3d_demo_card();
    } else if (g_scene == SK_OS_CARD_ROBOT_WALK) {
        draw_robot_walk_card();
    } else {
        draw_system_card();
        draw_system_value();
    }
    present_wait();
}

static void open_selected_card(void)
{
    scene_stop();
    g_page_ui_valid[0] = 0u;
    g_page_ui_valid[1] = 0u;
    g_scene = (sketch_os_scene_t)(SK_OS_CARD_ANIMATION + g_selected);
    if (g_scene == SK_OS_CARD_ROBOT_WALK) {
        g_robot_motion = SK_OS_ROBOT_MOTION_WALK;
    }
    seed_card_pages();
    g_last_anim_tick = rt_tick_get();
    g_last_system_tick = g_last_anim_tick;
    g_demo_yaw = 1u;
    g_demo_pitch = 0u;
    g_demo_model = SK_OS_MODEL_BLADE;
    g_walk_frame = 0u;
    rt_kprintf("SK_OS CARD %s\n", g_card_names[g_selected]);
}

static void return_home(void)
{
    scene_stop();
    g_scene = SK_OS_HOME;
    seed_home_pages();
    g_home_dirty = 1u;
    g_last_home_tick = 0u;
    rt_kprintf("SK_OS HOME selected=%u\n", (unsigned int)g_selected);
}

static void reset_demo_model_state(U8 model)
{
    g_demo_model = model;
    g_demo_yaw = 1u;
    g_demo_pitch = 0u;
    g_walk_frame = 0u;
    g_robot_motion = SK_OS_ROBOT_MOTION_WALK;
}

static void scene_submit_robot_meshes(U8 yaw,
                                      const U8 mesh_pitch[SK_OS_ROBOT_MESH_COUNT],
                                      const U8 mesh_roll[SK_OS_ROBOT_MESH_COUNT],
                                      S16 lift_y)
{
    U8 i;
    scene_ctrl_cmd_t cmd;

    for (i = 0u; i < SK_OS_ROBOT_MESH_COUNT; i++) {
        cmd = scene_ctrl_cmd_draw(i,
                                  g_robot_mesh_x[i],
                                  (S16)(g_robot_mesh_y[i] + lift_y),
                                  0,
                                  yaw,
                                  mesh_pitch[i],
                                  mesh_roll[i],
                                  0x0100u);
        scene_ctrl_cmd_push(&cmd);
    }
}

static void demo_3d_step(void)
{
    U8 render_result;
    U8 reverse = (U8)((RegRead(CONFREG_SWITCH_DATA) >> 1) & 0x01u);

    // Redraw the demo chrome on each back page so model labels do not lag.
    draw_3d_demo_card();
    scene_ctrl_set_position(200u, 151u, 0u);
    scene_ctrl_set_viewport(SK_OS_DEMO_VIEWPORT_X, SK_OS_DEMO_VIEWPORT_Y,
                            SK_OS_DEMO_VIEWPORT_W, SK_OS_DEMO_VIEWPORT_H,
                            SCENE_CTRL_VIEWPORT_ENABLE);
    // Scene's hardware local-clear command is not safe on the FPGA path.
    // Clear the current back page through the established SketchBook CPU
    // renderer, exactly as the home preview does, before Scene draws the pose.
    sketchbook_fill_rect(&g_display, SK_OS_DEMO_VIEWPORT_X, SK_OS_DEMO_VIEWPORT_Y,
                         SK_OS_DEMO_VIEWPORT_W, SK_OS_DEMO_VIEWPORT_H, COLOR_CARD);
    if (g_demo_model == SK_OS_MODEL_BLADE) {
        scene_ctrl_set_render_cfg(SCENE_CTRL_RENDER_CFG_BACKFACE_CULL |
                                  SCENE_CTRL_RENDER_CFG_DEPTH_SORT,
                                  COLOR_CARD);
        render_result = scene_render_rigid(SK_OS_MODEL_BLADE, g_demo_yaw, g_demo_pitch);
        if (render_result == 0u) return;
        present_wait();
    } else {
        scene_ctrl_set_render_cfg(SCENE_CTRL_RENDER_CFG_BACKFACE_CULL |
                                  SCENE_CTRL_RENDER_CFG_DEPTH_SORT,
                                  COLOR_CARD);
        render_result = scene_render_rigid(SK_OS_MODEL_ROBOT_RIGID, g_demo_yaw, g_demo_pitch);
        if (render_result == 0u) return;
        present_wait();
    }
    g_demo_yaw = (U8)((g_demo_yaw + (reverse ? 15u : 1u)) & 0x0fu);
}

static U8 walk_phase(U8 frame)
{
    switch (frame & (SK_OS_WALK_FRAMES - 1u)) {
    case 0u: case 8u: return 0u;
    case 1u: case 7u: return 1u;
    case 2u: case 3u: case 4u: case 5u: case 6u: return 2u;
    case 9u: case 15u: return 15u;
    default: return 14u;
    }
}

static U8 jump_open_phase(U8 frame)
{
    // The cycle never enters the negative (inward) roll half: limbs move
    // neutral -> open -> neutral, so arms do not clip the body and legs never cross.
    switch (frame & (SK_OS_WALK_FRAMES - 1u)) {
    case 0u: case 6u: case 12u: return 0u;
    case 1u: case 5u: case 7u: case 11u: case 13u: case 15u: return 1u;
    default: return 2u;
    }
}

static void robot_walk_step(void)
{
    U8 phase;
    U8 opposite;
    U8 mesh_pitch[SK_OS_ROBOT_MESH_COUNT];
    U8 mesh_roll[SK_OS_ROBOT_MESH_COUNT];
    S16 lift_y = 0;
    U32 completed;
    scene_ctrl_cmd_t cmd;

    draw_robot_walk_card();
    scene_ctrl_set_position(200u, 151u, 0u);
    scene_ctrl_set_viewport(SK_OS_DEMO_VIEWPORT_X, SK_OS_DEMO_VIEWPORT_Y,
                            SK_OS_DEMO_VIEWPORT_W, SK_OS_DEMO_VIEWPORT_H,
                            SCENE_CTRL_VIEWPORT_ENABLE);
    sketchbook_fill_rect(&g_display, SK_OS_DEMO_VIEWPORT_X, SK_OS_DEMO_VIEWPORT_Y,
                         SK_OS_DEMO_VIEWPORT_W, SK_OS_DEMO_VIEWPORT_H, COLOR_CARD);
    if (scene_load_asset(SK_OS_MODEL_ROBOTSS, SK_OS_ROBOT_MESH_COUNT, 1u) == 0u) return;
    completed = scene_ctrl_cmd_frame_count();
    if (g_robot_motion == SK_OS_ROBOT_MOTION_WALK) {
        phase = walk_phase(g_walk_frame);
        opposite = walk_phase((U8)(g_walk_frame + 8u));
        // Preserve the original walk: diagonal limbs swing in depth with pitch.
        mesh_pitch[0] = phase;
        mesh_pitch[1] = opposite;
        mesh_pitch[2] = opposite;
        mesh_pitch[3] = phase;
        mesh_roll[0] = 0u;
        mesh_roll[1] = 0u;
        mesh_roll[2] = 0u;
        mesh_roll[3] = 0u;
    } else {
        phase = jump_open_phase(g_walk_frame);
        opposite = (U8)((SK_OS_WALK_FRAMES - phase) & (SK_OS_WALK_FRAMES - 1u));
        // Keep the original diagonal pitch gait while the roll pose opens out.
        // The two axes combine into a forward-looking running jump without
        // reintroducing an inward screen-plane leg pose.
        mesh_pitch[0] = walk_phase(g_walk_frame);
        mesh_pitch[1] = walk_phase((U8)(g_walk_frame + 8u));
        mesh_pitch[2] = mesh_pitch[1];
        mesh_pitch[3] = mesh_pitch[0];
        // All four limbs use their outward roll direction.  Unlike walking,
        // neither leg is assigned the inward phase, so the feet never cross.
        mesh_roll[0] = opposite;
        mesh_roll[1] = phase;
        mesh_roll[2] = opposite;
        mesh_roll[3] = phase;
        lift_y = (S16)(-(S16)(phase * 2u));
    }
    mesh_pitch[4] = 0u;
    mesh_roll[4] = 0u;
    scene_submit_robot_meshes(0u, mesh_pitch, mesh_roll, lift_y);
    cmd = scene_ctrl_cmd_present(); scene_ctrl_cmd_push(&cmd);
    scene_ctrl_cmd_start_frame();
    while (scene_ctrl_cmd_frame_count() == completed) {
        if (scene_ctrl_read(SCENE_CTRL_REG_STATUS) & SCENE_CTRL_STATUS_ERROR) {
            rt_kprintf("SK_OS ROBOT FAIL %u\n", (unsigned int)scene_ctrl_error_code());
            return;
        }
    }
    // Command mode already issues an explicit PRESENT from the Scene
    // controller.  A second CPU-side PRESENT here swaps in the other back
    // page, which only contains the cleared viewport and causes the observed
    // robot/blank/robot frame alternation.
    g_walk_frame = (U8)((g_walk_frame + 1u) & (SK_OS_WALK_FRAMES - 1u));
}

static void poll_scene(void)
{
    rt_tick_t now = rt_tick_get();

    if ((g_scene == SK_OS_HOME) &&
        ((g_home_dirty != 0u) || ((now - g_last_home_tick) >= ms_to_tick(SK_OS_HOME_PERIOD_MS)))) {
        render_home_frame();
        return;
    }

    if ((g_scene == SK_OS_CARD_ANIMATION) &&
        ((now - g_last_anim_tick) >= ms_to_tick(SK_OS_3D_PERIOD_MS))) {
        g_last_anim_tick = now;
        demo_3d_step();
    }
    if ((g_scene == SK_OS_CARD_ROBOT_WALK) &&
        ((now - g_last_anim_tick) >= ms_to_tick(SK_OS_3D_PERIOD_MS))) {
        g_last_anim_tick = now;
        robot_walk_step();
    }
    if ((g_scene == SK_OS_CARD_SYSTEM) &&
        ((now - g_last_system_tick) >= ms_to_tick(SK_OS_SYSTEM_PERIOD_MS))) {
        g_last_system_tick = now;
        draw_system_value();
        present_wait();
    }
}

static void handle_event(U8 event)
{
    rt_kprintf("[DBG][UI] event=%u scene=%u selected=%u\n", (unsigned int)event,
               (unsigned int)g_scene, (unsigned int)g_selected);
    if (g_scene == SK_OS_HOME) {
        if ((event == SK_OS_EVENT_UP) && (g_selected > 0u)) {
            update_home_cursor((U8)(g_selected - 1u));
        } else if ((event == SK_OS_EVENT_DOWN) && (g_selected + 1u < SK_OS_CARD_COUNT)) {
            update_home_cursor((U8)(g_selected + 1u));
        } else if (event == SK_OS_EVENT_AUX) {
            rt_kprintf("SK_OS HOME ignore_btn3 selected=%u\n", (unsigned int)g_selected);
        } else if (event == SK_OS_EVENT_CONFIRM) {
            open_selected_card();
        }
    } else if (g_scene == SK_OS_CARD_ANIMATION) {
        if (event == SK_OS_EVENT_UP) {
            g_demo_pitch = (U8)((g_demo_pitch + 1u) & 0x0fu);
            rt_kprintf("SK_OS DEMO pitch=%u\n", (unsigned int)g_demo_pitch);
        } else if (event == SK_OS_EVENT_DOWN) {
            g_demo_pitch = (U8)((g_demo_pitch + 15u) & 0x0fu);
            rt_kprintf("SK_OS DEMO pitch=%u\n", (unsigned int)g_demo_pitch);
        } else if (event == SK_OS_EVENT_AUX) {
            scene_stop();
            reset_demo_model_state((g_demo_model == SK_OS_MODEL_BLADE) ? SK_OS_MODEL_ROBOT_RIGID : SK_OS_MODEL_BLADE);
            draw_3d_demo_card();
            present_wait();
            g_last_anim_tick = 0u;
            rt_kprintf("SK_OS DEMO model=%s\n",
                       (g_demo_model == SK_OS_MODEL_ROBOT_RIGID) ? "ROBOT_RIGID" : "BLADE");
        } else if (event == SK_OS_EVENT_CONFIRM) {
            return_home();
        }
    } else if (g_scene == SK_OS_CARD_ROBOT_WALK) {
        if (event == SK_OS_EVENT_UP) {
            g_robot_motion = (g_robot_motion == SK_OS_ROBOT_MOTION_WALK) ?
                SK_OS_ROBOT_MOTION_JUMP_OPEN : SK_OS_ROBOT_MOTION_WALK;
            g_walk_frame = 0u;
            g_last_anim_tick = 0u;
            rt_kprintf("SK_OS ROBOT motion=%s\n",
                       (g_robot_motion == SK_OS_ROBOT_MOTION_WALK) ? "WALK" : "JUMP_OPEN");
        } else if (event == SK_OS_EVENT_CONFIRM) {
            return_home();
        }
    } else if (event == SK_OS_EVENT_CONFIRM) {
        return_home();
    }
}

static void ui_thread_entry(void *parameter)
{
    U8 event;
    (void)parameter;

    while (1) {
        if (rt_mq_recv(g_event_mq, &event, sizeof(event), ms_to_tick(20u)) == RT_EOK) {
            handle_event(event);
        }
        poll_scene();
    }
}

static void post_event(U8 event)
{
    if (g_event_mq != RT_NULL) {
        (void)rt_mq_send(g_event_mq, &event, sizeof(event));
    }
}

static void input_thread_entry(void *parameter)
{
    U32 pending;
    U8 sample;
    rt_base_t level;
    (void)parameter;

    while (1) {
        level = rt_hw_interrupt_disable();
        pending = g_pending_buttons;
        g_pending_buttons = 0u;
        rt_hw_interrupt_enable(level);
        if (pending != 0u) {
            rt_kprintf("[DBG][INPUT] pending=%02lx\n", (unsigned long)pending);
        }
        if ((pending & 0x01u) != 0u) post_event(SK_OS_EVENT_UP);
        if ((pending & 0x02u) != 0u) post_event(SK_OS_EVENT_DOWN);
        if ((pending & 0x04u) != 0u) post_event(SK_OS_EVENT_AUX);

        sample = (U8)(RegRead(CONFREG_SWITCH_DATA) & 0x01u);
        if (sample != g_switch_candidate) {
            g_switch_candidate = sample;
            g_switch_debounce = 0u;
        } else if (g_switch_debounce < 2u) {
            g_switch_debounce++;
        } else if (g_switch_stable != g_switch_candidate) {
            g_switch_stable = g_switch_candidate;
            post_event(SK_OS_EVENT_CONFIRM);
            rt_kprintf("SK_OS SW0 confirm=%u\n", (unsigned int)sample);
        }
        rt_thread_mdelay(SK_OS_INPUT_POLL_MS);
    }
}

void sketch_os_hw_init(void)
{
    sketchbook_init(&g_display, SKETCHBOOK_BASE_ADDR);
    g_selected = 0u;
    g_scene = SK_OS_HOME;
    g_pending_buttons = 0u;
    g_switch_stable = (U8)(RegRead(CONFREG_SWITCH_DATA) & 0x01u);
    g_switch_candidate = g_switch_stable;
    g_switch_debounce = 0u;
    g_home_dirty = 1u;
    g_home_yaw = 1u;
    g_last_home_tick = 0u;
    seed_home_pages();
    setLedPin(0x0001u);
    reset_demo_model_state(SK_OS_MODEL_BLADE);
}

void sketch_os_on_button_irq(U8 button_state)
{
    rt_kprintf("[DBG][BTN_IRQ] state=%02x pending=%02lx\n", (unsigned int)(button_state & 0x0fu),
               (unsigned long)g_pending_buttons);
    g_pending_buttons |= (U32)(button_state & 0x0fu);
}

static int sketch_os_app_init(void)
{
    g_event_mq = rt_mq_create("skmq", sizeof(U8), SK_OS_MQ_DEPTH, RT_IPC_FLAG_FIFO);
    g_ui_thread = rt_thread_create("skui", ui_thread_entry, RT_NULL, 3072, 6, 10);
    g_input_thread = rt_thread_create("skin", input_thread_entry, RT_NULL, 1536, 5, 10);
    if ((g_event_mq == RT_NULL) || (g_ui_thread == RT_NULL) || (g_input_thread == RT_NULL)) {
        rt_kprintf("SK_OS INIT FAIL\n");
        return -1;
    }
    rt_thread_startup(g_ui_thread);
    rt_thread_startup(g_input_thread);
    rt_kprintf("SK_OS READY\n");
    rt_kprintf("SK_OS HOME selected=0\n");
    return 0;
}
INIT_APP_EXPORT(sketch_os_app_init);

static long sketch_os_shell_status(void)
{
    rt_kprintf("SK_OS STATUS scene=%u selected=%u frame=%lu presents=%lu\n",
               (unsigned int)g_scene, (unsigned int)g_selected,
               (unsigned long)sketchbook_get_frame_counter(&g_display),
               (unsigned long)g_present_count);
    return 0;
}
MSH_CMD_EXPORT_ALIAS(sketch_os_shell_status, skstatus, show Sketch OS status);
