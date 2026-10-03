# B05 实际宿主与有限战斗检查

日期：2026-10-02。范围是隔离候选，不是 B05 正式发布或完整自然平衡验收。
引擎 Godot 4.6.3；本报告新增检查均为 headless。相关图形环境为 Mesa
llvmpipe 软件渲染，不能据此宣称硬件 GPU 性能。本轮没有新增截图或像素可读性结论。
B06 继续禁用。真实玩家档没有读取、复制或修改。

## 发现并修复的真实入口问题

1. **固定信标数量不匹配**：L25 路线 seed54873、房间 seed159602 的实际
   `MineRoom.prepare_expedition_node` 被 `RoomProps` 的固定三个信标要求拒绝。
   B05 冻结图只有一个信标，部分首领图没有。`9f182ff` 按 B05 实际 authored
   anchors 配置，保留前四章三个信标约定，没有新增或移动冻结点。
2. **未打波次也能结算**：B05 普通目标允许空 objective directive，而旧待完成
   判断忽略这些区域。实际 L26/L28/L29 可零敌结算，其他房可只打一波。
   `9f182ff` 将 B05 完成门槛接到有限 encounter exhaustion，保留空间触发。
3. **BO05 真实入口未接入**：`BossLayouts` 只接受 BO01–BO04。`467f1ca`
   增加仅候选进程可用的 BO05 冻结布局分支，默认四章及 BO06 禁用不变。
4. **重载后首领结算 ID 不合法**：JSON 数字还原后 Room 创建了
   `:node:11.0:complete`，严格提交协议要求 `:node:11:complete`。
   `31edef5` 仅在 Room 构造事件 ID 时转为整数；没有放宽保存、掉落或收据验证。
   诊断期间对 run_controller 的临时日志已全部撤除。

以上问题由实际 Room/director/Enemy/brain/runtime 路径发现。此前只验证事务的
候选遍历通过，不能覆盖这些入口、波次或运行宿主问题。

## 已通过矩阵

| 检查 | 结果 | 限制 |
|---|---|---|
| 实际候选 UI preflight、L25–L30、BO05 | 主 seed54873：388 checks，0失败 | 控制位置/时间，使用致死测试伤害清场 |
| 有限波次与介绍 | L25 两波；L26–L30 三波；18种实际生成；单区≤6、整房≤18 | 主遍历 D0；另有 D4 满组观察 |
| 结算与重载 | 普通怪死亡信号、首领真实死亡信号、清场提交、每房两次磁盘重载、重复 tick 不增奖 | 不等同于玩家自然打通 |
| 撤离 | BO05 死亡后结算、撤离入库、重复撤离与重载仅计一局 | 合成 BO04 完成前置档 |
| 默认 Boss gate | 6 checks，0失败；BO01–BO04保留、BO05关闭、BO06关闭 | 单独无 candidate flag 运行 |
| M10 定点行为 | 合法外围位置签名释放并造成伤害；主路线安全回退仍可普攻 | 四秒控制时钟、耐久观察者 |
| D4 authored spawn 准入 | 37 checks，0失败；六房17区域/101演员 | 每区域8秒，观察者无敌、非真实平衡 |
| 三职业根井普攻击中 | 23 checks，0失败；战士接近/枪手射线/法师零资源普攻 | 单次攻击路径，不代表法师不用普攻玩法 |
| 三职业 L25 正常战斗 | 28 checks，0失败；正常伤害/生命/资源/移动/QWER | 只涵盖教学房两波，装备拥有为明确夹具假设 |
| BO05行为 | 19 checks，0失败；P1/P2/P3、根井轮换、真实召唤死亡无奖、四秒露芯 | 阶段血线受控；核心 landmark 不是像素可读性证据 |

附加路线 seed7 与 seed26002 的真实入口、完整有限波次和死亡至入库复验结果见下方运行记录。
没有将历史独立门闸/碰撞测试、设计数据校验或截图数计入本报告新增通过数。
本次现存检查无已知失败；下方未测范围仍是验收门槛。

## 准入观察

D4、seed54873、真实 authored spawn、玩家在当前区域中心、每区域8秒：
101名实际演员中93名至少释放一次签名；6名出现一次准入拒绝后使用基础攻击，
另外 M04 因队友满血、M18 因未连网使用条件回退。
拒绝样本是 L27 的 M07/两名M02，L29 的 M13，L30 的 M16/一名M01。
这不支持“多数攻击被抑制”的结论，也不是拒绝率的统计平衡测量。

M10 在 L28/D4 的 `(770,300)`，目标 `(870,300)` 均为合法地面：
`pollen_spray` 从真实脑状态机释放，四秒内总伤害1681。
合法主路线样本 `(1363,841)` 及 `(1400,300)` 的签名被保护走廊规则拒绝，
基础攻击仍造成989伤害。另一非法地面位置的释放记录被明确排除出合法证明。
M10 在 authored spawn 的八秒样本也释放了签名；没有改小保护走廊以强行通过。

## 三职业有限正常战斗

仅 D0 L25，两波共5个自然生成敌人。上限90模拟秒，清场或死亡提前停止；
使用生产输入请求、寻路、预警躲避、弹体、技能部署与伤害，没有改敌人生命、
玩家生命、资源、伤害、冷却或 invulnerable。沿用已有可见信息输入控制器，
法师覆盖掉基础攻击提交函数；未运行 S11 runner 或完整矩阵。

起点为合成 BO04 已完成的 Lv20角色，8槽 B04 合法绿色+3、主属性/词条分位50、
强化每阶10%、19天赋点、Q分支B/R分支A。模板从当前职业合法 B04 掉落池按ID排序选取。
装备拥有/强化是夹具假设，不能证明获取这些装备的自然耗时或真实玩家现有配装。

| 职业 | 清场模拟秒 | 首杀秒 | 末/最大HP | 最低资源 | 技能/普攻 |
|---|---:|---:|---:|---:|---:|
| CH01 战士 | 6.675 | 2.675 | 8243/8243 | 40/1000 | 4 / 5 |
| CH02 枪手 | 5.025 | 0.900 | 6931/6931 | 32/1000 | 4 / 3 |
| CH03 法师 | 9.375 | 1.375 | 6738/6738 | 298/1200 | 8 / 0 |

三职业资源为零累计时间均0。法师同时断言 shots=0、primary_hits=0，证明此短样本
使用技能/资源循环，不是“零资源普攻”替代。前一次相同输入夹具法师末HP为6526，
因此不宣称战斗伤害序列完全确定或可靠无伤。路线/装备描述和种子可重复，
短程自动策略仍受战斗时序、随机与观察调度影响。

按 weapon/head/chest/hands/legs/feet/ring/charm 顺序，战士和法师模板为
EQ10/EQ12/EQ30/EQ32/EQ111/EQ50/EQ112/EQ52；枪手为
EQ09/EQ12/EQ29/EQ32/EQ109/EQ49/EQ110/EQ52。法师为magic、另外两职为physical实例。

## BO05 行为与明确未测

真实候选 arena 自动创建机制宿主和 Boss。阶段血线受控进入1/2/3阶段，
根井数量1/2/2，第三阶段每6秒轮换；正常脑选择实际释放两只 transplant adds。
召唤物通过实际伤害死亡，kills/gold/loot/staged requests 均未增加。
活跃根井实际破坏打开 flower_heart，伤害倍率1.15，4秒后关闭。
已检查活跃身体的 core landmark 存在且有限，未用该字段宣称画面可读。

**仍未验收：** 三职业完整 B04→B05 自然装备获取/全章战斗；L26–L30及BO05正常
生命下的长程职业表现；D0–D4混装全面平衡；完整法师无普攻全章资源循环；
七房画面/拥挤预警/桥门/根井/露芯的最终实际像素阅读；声音输出；硬件GPU性能。
此前独立门闸通路检查不替代上述最终画面或全程自然游玩。

## 复现与运行记录

所有输出和隔离存档由 managed wrapper 管理，不提交日志、临时文件或存档。

```sh
python tools/test_workspace.py run --biome B05 -- godot --headless --path . tests/test_b05_natural_encounters.tscn -- --candidate-b05 --test-profile=user://test_b05_candidate/natural_host.json
python tools/test_workspace.py run --biome B05 -- godot --headless --path . tests/test_b05_natural_encounters.tscn -- --candidate-b05 --test-profile=user://test_b05_candidate/natural_seed7.json --seed=7 --skip-probes
python tools/test_workspace.py run --biome B05 -- godot --headless --path . tests/test_b05_natural_encounters.tscn -- --candidate-b05 --test-profile=user://test_b05_candidate/natural_seed26002.json --seed=26002 --skip-probes
python tools/test_workspace.py run --biome B05 -- godot --headless --path . tests/test_b05_bounded_combat.tscn -- --candidate-b05 --test-profile=user://test_b05_candidate/natural_bounded.json
```

同一 encounters scene 支持 `--probe-signatures`、`--probe-admission`、`--probe-classes`、
`--probe-boss` 独立小检查。`--probe-gates` 配合省略 candidate flag 验证关闭门槛。
测试 profile 文件名必须以 `natural` 开头。

- 主实际宿主：`20261002T152909851116Z-86abc3a6`，388/0。
- 关闭门槛：`20261002T152805000779Z-3a706464`，6/0。
- M10单独：`20261002T151818726189Z-da2a0fac`，6/0。
- authored准入：`20261002T153014459893Z-65080117`，37/0。
- 基础攻击：`20261002T152442239571Z-1f5b5320`，23/0。
- 最终三职业正常战斗：`20261002T153955582091Z-ab3d3659`，28/0。
- Boss行为：`20261002T153858495987Z-7a8a9ff9`，19/0。
- 附加seed7：`20261002T154025862152Z-1ba144ec`，383/0。
- 附加seed26002：`20261002T154045880573Z-2aeffa55`，383/0。

两个附加种子都重新通过实际 preflight、18种生成、有限波次、Boss死亡、每房重载和
撤离入库。未发现新的种子敏感入口或放置失败；这只是三种子的小范围回归。
