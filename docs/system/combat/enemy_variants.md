# 前四副本野怪外观与技能图索引

> 状态：当前参考：具体已实现范围以开发进度和运行代码为准。

## 2026-10-02扩充：54种身份与新增18张原生高清身体

当前四关9/12/15/18种普通怪。M37–M54的18张独立原生1254×1254 RGBA已生成并逐张目视检查，同一原始PNG供高清图鉴和战斗身体使用，无插值放大、换色复用或Python重绘。新身体没有完整逐帧动画；延用姿态变换，不把静态立绘说成完整动作。

18份独立manifest登记source_family、原始纹理、alpha区域、foot、source_height和SHA-256。区域以alpha≥16有效内容加4像素边距确定，排除近乎透明的生成扩散噪点，原PNG像素不变。新物种没有旧Mxx_v1图，EnemyArt特别按普通怪解剖高度clamp(导航半径×3.8,66,88)×1.20与足点y=18注册，避免继承rust_mite回退的y=38；导航/伤害半径不变。

来源与生成提示见新增18种provenance](../../../assets/system/ui/common/ui\refactor_v1\codex/provenance_new_monsters.json)。Godot4.7.2实际MineEnemy加载、真实纹理/region、脚点、碰撞不变、各行动阶段身份与独立徽章271项通过；这是运行注册检查，新增战斗UI的最终GPU像素检查见验收记录。

| ID | 原生图鉴/身体 | region | foot / source_height | manifest |
|---|---|---|---|---|
| M37 | [1254² PNG](../../../assets/levels/b02/enemies/m37/art/codex_portrait.png) | [154, 157, 993, 988] | [650.5, 1145] / 988 | [元数据](../../../assets/levels/b02/enemies/m37/art/body.regions.json) |
| M38 | [1254² PNG](../../../assets/levels/b02/enemies/m38/art/codex_portrait.png) | [48, 67, 1162, 1142] | [629.0, 1209] / 1142 | [元数据](../../../assets/levels/b02/enemies/m38/art/body.regions.json) |
| M39 | [1254² PNG](../../../assets/levels/b02/enemies/m39/art/codex_portrait.png) | [27, 208, 1217, 892] | [635.5, 1100] / 892 | [元数据](../../../assets/levels/b02/enemies/m39/art/body.regions.json) |
| M40 | [1254² PNG](../../../assets/levels/b03/enemies/m40/art/codex_portrait.png) | [113, 50, 1130, 1179] | [678.0, 1229] / 1179 | [元数据](../../../assets/levels/b03/enemies/m40/art/body.regions.json) |
| M41 | [1254² PNG](../../../assets/levels/b03/enemies/m41/art/codex_portrait.png) | [27, 50, 1221, 1169] | [637.5, 1219] / 1169 | [元数据](../../../assets/levels/b03/enemies/m41/art/body.regions.json) |
| M42 | [1254² PNG](../../../assets/levels/b03/enemies/m42/art/codex_portrait.png) | [58, 42, 1159, 1173] | [637.5, 1215] / 1173 | [元数据](../../../assets/levels/b03/enemies/m42/art/body.regions.json) |
| M43 | [1254² PNG](../../../assets/levels/b03/enemies/m43/art/codex_portrait.png) | [173, 121, 964, 1033] | [655.0, 1154] / 1033 | [元数据](../../../assets/levels/b03/enemies/m43/art/body.regions.json) |
| M44 | [1254² PNG](../../../assets/levels/b03/enemies/m44/art/codex_portrait.png) | [27, 63, 1201, 1165] | [627.5, 1228] / 1165 | [元数据](../../../assets/levels/b03/enemies/m44/art/body.regions.json) |
| M45 | [1254² PNG](../../../assets/levels/b03/enemies/m45/art/codex_portrait.png) | [109, 103, 1125, 1106] | [671.5, 1209] / 1106 | [元数据](../../../assets/levels/b03/enemies/m45/art/body.regions.json) |
| M46 | [1254² PNG](../../../assets/levels/b04/enemies/m46/art/codex_portrait.png) | [29, 26, 1213, 1198] | [635.5, 1224] / 1198 | [元数据](../../../assets/levels/b04/enemies/m46/art/body.regions.json) |
| M47 | [1254² PNG](../../../assets/levels/b04/enemies/m47/art/codex_portrait.png) | [52, 105, 1188, 1072] | [646.0, 1177] / 1072 | [元数据](../../../assets/levels/b04/enemies/m47/art/body.regions.json) |
| M48 | [1254² PNG](../../../assets/levels/b04/enemies/m48/art/codex_portrait.png) | [121, 15, 1113, 1228] | [677.5, 1243] / 1228 | [元数据](../../../assets/levels/b04/enemies/m48/art/body.regions.json) |
| M49 | [1254² PNG](../../../assets/levels/b04/enemies/m49/art/codex_portrait.png) | [39, 109, 1197, 1055] | [637.5, 1164] / 1055 | [元数据](../../../assets/levels/b04/enemies/m49/art/body.regions.json) |
| M50 | [1254² PNG](../../../assets/levels/b04/enemies/m50/art/codex_portrait.png) | [45, 152, 1201, 983] | [645.5, 1135] / 983 | [元数据](../../../assets/levels/b04/enemies/m50/art/body.regions.json) |
| M51 | [1254² PNG](../../../assets/levels/b04/enemies/m51/art/codex_portrait.png) | [7, 185, 1243, 954] | [628.5, 1139] / 954 | [元数据](../../../assets/levels/b04/enemies/m51/art/body.regions.json) |
| M52 | [1254² PNG](../../../assets/levels/b04/enemies/m52/art/codex_portrait.png) | [41, 41, 1195, 1171] | [638.5, 1212] / 1171 | [元数据](../../../assets/levels/b04/enemies/m52/art/body.regions.json) |
| M53 | [1254² PNG](../../../assets/levels/b04/enemies/m53/art/codex_portrait.png) | [62, 57, 1174, 1161] | [649.0, 1218] / 1161 | [元数据](../../../assets/levels/b04/enemies/m53/art/body.regions.json) |
| M54 | [1254² PNG](../../../assets/levels/b04/enemies/m54/art/codex_portrait.png) | [248, 101, 832, 1011] | [664.0, 1112] / 1011 | [元数据](../../../assets/levels/b04/enemies/m54/art/body.regions.json) |

54种施法呈现读各自enemy_id、ability_id、icon_id、vfx_identity及实际预警/锁定/阶段；既有36种沿用手绘技能图，新18种使用稳定、形状与内标记组合各不相同的身份徽章。所有怪保留来源徽章，最多两张详细技能卡，当前目标和近处已锁定威胁优先；低特效/关闭可选技能路径仍保留关键危险边界。不是把所有技能都画成无来源的一种闪光。

图鉴与战斗共用enemy_ability_catalog；完整效果、反制、数值见[逐怪技能册](ordinary_monster_expansion.md)，当前V2短预警与旧V1区别见[时序表](../balance/enemy_warning_timing.md)。下方599身体区域与36技能图是原M01–M36的历史资源集合和历史去重证据；不得把旧120计划的0重复率套给本轮追加物种，新18种目前每种只有一张独立身体。

## 原M01–M36资源与历史验证

更新日期：2026-10-01。本文记录已接入的普通野怪外观资源、分配规则和定向检查证据。36 个普通怪原型继续使用各自的行为、攻击序列、预警、属性与导航半径；新增索引只控制身体外观。完整逐帧动画和自然群战平衡仍待完善。

## 正式源图与元数据

以下 9 张源 PNG 已存在并接入运行路径。本次补齐和校验元数据没有重新生成或编辑这些源图；B03 的 M27 铲兵补充图此前由本轮主代理使用内置 ImageGen 生成，来源提示保存在对应 `.prompt.json`。所有元数据使用 `source_family = storybook_2_5d_v1`。

| 正式源图 | 真实身体数与原型分配 | 技能图 | 来源提示与区域元数据 |
|---|---|---|---|
| [storybook_B01_variants_v1.png](../../../assets/levels/b01/enemies/shared/b01_variants.png) | 72：M01–M09 各 8 个；9 列原型、8 行身体 | 9：M01–M09 各 1 个，末行 | [prompt](../../../assets/levels/b01/enemies/shared/b01_variants.prompt.json) · [regions](../../../assets/levels/b01/enemies/shared/b01_variants.regions.json) |
| [storybook_B02_variants_v1.png](../../../assets/levels/b02/enemies/shared/b02_variants.png) | 72：M10–M18 各 8 个；9 列原型、8 行身体 | 9：M10–M18 各 1 个，末行 | [prompt](../../../assets/levels/b02/enemies/shared/b02_variants.prompt.json) · [regions](../../../assets/levels/b02/enemies/shared/b02_variants.regions.json) |
| [storybook_B03_variants_v1.png](../../../assets/levels/b03/enemies/shared/b03_variants.png) | 72：M19–M27 各 8 个；9 列原型、8 行身体 | 9：M19–M27 各 1 个，末行 | [prompt](../../../assets/levels/b03/enemies/shared/b03_variants.prompt.json) · [regions](../../../assets/levels/b03/enemies/shared/b03_variants.regions.json) |
| [storybook_B04_variants_v1.png](../../../assets/levels/b04/enemies/shared/b04_variants.png) | 63：M28–M36 各 7 个；9 列原型、实际 7 行身体 | 9：M28–M36 各 1 个，末行 | [prompt](../../../assets/levels/b04/enemies/shared/b04_variants.prompt.json) · [regions](../../../assets/levels/b04/enemies/shared/b04_variants.regions.json) |
| [storybook_B01_reinforcements_v1.png](../../../assets/levels/b01/enemies/shared/b01_reinforcements.png) | 64：8×8；每行前 4 列为 M01、后 4 列为 M04，各 32 个 | 0；沿用第一批本原型技能图 | [prompt](../../../assets/levels/b01/enemies/shared/b01_reinforcements.prompt.json) · [regions](../../../assets/levels/b01/enemies/shared/b01_reinforcements.regions.json) |
| [storybook_B02_reinforcements_v1.png](../../../assets/levels/b02/enemies/shared/b02_reinforcements.png) | 64：8×8；每行前 4 列为 M10、后 4 列为 M14，各 32 个 | 0；沿用第一批本原型技能图 | [prompt](../../../assets/levels/b02/enemies/shared/b02_reinforcements.prompt.json) · [regions](../../../assets/levels/b02/enemies/shared/b02_reinforcements.regions.json) |
| [storybook_B03_reinforcements_v1.png](../../../assets/levels/b03/enemies/shared/b03_reinforcements.png) | 64：8×8，全部为 M19 提灯哨兵 | 0；沿用第一批 M19 技能图 | [prompt](../../../assets/levels/b03/enemies/shared/b03_reinforcements.prompt.json) · [regions](../../../assets/levels/b03/enemies/shared/b03_reinforcements.regions.json) |
| [storybook_B04_reinforcements_v1.png](../../../assets/levels/b04/enemies/shared/b04_reinforcements.png) | 64：8×8，全部为 M28 斧兵 | 0；沿用第一批 M28 技能图 | [prompt](../../../assets/levels/b04/enemies/shared/b04_reinforcements.prompt.json) · [regions](../../../assets/levels/b04/enemies/shared/b04_reinforcements.regions.json) |
| [storybook_B03_shovels_v1.png](../../../assets/levels/b03/enemies/shared/b03_shovels.png) | 64：8×8，全部为 M27 节拍铲兵 | 0；沿用第一批 M27 技能图 | [prompt](../../../assets/levels/b03/enemies/shared/b03_shovels.prompt.json) · [regions](../../../assets/levels/b03/enemies/shared/b03_shovels.regions.json) |

合计 **599 个身体区域与 36 个技能图**。身体池中 M01、M04、M10、M14 各 40 个；M19、M27 各 72 个；M28 为 71 个；其余 B01–B03 原型各 8 个，其余 B04 原型各 7 个。技能图不计作身体外观，也不计入重复率的独立身体数。

第一批已批准的 `region`、`foot`、`source_height`、`skill_icons` 原样保留。第二批图集拓扑为 8×8，实际像素分界存在少量偏移：工具在预期等分线的 ±20% 格宽窗口中寻找 `alpha > 32` 覆盖最少的分界，再对每格全部有效 alpha 求紧边界，保留独立武器和悬浮附件。`foot` 使用该区域中心 x 与独占底线 y，`source_height` 为区域高度；记录的是绘制注册锚点，导航与伤害碰撞继续使用原型的运行半径。

每份 `.regions.json` 的 `source` 记录生成方式、对应 `prompt_metadata`、源 PNG SHA-256、原始 RGBA SHA-256、原图尺寸、网格与足点规则。每个身体项另有真实纹理路径、`variant_id`、`source_cell`、`pixel_sha256`；`validation` 记录区域、脚点、数量与去重结果。源图始终保持原始 RGBA 像素，不通过 Python 重绘、换色或重写 PNG。

## 构建与资源验证

工具为 [tools/assets/monsters/build_enemy_variants.py](../../../tools/assets/monsters/build_enemy_variants.py)，需要带 Pillow 的 Python 3，可使用 Codex 工作区提供的依赖运行时。默认和 `--check` 都只校验；`--write` 只写区域 JSON 和来源元数据，不写源 PNG。

在仓库根目录运行：

```powershell
python tools/assets/monsters/build_enemy_variants.py --check
```

需要根据现有源图更新元数据时运行：

```powershell
python tools/assets/monsters/build_enemy_variants.py --write
```

本轮 `--check` 通过：599 个身体的区域、底线足点、来源高度与原图边界有效，36 个技能图均在第一批末行；599 个实际 `texture + region` 和 599 个精确 RGBA 区域指纹均不同，0 重复。工具执行前后检查的 15 份匹配源 PNG 哈希一致，其中包括本索引 9 张图以外的现有匹配来源。精确指纹不同仅证明像素不同，不代表所有造型在主观上同样容易辨认。

## 运行分配、技能显示与回退

[EnemyArt](../../../scripts/presentation/monsters/enemy_art.gd) 的 `entry_for()` 继续返回原来的默认身体，供独立角色、旧调用和预览使用。变体通过 `variant_entry_for()` 读取；加载身体池时以真实纹理路径和区域去重，共用同一纹理区域的别名不能增加外观数量。

[MineRoom.spawn_enemy()](../../../scripts/gameplay/world/room_controller.gd) 在确认出生点有效之后、节点进入 `_ready()` 之前，将 `profile.visual_variant_index` 写入敌人。房间为每个原型独立记录累计生成序号，前波敌人死亡后不删除计数。循环起点由 `layout_id + layout_seed + enemy_id` 决定，每个池先用完未出现的区域，再循环重复；它不读取或推进游戏 RNG，也不修改原型属性、威胁值、并发上限和有限波次。机关与静态技能端点不分配变体。同房同种子重新载入时也重置计数，以保持重放一致。

[EnemyVisual](../../../scripts/presentation/monsters/enemy_visual.gd) 使用选中区域完成足点映射，保留原有姿态变换、受击反馈和独立材质。旧动作银行只属于原始原型，不能在走路、预警、执行、收势或受击时覆盖已经选中的身体变体。M35 的携物与空手状态也保留本次身体。

技能徽章使用第一批 `skill_icons` 的本原型插画，独立于身体材质和镜像。它依据实际 `brain.current_telegraph()` 显示预警、锁定与连招阶段，并在本次执行阶段延续显示；结束施法后退场。降低特效保留徽章和关键地面预警，图标资源缺失时显示通用警示。无效外观索引回退到默认身体；某份新图或元数据不可用时，跳过该资源并保留现有默认身体与表现回退。

## 定向检查证据与边界

通过 [tools/test.ps1](../../../tools/test.ps1) 运行，全部使用新建的隔离存档目录，不接触实际玩家档：

```powershell
& ./tools/test.ps1 -Suite @('enemy_variant_budget','enemy_variants') -SkipImport -Graphical
```

Godot 4.7.2、RTX 3060 的真实 GPU 结果为：

| 检查 | 结果 | 覆盖 |
|---|---|---|
| [test_enemy_variant_budget.gd](../../../tests/combat/test_enemy_variant_budget.gd) | 793 项，0 失败 | 24 个普通房间 × 5 档难度，共 120 个组合；整房所有有限遭遇波次的真实身体区域分配；36 原型身体池与技能图；分配不消耗游戏 RNG |
| [test_enemy_variants.gd](../../../tests/combat/test_enemy_variants.gd) | 475 项，0 失败 | L15 与 L19 极限难度逐波真实生成；外观进入 `_ready()` 前分配；原行为、导航半径、出生点、源足点、alpha 接触点；姿态不回旧皮；同种子重新进房；M27 实际施法徽章、降低特效、缺图回退与静态端点计数 |

重复率定义为 `(整房累计生成数 − 独立身体 texture + region 数) / 整房累计生成数`。分母包含三个战区的初始与全部有限后续遭遇波次，已经死亡或退场的敌人仍计入；机关、技能图、尸体和动作帧不计作独立普通怪身体。120 个组合的最高重复率为 **0%**，满足严格 `<30%`。这个检查口径不包含可反复触发的技能召唤、首领召唤或无限时长战斗，不能据此承诺任意新增生成路径的累计重复率。

L15 极限难度实际生成 53 只敌人、使用 53 个独立身体区域；L19 为 58 只、58 个。测试逐批调用真实波次生成路径并清理前波以控制并发，验证的是有限计划和运行表现，不是自然游玩中三秒增援节奏或战斗难度的完整验收。日志没有额外脚本或引擎错误。

当时查看的 L15、L19 第二战区临时实机截图位于隔离目录，未加入 Git；该目录没有随当前工作树保留。需要重新查看时，使用上述图形检查入口生成新的截图，不把已失效的本地路径作为当前证据链接。

图像中可见同原型的身体造型差异，身体裁切和足点已校对。完整逐帧变体动作、全部朝向和连招的主观可读性、密集群战遮挡与自然难度平衡仍待后续游玩打磨，不因素材数量或检查通过而记为完成。
