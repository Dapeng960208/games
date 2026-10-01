# 数值重构文档入口

2026-10-01：方案等待用户确认。当前运行数值未修改；文档与生成工具直接提交main。

推荐先读 [等级、装备、锻造与全量Buff方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)，再查看 [目标数值全表](TARGET_NUMERICAL_TABLES.md)。

当前实现的完整证据分别在：

- [角色、逐级成长、96装备、14套装、强化/交易及配装算例](CURRENT_HERO_EQUIPMENT_CATALOG.md)。
- [技能、被动、遗物、状态、Buff、护盾、补给、全部加成及伤害流水线](CURRENT_BUFF_SKILL_CATALOG.md)。
- [36野怪、精英、4Boss40招、初始属性、成长、难度及实际遭遇](CURRENT_ENEMY_BOSS_CATALOG.md)。
- [24房、4Boss、2可选箱与自然击杀的全部奖励](CURRENT_REWARD_CATALOG.md)。

仅用于文档的 [新方案参数](numerical_v2_parameters.json) 和 [敌人初值快照](current_enemy_initial_values.json) 不由游戏加载。所有 CURRENT 册描述现状，TARGET 册描述提案，二者不能互相代替。

文档一致性检查：

```powershell
python tools/balance/export_hero_equipment_catalog.py --check
python tools/balance/render_buff_skill_catalog.py --check
python tools/balance/render_enemy_boss_catalog.py --input artifacts/balance-enemy-catalog/current.json --check
python tools/balance/render_target_numerical_tables.py --check
```

敌人现状导出需先使用册末记录的隔离Godot命令生成JSON；其缓存不入库。角色、Buff和目标表的一致性检查不依赖缓存或实际玩家存档。Godot实际预览与静态源码梳理的边界在各册内明确标注；文档检查不替代未来运行重构后的战斗验收。
