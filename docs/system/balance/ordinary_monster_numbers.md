# 当前普通怪数值来源

更新：2026-10-03。**状态：90种普通怪与整数结算已接入；自然平衡待验证。**

前四章分别有9、12、15、18种普通怪；B05/B06 的各18种普通怪已正式接入。物种身份、角色定位、招式、实际难度与校准快照共同决定运行值，不将过期导出表作为当前面板。

| 来源 | 责任 |
|---|---|
| `data/monsters/enemies.json`、`enemy_progression.json` | 前四章身份、基础参数与等级机制 |
| `data/monsters/enemy_species_policy.json` | 显式候选的物种定位参数 |
| `data/rules/numerical.json` | 运行闸门、整数尺度、难度与结算参数 |
| `scripts/domain/combat/enemy_profiles.gd` | 普通怪配置、品阶与实际编成 |
| `scripts/domain/combat/enemy_numbers.gd` | 当前属性和技能包解析 |
| `scripts/domain/combat/enemy_calibration.gd` | 有效冻结校准快照 |
| `scripts/domain/combat/damage_resolver.gd` | 实收伤害与抗性结算 |

生命、攻击、法强、双抗和明确的战斗包在当前尺度计算，完整乘积在结算边界取整；百分比、时间、距离、速度、货币和数量保持各自单位。当前抗性分母1000，默认校准版本14，版本15只在显式候选与独立档中使用。首领使用独立解析，不重复套普通怪成长。

`progressive_monster_roster` 检查登记与编成，`numerical_enemy_skills` 检查实际包、状态、支援和设施，`enemy_art` 检查当前身体注册与碰撞半径。其通过不能替代自然击杀时间、连续整关、资源压力或装备获取验证。技能身份见 [技能登记](../combat/ordinary_monster_expansion.md)，共用结算见 [数值总则](level_equipment_numerical_design.md)。
