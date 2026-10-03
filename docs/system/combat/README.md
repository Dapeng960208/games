# 战斗系统

> 状态：三职业、六关 90 普通怪和 6 首领已正式接入；自然全量平衡与完整动作待验证。

- [职业技能](role_skills.md)
- [普通怪机制与门槛](ordinary_monster_expansion.md)
- [普通怪变体登记](enemy_variants.md)
- [当前普通怪数值](../balance/ordinary_monster_numbers.md)
- [预警时序](../balance/enemy_warning_timing.md)

普通怪与首领的逐关入口见 [levels](../../levels/README.md)，对应 assets/levels/<chapter>/enemies 与 bosses。战斗规则位于 scripts/domain/combat，节点行为位于 scripts/gameplay，绘制与反馈位于 scripts/presentation/combat 或 monsters。B05/B06 专属规则已进入正式六章默认配置；实验性校准仍隔离。
