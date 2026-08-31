#ifndef SK_OS_SCENE_ASSET_H
#define SK_OS_SCENE_ASSET_H

#include "common_func.h"

typedef enum {
    SCENE_ASSET_OK = 0,
    SCENE_ASSET_BAD_MAGIC,
    SCENE_ASSET_BAD_VERSION,
    SCENE_ASSET_BAD_HEADER,
    SCENE_ASSET_BAD_ENTRY,
    SCENE_ASSET_OUT_OF_RANGE
} scene_asset_status_t;

typedef struct {
    U32 base;
    U32 size;
    U8 format_version;
} scene_asset_t;

/* Resolve one SK3D image at ext_base or a numbered S3PK v1 entry. */
scene_asset_status_t scene_asset_resolve_entry(U32 ext_base, U8 entry_index,
                                               scene_asset_t *asset);
/* Compatibility helper for the first package entry (the blade preview). */
scene_asset_status_t scene_asset_resolve(U32 ext_base, scene_asset_t *asset);
const char *scene_asset_status_text(scene_asset_status_t status);

#endif /* SK_OS_SCENE_ASSET_H */
