# 当前数值与验证入口

> 状态：新整数规则已接入；自然全量平衡未完成。正式默认六章／Lv30，B05/B06 已接入正常游戏。

当前唯一运行参数源为 `data/rules/numerical.json`。默认校准版本 14；版本 15 和其他实验只在明确 debug 候选、独立档及对应检查协议下使用。不能用旧阶段快照证明当前候选平衡。

- [共用规则与边界](level_equipment_numerical_design.md)
- [当前普通怪数值](ordinary_monster_numbers.md)与[技能登记](../combat/ordinary_monster_expansion.md)
- [成长与保存检查](growth_integration.md)
- [实际预警时序](enemy_warning_timing.md)
- [首领难度与构筑协议](boss_difficulty_calibration.md)
- [工坊规则](random_forging_design.md)
- [自然进度协议](s11_natural_progress_protocol.md)与[当前自然样本限制](first_four_natural_results_2026-10-03.md)

B05、B06 的实验性平衡协议、构筑和诊断分别在各关 `balance`、`enemies`、`bosses` 下。固定数值输入和公式期望已经归入 `tests/fixtures/numerical`，不再作为旧六槽“当前实现”文档展示。
