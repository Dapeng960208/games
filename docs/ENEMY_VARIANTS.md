# 前四副本野怪外观与技能图索引

更新日期：2026-10-01。本文记录已接入的普通野怪外观资源、分配规则和定向检查证据。36 个普通怪原型继续使用各自的行为、攻击序列、预警、属性与导航半径；新增索引只控制身体外观。完整逐帧动画和自然群战平衡仍待完善。

## 正式源图与元数据

以下 9 张源 PNG 已存在并接入运行路径。本次补齐和校验元数据没有重新生成或编辑这些源图；B03 的 M27 铲兵补充图此前由本轮主代理使用内置 ImageGen 生成，来源提示保存在对应 `.prompt.json`。所有元数据使用 `source_family = storybook_2_5d_v1`。

| 正式源图 | 真实身体数与原型分配 | 技能图 | 来源提示与区域元数据 |
|---|---|---|---|
| [storybook_B01_variants_v1.png](../assets/generated/enemies/storybook_B01_variants_v1.png) | 72：M01–M09 各 8 个；9 列原型、8 行身体 | 9：M01–M09 各 1 个，末行 | [prompt](../assets/generated/enemies/storybook_B01_variants_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B01_variants_v1.regions.json) |
| [storybook_B02_variants_v1.png](../assets/generated/enemies/storybook_B02_variants_v1.png) | 72：M10–M18 各 8 个；9 列原型、8 行身体 | 9：M10–M18 各 1 个，末行 | [prompt](../assets/generated/enemies/storybook_B02_variants_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B02_variants_v1.regions.json) |
| [storybook_B03_variants_v1.png](../assets/generated/enemies/storybook_B03_variants_v1.png) | 72：M19–M27 各 8 个；9 列原型、8 行身体 | 9：M19–M27 各 1 个，末行 | [prompt](../assets/generated/enemies/storybook_B03_variants_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B03_variants_v1.regions.json) |
| [storybook_B04_variants_v1.png](../assets/generated/enemies/storybook_B04_variants_v1.png) | 63：M28–M36 各 7 个；9 列原型、实际 7 行身体 | 9：M28–M36 各 1 个，末行 | [prompt](../assets/generated/enemies/storybook_B04_variants_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B04_variants_v1.regions.json) |
| [storybook_B01_reinforcements_v1.png](../assets/generated/enemies/storybook_B01_reinforcements_v1.png) | 64：8×8；每行前 4 列为 M01、后 4 列为 M04，各 32 个 | 0；沿用第一批本原型技能图 | [prompt](../assets/generated/enemies/storybook_B01_reinforcements_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B01_reinforcements_v1.regions.json) |
| [storybook_B02_reinforcements_v1.png](../assets/generated/enemies/storybook_B02_reinforcements_v1.png) | 64：8×8；每行前 4 列为 M10、后 4 列为 M14，各 32 个 | 0；沿用第一批本原型技能图 | [prompt](../assets/generated/enemies/storybook_B02_reinforcements_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B02_reinforcements_v1.regions.json) |
| [storybook_B03_reinforcements_v1.png](../assets/generated/enemies/storybook_B03_reinforcements_v1.png) | 64：8×8，全部为 M19 提灯哨兵 | 0；沿用第一批 M19 技能图 | [prompt](../assets/generated/enemies/storybook_B03_reinforcements_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B03_reinforcements_v1.regions.json) |
| [storybook_B04_reinforcements_v1.png](../assets/generated/enemies/storybook_B04_reinforcements_v1.png) | 64：8×8，全部为 M28 斧兵 | 0；沿用第一批 M28 技能图 | [prompt](../assets/generated/enemies/storybook_B04_reinforcements_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B04_reinforcements_v1.regions.json) |
| [storybook_B03_shovels_v1.png](../assets/generated/enemies/storybook_B03_shovels_v1.png) | 64：8×8，全部为 M27 节拍铲兵 | 0；沿用第一批 M27 技能图 | [prompt](../assets/generated/enemies/storybook_B03_shovels_v1.prompt.json) · [regions](../assets/generated/enemies/storybook_B03_shovels_v1.regions.json) |

合计 **599 个身体区域与 36 个技能图**。身体池中 M01、M04、M10、M14 各 40 个；M19、M27 各 72 个；M28 为 71 个；其余 B01–B03 原型各 8 个，其余 B04 原型各 7 个。技能图不计作身体外观，也不计入重复率的独立身体数。

第一批已批准的 `region`、`foot`、`source_height`、`skill_icons` 原样保留。第二批图集拓扑为 8×8，实际像素分界存在少量偏移：工具在预期等分线的 ±20% 格宽窗口中寻找 `alpha > 32` 覆盖最少的分界，再对每格全部有效 alpha 求紧边界，保留独立武器和悬浮附件。`foot` 使用该区域中心 x 与独占底线 y，`source_height` 为区域高度；记录的是绘制注册锚点，导航与伤害碰撞继续使用原型的运行半径。

每份 `.regions.json` 的 `source` 记录生成方式、对应 `prompt_metadata`、源 PNG SHA-256、原始 RGBA SHA-256、原图尺寸、网格与足点规则。每个身体项另有真实纹理路径、`variant_id`、`source_cell`、`pixel_sha256`；`validation` 记录区域、脚点、数量与去重结果。源图始终保持原始 RGBA 像素，不通过 Python 重绘、换色或重写 PNG。

## 构建与资源验证

工具为 [tools/build_enemy_variants.py](../tools/build_enemy_variants.py)，需要带 Pillow 的 Python 3，可使用 Codex 工作区提供的依赖运行时。默认和 `--check` 都只校验；`--write` 只写区域 JSON 和来源元数据，不写源 PNG。

在仓库根目录运行：

```powershell
python tools/build_enemy_variants.py --check
```

需要根据现有源图更新元数据时运行：

```powershell
python tools/build_enemy_variants.py --write
```

本轮 `--check` 通过：599 个身体的区域、底线足点、来源高度与原图边界有效，36 个技能图均在第一批末行；599 个实际 `texture + region` 和 599 个精确 RGBA 区域指纹均不同，0 重复。工具执行前后检查的 15 份匹配源 PNG 哈希一致，其中包括本索引 9 张图以外的现有匹配来源。精确指纹不同仅证明像素不同，不代表所有造型在主观上同样容易辨认。

## 运行分配、技能显示与回退

[EnemyArt](../scripts/combat/enemy_art.gd) 的 `entry_for()` 继续返回原来的默认身体，供独立角色、旧调用和预览使用。变体通过 `variant_entry_for()` 读取；加载身体池时以真实纹理路径和区域去重，共用同一纹理区域的别名不能增加外观数量。

[MineRoom.spawn_enemy()](../scripts/combat/room.gd) 在确认出生点有效之后、节点进入 `_ready()` 之前，将 `profile.visual_variant_index` 写入敌人。房间为每个原型独立记录累计生成序号，前波敌人死亡后不删除计数。循环起点由 `layout_id + layout_seed + enemy_id` 决定，每个池先用完未出现的区域，再循环重复；它不读取或推进游戏 RNG，也不修改原型属性、威胁值、并发上限和有限波次。机关与静态技能端点不分配变体。同房同种子重新载入时也重置计数，以保持重放一致。

[EnemyVisual](../scripts/combat/enemy_visual.gd) 使用选中区域完成足点映射，保留原有姿态变换、受击反馈和独立材质。旧动作银行只属于原始原型，不能在走路、预警、执行、收势或受击时覆盖已经选中的身体变体。M35 的携物与空手状态也保留本次身体。

技能徽章使用第一批 `skill_icons` 的本原型插画，独立于身体材质和镜像。它依据实际 `brain.current_telegraph()` 显示预警、锁定与连招阶段，并在本次执行阶段延续显示；结束施法后退场。降低特效保留徽章和关键地面预警，图标资源缺失时显示通用警示。无效外观索引回退到默认身体；某份新图或元数据不可用时，跳过该资源并保留现有默认身体与表现回退。

## 定向检查证据与边界

通过 [tools/test.ps1](../tools/test.ps1) 运行，全部使用新建的隔离存档目录，不接触实际玩家档：

```powershell
& ./tools/test.ps1 -Suite @('enemy_variant_budget','enemy_variants') -SkipImport -SkipRestart -Graphical
```

Godot 4.7.2、RTX 3060 的真实 GPU 结果为：

| 检查 | 结果 | 覆盖 |
|---|---|---|
| [test_enemy_variant_budget.gd](../tests/test_enemy_variant_budget.gd) | 793 项，0 失败 | 24 个普通房间 × 5 档难度，共 120 个组合；整房所有有限遭遇波次的真实身体区域分配；36 原型身体池与技能图；分配不消耗游戏 RNG |
| [test_enemy_variants.gd](../tests/test_enemy_variants.gd) | 475 项，0 失败 | L15 与 L19 极限难度逐波真实生成；外观进入 `_ready()` 前分配；原行为、导航半径、出生点、源足点、alpha 接触点；姿态不回旧皮；同种子重新进房；M27 实际施法徽章、降低特效、缺图回退与静态端点计数 |

重复率定义为 `(整房累计生成数 − 独立身体 texture + region 数) / 整房累计生成数`。分母包含三个战区的初始与全部有限后续遭遇波次，已经死亡或退场的敌人仍计入；机关、技能图、尸体和动作帧不计作独立普通怪身体。120 个组合的最高重复率为 **0%**，满足严格 `<30%`。这个检查口径不包含可反复触发的技能召唤、首领召唤或无限时长战斗，不能据此承诺任意新增生成路径的累计重复率。

L15 极限难度实际生成 53 只敌人、使用 53 个独立身体区域；L19 为 58 只、58 个。测试逐批调用真实波次生成路径并清理前波以控制并发，验证的是有限计划和运行表现，不是自然游玩中三秒增援节奏或战斗难度的完整验收。日志没有额外脚本或引擎错误。

本次查看的临时实机截图位于隔离目录，未加入 Git，清理该临时目录后链接将失效：

- [L15 第二战区实际波次](../tools/godot/test-runs/20261001T102636199-c37b35e9/L15_enemy_variants.png)
- [L19 第二战区实际波次](../tools/godot/test-runs/20261001T102636199-c37b35e9/L19_enemy_variants.png)

图像中可见同原型的身体造型差异，身体裁切和足点已校对。完整逐帧变体动作、全部朝向和连招的主观可读性、密集群战遮挡与自然难度平衡仍待后续游玩打磨，不因素材数量或检查通过而记为完成。
