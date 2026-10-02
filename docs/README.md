# 游戏开发文档索引

当前需求、实际进度、代码待办与规范集中维护于本目录。重复的旧阶段计划、过时状态和旧 UI 文档清理，批准图纸、来源和许可保留。

| 文档 | 用途 |
|---|---|
| [开发进度](DEVELOPMENT_PROGRESS.md) | 实际接入、证据、限制和未完成内容 |
| [代码待办与十二关路线图](LEVEL_ROADMAP.md) | 优先级、代码入口、依赖及完成条件 |
| [开发规范](DEVELOPMENT_STANDARDS.md) | 视觉、地图、操作、保存、资源与提交约定 |
| [玩法、成长与长期可玩性审查（2026-10-01）](audits/GAMEPLAY_AUDIT_2026-10-01.md) | 固定提交的源码证据、竞品研究、12 项发现、长期循环提案和待执行实机验收；不替代实际进度 |
| [成长数值快照模型](audits/progression_snapshot_2026_10_01.py) | 复算路线、经验台阶、遗物终态和五档奖励；非引擎测试，不读取当前游戏数据 |
| [第二轮审查：跨系统规则与新增问题](audits/GAMEPLAY_AUDIT_ROUND2_2026-10-01.md) | A13–A30 共18项：奖励折算、存档兼容/体积、强化、补给、职业配装、状态和UI逻辑；区分源码事实、离线模型与待验证风险 |
| [第二轮交互规则模型](audits/interaction_models_2026_10_01.py) | 20项独立模型检查；含合成账本体积、初始强化平台和奖励策略；不运行Godot、不读取或修改玩家档案 |
| [用户确认需求](USER_LEVEL_BRIEF.md) | 十二种族与后续玩法、美术要求 |
| [关卡和装备设计](LEVEL_DESIGN_V1.md) | 目标与数值草案，不代表已经实现 |
| [54普通怪与难度技能](ORDINARY_MONSTER_EXPANSION.md) | 9/12/15/18种、逐怪基础和D1–D4技能、反制、实际房间编成 |
| [敌人与首领短预警](balance/ENEMY_WARNING_TIMING.md) | 全54种与40首领招式的旧值/五难度新时序、家族下限和实际释放同步 |
| [普通怪当前数值](balance/ORDINARY_MONSTER_NUMBERS.md) | 新18种基础值、54种×五难度解析、伤害与恢复公式 |
| [前四关设计](levels/) | 背景、敌人、首领、装备、地图与遗物 |
| [28 房设计册](levels/fixed_layouts/index.html) | 固定蓝图、目标效果及当前实机截图 |
| [摆放分组草稿](drafts/room-placement-20261001/README.md) | 未接入的分组方案 |
| [全部28房原生细节验收](ui/WORLD_2K_CLARITY.md) | 原生分块、五镜头对齐、资源生命周期与无缓存复现结果 |
| [四首领战斗高清采样](ui/BOSS_2K_CLARITY.md) | 正确身份、脚点、碰撞与实际2K状态验证 |
| [普通怪精确变体高清采样](ui/ENEMY_VARIANT_2K_CLARITY.md) | 精确外观键保留、采样尺寸与验收范围 |
| [世界交互文字可读性](ui/WORLD_LABEL_CONTRAST.md) | 字重、独立底板和实际中英2K文字检查 |
| [追加18条变体与虚拟采样](ui/ENEMY_VARIANT_HD_BATCH_2.md) | 22条精确覆盖、双向/死亡/透明翼采样结果与保留限制 |
| [七天存档回收站](SAVE_RECYCLE_BIN.md) | 删除/新建覆盖归档、冲突保护、恢复和到期清理边界 |
| [素材版权](ASSET_LICENSES.md) | 美术、音频与字体来源 |
| [Godot 第三方声明](GODOT_THIRD_PARTY.txt) | 引擎第三方许可 |
| [工作区清理记录](WORKSPACE_CLEANUP.md) | 清理范围和保留原则 |

发生冲突时，以实际代码和进度记录为准。设计说明想做什么，路线图说明下一步如何做，进度说明已经做到了什么。后续更新对应条目，不再复制整套新计划。

- [第二轮 A13–A30 修复与验收](audits/GAMEPLAY_AUDIT_ROUND2_FIXES_2026-10-01.md)：运行代码、安全兼容、逐项引擎证据与仍需自然游玩验证的边界。

三职业定位、独立成长、八向动作和职业装备限制已接入并完成针对性验收，详见[方案与实际验收](character-optimization/ROLE_OPTIMIZATION_2026-10-02.md)。自然长期玩法及S11全量平衡仍未完成。

- [骷髅召唤职业完整设计（未实装）](character-optimization/SKELETON_SUMMONER_DESIGN_2026-10-02.md)：召唤技能、全属性继承、套装、遗物和验收设计，数值待验证。
