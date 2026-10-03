# 数值重构文档入口

2026-10-03 PR #7 合并后，当前未完成事项统一见[平衡性遗留清单](BALANCE_FOLLOWUPS_2026-10-03.md)：最新要求、已有反例、B05/B06 Boss 候选结果、B06 B 部分完成及后续验收条件。该文档 PR 不调参；用户已授权 B07/B08 分别开分支/PR 开发，平衡遗留不阻塞开工。下方旧版本/旧等级样本保留历史身份，不能证明最新模型通过。

## 当前共享模型入口

2026-10-03：archive15/数值v4已进入**显式隔离候选**，默认仍14。按最新要求base1.0、坦克HP2/双防1.3，独立法强、全局暴击和各定位增强的口径写回[原总案第8/9节](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)；六章原正文已列90种定位、实际出场采样等级和[15真实profile全表](resolver_tables/ARCHIVE15_B01_B06.csv)。profile一致性与真实伤害/行为、连续整关验收分开；不以14旧战斗样本证明15平衡。

2026-10-02冻结archive14，覆盖B01–B06普通/精英，Boss保持独立v2。公式、原型/定位系数、双防成长和取整已回写[原数值总案第9节](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md#9-野怪首领与难度标尺)；各章原正文列出当前完整roster和Boss五难度表。[完整2730行resolver表](resolver_tables/ARCHIVE14_B01_B06.csv)及[来源哈希](resolver_tables/ARCHIVE14_MANIFEST.json)可由 `python tools/balance/sync_level_numerical_docs.py --check` 复核。默认发布仍为前四章，B05/B06为隔离候选；数值一致不代表三职业/装备/连续整关平衡已验收。

下文保留各轮历史记录；旧CURRENT/TARGET及archive13表不能当archive14当前面板。

2026-10-02新增普通怪范围：四关9/12/15/18种，共54种；新增18种及全部普通怪难度技能单独记录于[当前普通怪数值](ORDINARY_MONSTER_NUMBERS.md)与[逐怪技能/关卡册](../ORDINARY_MONSTER_EXPANSION.md)。本轮追加的普通怪和首领短预警见[实际时序全表](ENEMY_WARNING_TIMING.md)，仅V2改变前摇/锁定，恢复和伤害不变。下方36种CURRENT快照保留旧数值基线，不覆盖本轮技能扩充。

最新状态（2026-10-02）：本次PR #2交付S00–S10，已完成本地合并前验收及发现问题的修复；新规则默认启用，旧进行中冒险保持冻结规则。用户授权验收后合并并清理PR分支。S11继续暂缓，所有实验参数均未进入生产配置，自然平衡未验收。见 [本地验收记录](PR2_ACCEPTANCE_2026-10-02.md)、[S11暂缓与已知问题](S11_DEFERRED_ISSUES_2026-10-01.md)、[实施记录](IMPLEMENTATION_LOG.md)和[运行校准表](RUNTIME_CALIBRATION_TABLES.md)。

下方提案、CURRENT现状册和旧目标册保留原始设计/源码基线，不应把它们的历史“待确认/未实施”措辞当作当前交付状态。

推荐先读 [等级、装备、锻造与全量Buff方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)，再查看 [目标数值全表](TARGET_NUMERICAL_TABLES.md)、[角色技能与Buff整数目标表](TARGET_HERO_SKILL_BUFF_TABLES.md)、[野怪与Boss技能目标表](TARGET_ENEMY_SKILL_TABLES.md)。

[S00–S11执行清单](NUMERICAL_REDESIGN_EXECUTION_STEPS.md)记录步骤、责任和实际状态。S11保留的检查要求没有降低，但按用户要求暂缓；文档或工具检查通过不能当作战斗平衡已验收。

新增要求集中记录于 [随机强化与品质等效](RANDOM_FORGING_DESIGN.md)和[章节递增/Boss配装标尺](BOSS_DIFFICULTY_CALIBRATION.md)：金掉落最高+1，白绿紫可+5；每阶增幅8%–12%，可保底重锻；白+5≈绿+3、绿+5≈紫+2、紫+5≈金+2；1–12章递增，按对应章级全8槽金约+2配装校准D4首领。后三项中的具体概率、费用和战斗表现是待确认/待验证参数。

当前实现的完整证据分别在：

- [角色、逐级成长、96装备、14套装、强化/交易及配装算例](CURRENT_HERO_EQUIPMENT_CATALOG.md)。
- [技能、被动、遗物、状态、Buff、护盾、补给、全部加成及伤害流水线](CURRENT_BUFF_SKILL_CATALOG.md)。
- [36野怪、精英、4Boss40招、初始属性、成长、难度及实际遭遇](CURRENT_ENEMY_BOSS_CATALOG.md)。
- [24房、4Boss、2可选箱与自然击杀的全部奖励](CURRENT_REWARD_CATALOG.md)。

仅用于文档的 [新方案参数](numerical_v2_parameters.json)、[敌人初值快照](current_enemy_initial_values.json)及[敌人技能冻结输入](current_enemy_skill_inputs.json)不由游戏加载。所有 CURRENT 册描述现状，TARGET 册描述提案，二者不能互相代替。

文档一致性检查：

```powershell
python tools/balance/export_hero_equipment_catalog.py --check
python tools/balance/render_buff_skill_catalog.py --check
python tools/balance/render_enemy_boss_catalog.py --input artifacts/balance-enemy-catalog/current.json --check
python tools/balance/render_target_numerical_tables.py --check
python tools/balance/render_target_hero_skill_buffs.py --check
python tools/balance/render_target_enemy_skills.py --check
```

敌人现状导出需先使用册末记录的隔离Godot命令生成JSON；其缓存不入库。角色、Buff和三份目标表的一致性检查不依赖缓存或实际玩家存档。Godot实际预览与静态源码梳理的边界在各册内明确标注；文档检查不替代未来运行重构后的战斗验收。

三职业后续工作：[定位、八向动作、技能手感、成长与职业装备详细方案](../character-optimization/ROLE_OPTIMIZATION_2026-10-02.md)。当前为逐项实施方案；未验证项目保持待完成，S11全量自然平衡仍暂停。
