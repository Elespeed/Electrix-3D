#include "scene_asset.h"

#define SCENE_ASSET_EXT_BYTES       0x00400000u
#define SCENE_ASSET_SK3D_MAGIC      0x534b3344u
#define SCENE_ASSET_S3PK_MAGIC      0x5333504bu
#define SCENE_ASSET_S3PK_VERSION    1u
#define SCENE_ASSET_S3PK_ENTRY_SIZE 32u
#define SCENE_ASSET_MAX_MESHES      16u

static U32 asset_word(U32 base, U32 offset)
{
    return *(volatile const U32 *)(base + offset);
}

static U8 range_valid(U32 offset, U32 size)
{
    return (offset <= SCENE_ASSET_EXT_BYTES) &&
           (size <= (SCENE_ASSET_EXT_BYTES - offset));
}

static scene_asset_status_t resolve_sk3d(U32 base, U32 available, scene_asset_t *asset)
{
    U32 vertex_count;
    U32 triangle_count;
    U32 format;
    U32 size;
    U32 mesh_count;

    if (available < 16u) return SCENE_ASSET_OUT_OF_RANGE;
    vertex_count = asset_word(base, 4u) & 0xffu;
    triangle_count = asset_word(base, 8u) & 0xffu;
    format = asset_word(base, 12u);
    if (vertex_count == 0u || triangle_count == 0u) return SCENE_ASSET_BAD_HEADER;

    size = 16u + (vertex_count * 8u) + (triangle_count * 8u);
    if ((format & 0xffu) == 3u) {
        U32 material_count = (format >> 8) & 0xffu;
        U32 group_count = (format >> 16) & 0xffu;
        if (material_count == 0u || group_count == 0u) return SCENE_ASSET_BAD_HEADER;
        size += (material_count * 4u) + (group_count * 4u);
    } else if ((format & 0xffu) == 4u) {
        mesh_count = (format >> 8) & 0xffu;
        if (mesh_count == 0u || mesh_count > SCENE_ASSET_MAX_MESHES) return SCENE_ASSET_BAD_HEADER;
        size += mesh_count * 16u;
    } else if ((format & 0xffu) != 2u) {
        return SCENE_ASSET_BAD_VERSION;
    }

    if (!range_valid(0u, size) || size > available) return SCENE_ASSET_OUT_OF_RANGE;
    asset->base = base;
    // S3PK descriptors cover every V4 mesh payload.  The common header's
    // aggregate counts are sufficient for validation but are not the package
    // extent, so preserve the catalog size when resolving a package entry.
    asset->size = (available == SCENE_ASSET_EXT_BYTES) ? size : available;
    asset->format_version = (U8)(format & 0xffu);
    return SCENE_ASSET_OK;
}

scene_asset_status_t scene_asset_resolve_entry(U32 ext_base, U8 entry_index,
                                               scene_asset_t *asset)
{
    U32 magic;

    if (asset == 0) return SCENE_ASSET_BAD_HEADER;
    if (!range_valid(0u, 16u)) return SCENE_ASSET_OUT_OF_RANGE;
    magic = asset_word(ext_base, 0u);
    if (magic == SCENE_ASSET_SK3D_MAGIC)
        return resolve_sk3d(ext_base, SCENE_ASSET_EXT_BYTES, asset);
    if (magic == SCENE_ASSET_S3PK_MAGIC) {
        U32 version_and_count = asset_word(ext_base, 4u);
        U32 entry_count = (version_and_count >> 16) & 0x0fu;
        U32 directory_bytes = asset_word(ext_base, 8u);
        U32 payload_offset = asset_word(ext_base, 12u);
        U32 entry_base;
        U32 entry_info;
        U32 entry_offset;
        U32 entry_size;

        if ((version_and_count & 0xffffu) != SCENE_ASSET_S3PK_VERSION)
            return SCENE_ASSET_BAD_VERSION;
        if (entry_count == 0u || entry_count > SCENE_ASSET_MAX_MESHES ||
            directory_bytes != entry_count * SCENE_ASSET_S3PK_ENTRY_SIZE ||
            payload_offset < (16u + directory_bytes) || (payload_offset & 3u) != 0u ||
            entry_index >= entry_count)
            return SCENE_ASSET_BAD_HEADER;

        entry_base = 16u + ((U32)entry_index * SCENE_ASSET_S3PK_ENTRY_SIZE);
        if (!range_valid(entry_base, SCENE_ASSET_S3PK_ENTRY_SIZE))
            return SCENE_ASSET_OUT_OF_RANGE;
        entry_info = asset_word(ext_base, entry_base);
        entry_offset = asset_word(ext_base, entry_base + 4u);
        entry_size = asset_word(ext_base, entry_base + 8u);
        if ((entry_info & 0x0fu) != entry_index ||
            ((((entry_info >> 8) & 0xffu) != 2u) &&
             (((entry_info >> 8) & 0xffu) != 3u) &&
             (((entry_info >> 8) & 0xffu) != 4u)) ||
            entry_size == 0u || (entry_offset & 3u) != 0u || entry_offset < payload_offset ||
            !range_valid(entry_offset, entry_size))
            return SCENE_ASSET_BAD_ENTRY;

        return resolve_sk3d(ext_base + entry_offset, entry_size, asset);
    }
    return SCENE_ASSET_BAD_MAGIC;
}

scene_asset_status_t scene_asset_resolve(U32 ext_base, scene_asset_t *asset)
{
    return scene_asset_resolve_entry(ext_base, 0u, asset);
}

const char *scene_asset_status_text(scene_asset_status_t status)
{
    switch (status) {
    case SCENE_ASSET_OK: return "ok";
    case SCENE_ASSET_BAD_MAGIC: return "bad magic";
    case SCENE_ASSET_BAD_VERSION: return "unsupported version";
    case SCENE_ASSET_BAD_HEADER: return "bad header";
    case SCENE_ASSET_BAD_ENTRY: return "bad package entry";
    case SCENE_ASSET_OUT_OF_RANGE: return "outside ExtRAM";
    default: return "unknown";
    }
}
