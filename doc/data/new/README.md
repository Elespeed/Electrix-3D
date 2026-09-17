# 300 帧预测数据（合成示例）

`forecast_300_frames.csv` 是用于统计脚本、论文版式和分析流程预演的**预测/合成**数据，不能作为仿真、上板或基准测试的实测结果，不能用于支持研究假设、报告 P99 或替换正式 5×300 帧实验。

数据覆盖 S0--S4、`CPU_ONLY`、`CPU_MATMUL`、`SCENE_CONTROLLER`，每个“规模 × 方案”条件为 300 帧，共 4,500 条记录。每一行均含 `record_class=FORECAST_SYNTHETIC_DO_NOT_USE_AS_MEASURED_RESULT` 与 `status=FORECAST_ONLY`，以保证脱离本说明文件后仍可识别来源。

生成口径：固定随机种子 `20260913`，以稿件中记录的先导实验量级为场景输入；S3/S4 的 `SCENE_CONTROLLER` 延迟中心保留了先导实验中略高于 33.333 ms 预算的趋势。数值不是通过真实 RTL、SoC 或 FPGA 运行获得，也不是对正式实验的统计推断。

运行 `python doc/data/new/generate_forecast_dataset.py` 可确定性重建 CSV。未生成任何图表。
