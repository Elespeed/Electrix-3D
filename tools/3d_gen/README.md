# Blender -> FPGA 3D Converter

`tools/3d_gen` 当前提供 Blender 低模资产到 SketchBook/FPGA 渲染链路的离线转换与参考渲染工具。

当前入口：

```powershell
python tools/3d_gen/obj2sk3d.py `
    assets/3d/sources/cat1/cat1.obj `
    --mtl assets/3d/sources/cat1/cat1.mtl `
    --target-height 120 `
    --center `
    --output assets/3d/generated/cat1/v3/cat1.s3d.mif

python tools/3d_gen/render_cli.py `
    assets/3d/generated/cat1/v3/cat1.json `
    --profile no_zbuffer
```

若资产遵循默认目录约定，可直接完成转换和两份参考渲染：

```powershell
make -f tools/3d_gen/Makefile ASSET=plane
```

默认读取 `assets/3d/sources/plane/plane.obj` 和 `.mtl`，写入 `assets/3d/generated/`，并为普通版和 `_shade` 版分别生成三个渲染 profile：`no_zbuffer`、`zbuffer`、`zbuffer_object_outline`。输出位置为 `assets/3d/previews/frame/plane/<profile>/` 与 `assets/3d/previews/frame/plane_shade/<profile>/`。可用 `SCALE` 设置额外等比缩放，例如 `SCALE=0.8`；它在 `--target-height` 归一化后生效，仍会自动压缩到 SK3D0 坐标范围。Makefile 的预览使用 `--preserve-scale`，因此 PNG 会反映实际导出尺寸；单独调用 `render_cli.py` 时，默认仍会归一化到 120，若想保留尺寸请加同名参数。

## 输入

- `OBJ`
  - 必须三角化
  - 面通过 `usemtl` 绑定材质
- `MTL`
  - 使用 `Kd` 作为面颜色来源

源资产目录约定：

```text
assets/3d/sources/<asset>/
  <asset>.obj
  <asset>.mtl
```

## 输出

转换器会同时生成：

- `assets/3d/generated/<asset>/v3/<asset>.json`
- `assets/3d/generated/<asset>/v3/<asset>.s3d.mif`
- `assets/3d/generated/<asset>/v3/<asset>.s3d.bin`（每个 32-bit word 按 little-endian 连续存放）
- `assets/3d/generated/<asset>/v3/<asset>_ref_pkg.svh`

`--target-height` 是期望高度。若按该高度缩放后任何顶点坐标超出 SK3D0 可表示范围，转换器会自动进行一次等比缩小，使所有坐标落在 `[-128, 127]` 内，并在终端提示实际高度。JSON 的 `metadata.normalization` 同时记录请求高度、实际高度和自动缩放比例。

## V3 / V4 资产目录

`make -f tools/3d_gen/Makefile ASSET=robotss` 会同时生成：

- `assets/3d/generated/<asset>/v3/`：现有 V3 动态着色模型及其 `_shade` 预烘焙模型、JSON、MIF、bin 和 SV 参考包；
- `assets/3d/generated/<asset>/v4/`：V4 多 mesh 的预烘焙 `_shade` 模型 MIF、bin 和审计 JSON。

V4 使用 `SK3D` header、版本 `4`。header 后是每个 mesh 四个 word 的顶点范围和三角形范围描述符，之后是拼接的 Q8.8 顶点池与 RGB332 静态三角形。当前硬件支持 1--16 mesh、总 1--128 顶点及总 1--192 三角形。

多部件 V4 模型提供 `<asset>.v4.json` 清单。清单按显示顺序列出 mesh 的 `name`、可匹配 OBJ `g` 标签的 `group_prefixes` 和 `pivot_key`；`pivot_file` 指向含 `objects.<pivot_key>.obj_pivot` 的 OBJ 空间 pivot 文件。所有 OBJ face 必须恰好归属于一个 mesh。导出器以 pivot 为局部原点重建各 mesh 顶点与索引；运行时 draw 命令使用输出 JSON 的 pivot 作为中性姿态平移。没有清单的模型自动导出一个名为 `root` 的 V4 mesh，保证 `make ASSET=<asset>` 可用。

默认 `make` 的 PNG 预览与 `ASSET=robotss` 的 GIF 预览均只读取 `assets/3d/generated/<asset>/v3/`。GIF 写入 `assets/3d/previews/frame/robotss/walk_v3/`，不会读取 V4 文件；V4 动画仍可单独通过 `robotss_walk.py` 生成。迁移前由 TB 消费但不能与当前生成结果等同的文件保存在 `<asset>/legacy_v3/`，不得按同名文件直接删除。

## 格式

- 中间 JSON
  - `lowpoly-model` v1
  - 保留 `metadata`
  - 面可带 `material` / `group` 等 `extra` 字段
- 运行时二进制
  - `SK3D0`
  - 所有面色与动态四档材质色均为 RGB332；参考 PNG 由 RGB332 精确扩展为 RGB888
  - header:
    - `word0`: `SK3D`
    - `word1`: `vertex_count`
    - `word2`: `triangle_count`
    - `word3`: version/reserved，当前为 `0`
  - 同时输出 `.s3d.mif`（一行一个二进制 word，供仿真初始化）和 `.s3d.bin`（little-endian 原始字节流，供软件或 ROM 镜像使用）；二者承载完全相同的 word 序列

## 首版限制

- `<= 128` 顶点
- `<= 192` 三角形
- 坐标自动等比压缩至可编码的 signed Q8.8 范围（不会自动减面）
- 不做自动减面
- 不支持 pivot / animation / texture

## 测试

```powershell
python -m unittest discover -s tools/3d_gen/tests -v
```

重点测试覆盖：

- OBJ/MTL 导入
- SK3D0 导出
- `cat1` 资产的确定性生成
- 离线 3D 参考渲染的确定性输出
- `cat1` 遮挡热点帧的统计稳定性

## 离线参考渲染

`render_cli.py` 会把 lowpoly JSON 资产渲染到：

```text
assets/3d/previews/frame/<asset>/<profile>/
  frame_0000.png
  ...
  frame_0015.png
  contact_sheet.png
  animation.gif
  frames.json
```

固定 profile：

- `no_zbuffer`
  - 当前硬件黄金参考
  - 对齐当前 Sketch 3D 链路：背面剔除 + 平均 Z painter sort + 面原色
  - 用于和 `sim/frame_output/*.png` 做逐帧对照，不直接拿来对比 Blender
- `zbuffer`
  - 离线遮挡验证 profile
  - 使用逐像素 Z-buffer 修复遮挡错误，不加阴影
  - 只承诺比 `no_zbuffer` 少遮挡错误，不承诺更像 Blender
- `zbuffer_object_outline`
  - Z-buffer 可见性加对象边界描边，用于检查不同物体的可见轮廓

## `frames.json` 诊断字段

除了每帧三角形明细，`frames.json` 现在还会输出：

- `focus_frame_indices`
  - 固定重点检查帧，默认是 `0 / 3 / 4 / 12`
- `focus_frames`
  - 重点帧的简表，便于快速判断正面、侧面和热点角度
- `occlusion_stats`
  - `visible_triangle_count`
  - `overlap_triangle_count`
  - `overlap_pixel_count`
  - `painter_z_conflict_triangle_count`
  - `zbuffer_corrected_pixel_count`
  - `zbuffer_corrected_pixel_ratio`
  - `filled_pixel_count`
  - `depth_min` / `depth_max` / `depth_span`

这些统计用于把问题拆成三类：

- 遮挡错误：平均 Z painter sort 与逐像素 Z-buffer 出现冲突
- 立体感不足：正交投影 + 无阴影，或仅面级阴影导致
- 资产表达限制：当前模型、材质或部件粒度过粗

如果 `zbuffer` 已经把遮挡冲突降下去，但侧面仍然像平板，这不是 Z-buffer 失败，而是后两类问题的剩余影响。
