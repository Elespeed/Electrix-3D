按 [阶段性方案汇总](D:/FPGA/Electrix-3d/doc/阶段/阶段性方案汇总.md) 的目标看，目前处于“统一三路径实现与烟测收敛”阶段，尚未进入可出论文图的正式采样阶段。

| 验收项 | 状态 |
|---|---|
| 统一 S0–S4 SK3D-v4 资产、尺寸与 SHA 元数据 | 已完成 |
| `CPU_ONLY`：CPU 变换/剔除/排序/命令 | 已完成，S0 smoke 已通过 |
| `CPU_MATMUL`：仅 4×4 Q8.8 矩阵乘法外设 | 实现完成，但端到端 smoke 未通过 |
| `SCENE_CONTROLLER` 全硬件路径 | 已完成，S0 smoke 已通过 |
| 矩阵外设独立自动回归 | 已完成、通过 |
| 三种模式的 framebuffer CRC 等价闭环 | 未完成 |
| 30 warmup / 300 frames / 5 repetitions 正式矩阵 | 未开始 |
| active cycles、P99、idle/后台吞吐三张图 | 未开始；无可发布统计数据 |

整体上，按关键交付物粗略可视为约 **60% 完成**：三路径框架、两条端到端路径和外设单测已落地；剩余工作的关键不是画图，而是修通 `CPU_MATMUL` 的 SoC 读回并完成 CRC 闭环。

已经验证可通过、可复现的命令：

```powershell
# 生成确定性 S0–S4 模型资产
make -C experiments/3d_scene assets

# CPU 全软件 S0 烟测：此前已通过
make -C experiments/3d_scene MODE=CPU_ONLY MODEL=S0 smoke

# Scene Controller S0 烟测：此前已通过
make -C experiments/3d_scene MODE=SCENE_CONTROLLER MODEL=S0 smoke

# 矩阵外设独立 Verilator 回归：当前结果 JSON 为 PASS
make -C fpga/verilator TB=matmul_peripheral_tb run-batch
```

当前明确不能通过的命令：

```powershell
make -C experiments/3d_scene MODE=CPU_MATMUL MODEL=S0 smoke
```

已定位证据：CPU 正确写入矩阵外设，外设内部 `C` 结果非零且 `done=1/error=0`，但 CPU 读回 `C` 为零，因此失败点在 SoC 的 AXI 读响应/读数据转发，而非 Q8.8 运算或三角形剔除。

暂时不应运行：

```powershell
make -C experiments/3d_scene MODE=CPU_MATMUL run-matrix
make -C experiments/3d_scene MODE=CPU_ONLY run-matrix
make -C experiments/3d_scene MODE=SCENE_CONTROLLER run-matrix
```

原因是正式矩阵必须先满足三模式 smoke 全绿，并且 framebuffer CRC 等价性仍未闭环。运行 smoke 时也应串行执行：`rt_3d_soc_tb` 共用结果 JSON 和 transcript，不能多模式并发。

## CPU_MATMUL 独立顶层交接（待实现、待验证）

为避免改动原有 `soc_top_sketch` 路径，计划新增论文专用的 CPU + Matmul +
SketchBook 顶层及其专用 test bench。实验入口已预留为：

```powershell
# 专用 S0 烟测：固定 CPU_MATMUL/S0，并选择专用 test bench
make -C experiments/3d_scene cpu-matmul-smoke

# 等价的显式选择形式
make -C experiments/3d_scene MODE=CPU_MATMUL MODEL=S0 TB=rt_3d_soc_matmul_tb smoke
```

该入口当前只是运行选择，不代表专用 RTL、filelist 或 test bench 已经完成，
也不代表 smoke 已通过。普通 `smoke` 仍使用调用者指定的 `TB`；专用运行的
正式结果目录按以下层级隔离，避免不同模式或模型互相覆盖：

```text
experiments/3d_scene/runs/<run_id>/CPU_MATMUL/S0/
```

## CPU_MATMUL 独立顶层实施记录（2026-09-06）

- 已新增 `rtl/soc_top_sketch_matmul.sv`、专用 TB 和 Verilator filelist；顶层保持板级端口兼容，并禁用 Scene Controller。
- Verilator S0 smoke 通过：Matmul 写 178、读 104、非零 C 读回 96；CPU 提交 CLEAR=2、TRIANGLE=20、PRESENT=2，并完成非黑帧检查。
- 根因：Matmul C 读窗口的 8 位地址上界回绕，C 寄存器已计算却被读回为零；专用顶层选择锁存地址的读响应。原顶层的默认参数保持原行为。
- CPU_ONLY S0 与 SCENE_CONTROLLER S0 回归通过；矩阵外设独立 Q8.8 回归通过。
- framebuffer/命令 CRC 等价闭环尚未完成；正式 30 warmup × 300 frames × 5 repetitions 尚未开始，禁止运行 `run-matrix`。

在专用顶层和 test bench 落地后，首先验证矩阵写入、`AR handshake`、读响应
转发、CPU 读回、SketchBook `CLEAR/TRIANGLE_FLAT/PRESENT`，再决定是否进入
三模式 CRC 闭环和正式矩阵采样。正式采样在此之前仍保持未开始状态。
