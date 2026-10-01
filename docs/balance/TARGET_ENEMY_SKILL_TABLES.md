# 野怪与首领技能目标全表（重构确认稿）

**以下全部是待确认的设计数值，尚未接入游戏。** 当前真实值仍由 [现状怪物与首领附录](CURRENT_ENEMY_BOSS_CATALOG.md) 记录。本册配合 [主方案](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md) 与 [目标属性总表](TARGET_NUMERICAL_TABLES.md)，明确基础值扩大10倍之后每个技能的整数输入。

冻结输入来自 Godot `4.7.2-stable (official)` 对提交 `8daa519f2ea1a7dcc3f422b4df96ac81d65986b9` 的纯 Profile/Brain 导出：[current_enemy_skill_inputs.json](current_enemy_skill_inputs.json)。36原型×4阶=144组普通命令序列，共311个普通命令位置；40个首领技能ID、103个阶段变体、395个有效难度/阶段组合。精英附加命令另计。该文件与 [生成器](../../tools/balance/render_target_enemy_skills.py) 入库后，不依赖忽略的 artifacts 缓存。新倍率同时核对 [主方案参数](numerical_v2_parameters.json)，禁止两份表口径漂移。

## 1. 整数化顺序与适用范围

定义 `R(x)=floor(x+0.5)`，仅接受非负输入；生成器用 Decimal/ROUND_HALF_UP 实现。每个完整属性先计算所有属性层倍率，再 R 一次；技能拿已整数化的演员伤害，乘招式与技能倍率后 R 一次。运行实装须在减伤、追加伤害、每跳状态伤害与治疗/盾实际入账时各 R 一次，不能使用截断或 Python 默认银行家舍入。

章节B按1–12递增：`F_HP(B)=1+0.12×(B−1)`，`F_A(B)=1+0.08×(B−1)`。当前原型M01–M09属于B1、M10–M18属于B2、M19–M27属于B3、M28–M36属于B4；BO01–BO04一一对应B1–B4。章节系数作用演员生命与基础伤害，不二次修改技能damage_multiplier。

本次校准标尺是对应章等级与装备等级的全金装、约+2强化能显著压制本章D4首领；英雄配装输出/生命与实战击杀时间的验证见主方案。敌人只按章/区域与D固定计算，玩家获得更好装备时不会随玩家属性追平。B5–B12目前仅记录公式与标准样例，不能据这些样例宣称关卡已发布。

普通/精英：`HP=R(旧同等级D0生命×1.35×10×F_HP(B)×HP_D)`，`A=R(旧同等级D0伤害×1.35×10×F_A(B)×Damage_D)`。旧 Profile 已包括原型、等级与精英身份，禁止重复叠精英生命1.2/伤害1.12。护甲/魔抗=`R((旧同等级D0双抗+2D)×10)`；既有旧等级防御上限24/32按单位换成240/320，难度加值仍在旧上限之后。所有D难度的本章三区等级固定为`5(B−1)+1 / +3 / +5`，首领固定Lv`5B`；同章提高D只改变难度倍率，不额外抬等级，也不读取玩家等级。

首领：`HP=R(旧章节D0生命×1.35×10×F_HP(B)×HP_D)`，`A=R(旧章节D0伤害×1.35×10×F_A(B)×Damage_D)`；演员始终使用本章Lv5B基准。双抗=`R((旧章节双抗+3D)×10)`。旧首领的`1+0.16D / 1+0.08D`不再叠加；已取消旧方案D3/D4统一Lv20与章节等级差额补正。

普通/精英技能原伤害 `Q=R(A×原招式系数×TierSkill[t]×EnemySkillD[D])`；首领 `Q=R(A×原招式系数×BossSkillD[D]×Phase[P])`。新增技能倍率作用每次命中与持续区域的每一跳，不再乘一次整段总伤害。加速、召唤、治疗、护盾、诱饵、机关交互的命令即使缓存有damage_multiplier=1，也没有直接伤害。M34反击架势auto_release=false，本命令0伤害，随后独立melee命令照表计伤；不能重复算一次counter。

| 难度 | HP_D | Damage_D | 普通技能D倍率 | 首领技能D倍率 |
| --- | --- | --- | --- | --- |
| D0 | 1 | 1 | 1 | 1 |
| D1 | 1.4 | 1.2 | 1.05 | 1.06 |
| D2 | 2 | 1.5 | 1.1 | 1.12 |
| D3 | 2.8 | 1.85 | 1.15 | 1.2 |
| D4 | 4 | 2.3 | 1.2 | 1.3 |


| 阶级 | 参考等级 | 普通额外技能倍率 | 首领阶段 | 首领阶段倍率 |
| --- | --- | --- | --- | --- |
| T1 | 1 | 1 | P1 | 1 |
| T2 | 5 | 1.08 | P2 | 1.1 |
| T3 | 10 | 1.16 | P3 | 1.2 |
| T4 | 15 | 1.25 | — | — |


### 1.1 十二章系数、区域等级与未来接口

| 章节 | 状态 | 三区固定等级（所有D相同） | 首领固定等级 | F_HP | F_A | 现有怪物/首领 |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | 已发布章，数值重构待接入 | 1 / 3 / 5 | 5 | 1 | 1 | M01–M09 / BO01 |
| B2 | 已发布章，数值重构待接入 | 6 / 8 / 10 | 10 | 1.12 | 1.08 | M10–M18 / BO02 |
| B3 | 已发布章，数值重构待接入 | 11 / 13 / 15 | 15 | 1.24 | 1.16 | M19–M27 / BO03 |
| B4 | 已发布章，数值重构待接入 | 16 / 18 / 20 | 20 | 1.36 | 1.24 | M28–M36 / BO04 |
| B5 | 未来公式接口，未制作本章原型 | 21 / 23 / 25 | 25 | 1.48 | 1.32 | — |
| B6 | 未来公式接口，未制作本章原型 | 26 / 28 / 30 | 30 | 1.6 | 1.4 | — |
| B7 | 未来公式接口，未制作本章原型 | 31 / 33 / 35 | 35 | 1.72 | 1.48 | — |
| B8 | 未来公式接口，未制作本章原型 | 36 / 38 / 40 | 40 | 1.84 | 1.56 | — |
| B9 | 未来公式接口，未制作本章原型 | 41 / 43 / 45 | 45 | 1.96 | 1.64 | — |
| B10 | 未来公式接口，未制作本章原型 | 46 / 48 / 50 | 50 | 2.08 | 1.72 | — |
| B11 | 未来公式接口，未制作本章原型 | 51 / 53 / 55 | 55 | 2.2 | 1.8 | — |
| B12 | 未来公式接口，未制作本章原型 | 56 / 58 / 60 | 60 | 2.32 | 1.88 | — |


未来B5–B12仅保留同一公式接口，不声称已有新野怪或Boss。下列与主目标总表使用相同的**M01标准原型归一化样例**：旧Lv1/D0生命60、伤害14，无精英/原型额外倍率；在本章第三区等级L=5B先用目标普通等级成长`HP_old=60×[1+0.055×(L−1)]`、`A_old=14×[1+0.025×(L−1)]`，再校准×1.35×10、章节系数与D倍率后R。D4从完整未舍入属性乘D倍率后R，不能将D0整数再乘D倍率。该样例不是未来真实怪物定稿；当前运行等级仍上限20，扩展章的L21–60仅为目标接口演算。

| 章/标准参考级 | 标准HP D0 | 标准HP D4 | 标准A D0 | 标准A D4 |
| --- | --- | --- | --- | --- |
| B1/Lv5 | 988 | 3953 | 208 | 478 |
| B2/Lv10 | 1356 | 5425 | 250 | 575 |
| B3/Lv15 | 1778 | 7111 | 296 | 681 |
| B4/Lv20 | 2253 | 9011 | 346 | 795 |
| B5/Lv25 | 2781 | 11125 | 399 | 918 |
| B6/Lv30 | 3363 | 13452 | 456 | 1050 |
| B7/Lv35 | 3998 | 15994 | 517 | 1190 |
| B8/Lv40 | 4687 | 18749 | 582 | 1339 |
| B9/Lv45 | 5430 | 21718 | 651 | 1497 |
| B10/Lv50 | 6225 | 24901 | 723 | 1664 |
| B11/Lv55 | 7075 | 28298 | 799 | 1839 |
| B12/Lv60 | 7977 | 31909 | 879 | 2023 |


生命、攻击/法强、护甲/魔抗/穿透、真伤、护盾、治疗、DoT power、可击破端点生命与固定护甲削减属于扩大10倍的战斗数值；百分比/系数、暴击率、概率、移速、射程、距离、角度、数量、时间、金币/经验/材料不做该单位扩大。角色资源上限与回复固定量按主方案×10，但支持次数、受益次数、召唤预算等计数不×10。新增技能倍率不缩短预警/锁定，不增发弹体、召唤或区域。普通已存在的四阶命令数量差异照旧保留。

敌技能命中玩家的减伤输入：`E=max(0,相应防御×状态防御系数−穿透)`，`r=E/(1000+E)`，`Hurt=R(Q×其它合法百分比修正×(1−r)×(1−DR))`；双抗不另设65%上限，独立的通用减伤DR（装备与有效技能/状态）统一封顶65%；真伤绕过双抗。玩家减伤后的护盾扣减与生命扣减均使用整数且总计不得超过 Hurt。例：Q=1000、有效护甲1000得到实伤500；扩大前Q=100、护甲100同样实伤50，单位扩大本身不会改变克制比例。腐蚀已有物理护甲系数0.85、直接受伤1.08；不重复作用到腐蚀自身每跳。敌人承受玩家攻击的独立支援盾仍先于防御吸收，CombatStatus盾仍在减伤后吸收，分别按原顺序结算整数；本册不改变既有盾时序。

状态百分比系数本身保持：burn每1s为`R(power×0.12)`魔法；corrosion每1s为`R(power×0.08)`物理；bleed每1s为`R(power×0.10)`物理；shock下次直伤追加`R(power×0.25)`魔法。默认power=本招整数Q；若原命令显式power为旧绝对值，先×10并乘本招技能倍率再R。减速magnitude与时长保持。状态每跳仍进入1000分母防御公式，表中是减伤前输入。

旧绝对掩体/虫卵生命：`R(旧绝对量×10×该技能倍率)`；掩体/可拆线端点旧1–80生命限制随单位变成10–800，再应用限制，虫卵不套该80旧上限。M06的cover_hp与anchor_health是同一掩体输入的别名，优先anchor_health，只生成一个耐久值。M25充盾同样优先guard_ratio，shield_ratio仅为回退别名，只充一个盾。比例盾/治疗保留原比例字段，实际量=`R(受益者新整数生命×原比例)`；不叠技能阶级/难度/阶段倍率，避免生命与技能倍数复合。旧绝对型护盾/治疗仅×10，不加技能强度；当前命令没有这类绝对输入。破卵扣甲为`R(旧固定扣甲×10)`，不乘技能倍率。支援盾保持35%受益者HP上限、治疗保持15%上限，治疗还受实际缺失生命限制。盾/治疗列以受益者生命等于施法者为演算样例，真实受益者不同则重算。CombatStatus单源盾的50%上限与多来源取最大池仍按其现有实现，不把该规则套到独立支援盾。

## 2. 全部36野怪、四阶命令与普通/精英D0/D4

四阶参考等级依次Lv1/Lv5/Lv10/Lv15，T4在Lv20仍用同一命令序列但基础伤害更高。所有表行叠本原型所属章的F_HP/F_A；D0与D4在**同一参考等级**下比较，是分离阶/章/难度的公式对照样例，不是实际每章都会生成全部四阶。真实本章三区按固定章级1/3/5偏移重新解析Profile并选择对应tier，再套公式；首领为5B，各D不再额外抬L。不能把本表Lv1/5/10/15直接当所有实际房间等级。所有伤害列都是单次/单枚/每跳原伤害，不是整招保证总实伤。冻结序列是初始循环/可用支援次数状态；M17治疗次数耗尽的伤害分支另列，M06掩体冷却期间省略掩体命令，M05奇偶循环只翻转弧线方向、M11奇偶循环只镜像落点、M23奇偶循环切拉/推，伤害公式相同。

### M01 晴辉构装巡庭夹卫（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 810/3240 | 189/435 | 1.近战×1 | 1:14 | 1:189 | 1:522 | — |
| T1/Lv1 | 精英 | 972/3888 | 212/487 | 1.近战×1<br>2.地面区×0.35 | 1:15.68；2:5.488 | 1:212；2:74 | 1:584；2:205 | — |
| T2/Lv5 | 普通 | 988/3953 | 208/478 | 1.近战×1<br>2.近战×1 | 1:15.4；2:15.4 | 1:225；2:225 | 1:619；2:619 | — |
| T2/Lv5 | 精英 | 1186/4743 | 233/536 | 1.近战×1<br>2.近战×1<br>3.地面区×0.35 | 1:17.248；2:17.248；3:6.0368 | 1:252；2:252；3:88 | 1:695；2:695；3:243 | — |
| T3/Lv10 | 普通 | 1211/4844 | 232/533 | 1.位移攻击×0<br>2.近战×1<br>3.近战×1 | 1:0；2:17.15；3:17.15 | 1:0；2:269；3:269 | 1:0；2:742；3:742 | — |
| T3/Lv10 | 精英 | 1453/5813 | 259/596 | 1.位移攻击×0<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:19.208；3:19.208；4:6.7228 | 1:0；2:300；3:300；4:105 | 1:0；2:830；3:830；4:290 | — |
| T4/Lv15 | 普通 | 1434/5735 | 255/587 | 1.位移攻击×0<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:18.9；3:18.9；4:18.9 | 1:0；2:319；3:319；4:319 | 1:0；2:881；3:881；4:881 | — |
| T4/Lv15 | 精英 | 1720/6882 | 286/657 | 1.位移攻击×0<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:21.168；3:21.168；4:21.168；5:7.4088 | 1:0；2:358；3:358；4:358；5:125 | 1:0；2:986；3:986；4:986；5:345 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T2-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-24.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=24.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.9`；`landing_only=false`；`path_mode="line"`；`radius=12.0`；`range=68.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=30.0` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-42.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=42.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=false`；`path_mode="line"`；`radius=12.0`；`range=68.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=30.0` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-42.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=42.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=2.00712863979348`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M02 晴辉构装冲锋蛛卫（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1053/4212 | 216/497 | 1.位移攻击×1 | 1:16 | 1:216 | 1:596 | — |
| T1/Lv1 | 精英 | 1264/5054 | 242/556 | 1.位移攻击×1<br>2.地面区×0.35 | 1:17.92；2:6.272 | 1:242；2:85 | 1:667；2:234 | — |
| T2/Lv5 | 普通 | 1285/5139 | 238/546 | 1.位移攻击×1<br>2.近战×1 | 1:17.6；2:17.6 | 1:257；2:257 | 1:708；2:708 | — |
| T2/Lv5 | 精英 | 1542/6166 | 266/612 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:19.712；2:19.712；3:6.8992 | 1:287；2:287；3:101 | 1:793；2:793；3:278 | — |
| T3/Lv10 | 普通 | 1574/6297 | 265/609 | 1.位移攻击×1<br>2.近战×1 | 1:19.6；2:19.6 | 1:307；2:307 | 1:848；2:848 | — |
| T3/Lv10 | 精英 | 1889/7556 | 296/682 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:21.952；2:21.952；3:7.6832 | 1:343；2:343；3:120 | 1:949；2:949；3:332 | — |
| T4/Lv15 | 普通 | 1864/7455 | 292/671 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1 | 1:21.6；2:21.6；3:21.6 | 1:365；2:365；3:365 | 1:1007；2:1007；3:1007 | — |
| T4/Lv15 | 精英 | 2237/8946 | 327/751 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:24.192；2:24.192；3:24.192；4:8.4672 | 1:409；2:409；3:409；4:143 | 1:1127；2:1127；3:1127；4:394 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=false`；`path_mode="line"`；`radius=23.0`；`range=270.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=215.0`；`wall_stun_seconds=1.2` |
| T2-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.3`；`landing_only=false`；`path_mode="line"`；`radius=23.0`；`range=270.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=215.0`；`wall_stun_seconds=1.2` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=55.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.3`；`fixed_cycle_direction=true`；`radius=36.0`；`range=72.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.3`；`landing_only=false`；`path_mode="line"`；`radius=23.0`；`range=270.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=215.0`；`wall_stun_seconds=1.2` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=55.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.3`；`fixed_cycle_direction=true`；`radius=36.0`；`range=72.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.6`；`landing_only=false`；`path_mode="line"`；`radius=23.0`；`range=270.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=215.0`；`wall_stun_seconds=1.6` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=55.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=36.0`；`range=72.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-55.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=36.0`；`range=72.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M03 晴辉构装远程炮手（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 648/2592 | 176/404 | 1.弹体×1 | 1:13 | 1:176 | 1:485 | — |
| T1/Lv1 | 精英 | 778/3110 | 197/452 | 1.弹体×1<br>2.地面区×0.35 | 1:14.56；2:5.096 | 1:197；2:69 | 1:542；2:190 | — |
| T2/Lv5 | 普通 | 791/3162 | 193/444 | 1.弹体×1 | 1:14.3 | 1:208 | 1:575 | — |
| T2/Lv5 | 精英 | 949/3795 | 216/497 | 1.弹体×1<br>2.地面区×0.35 | 1:16.016；2:5.6056 | 1:233；2:82 | 1:644；2:225 | — |
| T3/Lv10 | 普通 | 969/3875 | 215/494 | 1.弹体×1 | 1:15.925 | 1:249 | 1:688 | — |
| T3/Lv10 | 精英 | 1163/4650 | 241/554 | 1.弹体×1<br>2.地面区×0.35 | 1:17.836；2:6.2426 | 1:280；2:98 | 1:771；2:270 | — |
| T4/Lv15 | 普通 | 1147/4588 | 237/545 | 1.弹体×1 | 1:17.55 | 1:296 | 1:818 | — |
| T4/Lv15 | 精英 | 1376/5505 | 265/610 | 1.弹体×1<br>2.地面区×0.35 | 1:19.656；2:6.8796 | 1:331；2:116 | 1:915；2:320 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.95`；`pierce=false`；`projectile_angles=[0.0]`；`radius=5.0`；`range=430.0`；`shape="line"`；`speed=330.0`；`spread_degrees=70.0`；`track=true` |
| T2-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.95`；`pierce=false`；`projectile_angles=[-6.0,6.0]`；`radius=5.0`；`range=430.0`；`shape="line"`；`speed=330.0`；`spread_degrees=12.0`；`track=true` |
| T3-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.95`；`pierce=false`；`projectile_angles=[-6.0,6.0]`；`radius=5.0`；`range=430.0`；`shape="line"`；`speed=330.0`；`spread_degrees=12.0`；`track=true` |
| T4-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=3`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`pierce=false`；`projectile_angles=[-12.0,0.0,12.0]`；`radius=5.0`；`range=430.0`；`shape="line"`；`speed=330.0`；`spread_degrees=24.0`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M04 晴辉构装蜂群微卫（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 378/1512 | 108/248 | 1.位移攻击×1 | 1:8 | 1:108 | 1:298 | — |
| T1/Lv1 | 精英 | 454/1814 | 121/278 | 1.位移攻击×1<br>2.地面区×0.35 | 1:8.96；2:3.136 | 1:121；2:42 | 1:334；2:117 | — |
| T2/Lv5 | 普通 | 461/1845 | 119/273 | 1.位移攻击×1<br>2.近战×1 | 1:8.8；2:8.8 | 1:129；2:129 | 1:354；2:354 | — |
| T2/Lv5 | 精英 | 553/2214 | 133/306 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:9.856；2:9.856；3:3.4496 | 1:144；2:144；3:50 | 1:397；2:397；3:139 | — |
| T3/Lv10 | 普通 | 565/2260 | 132/304 | 1.位移攻击×1<br>2.近战×1 | 1:9.8；2:9.8 | 1:153；2:153 | 1:423；2:423 | — |
| T3/Lv10 | 精英 | 678/2713 | 148/341 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:10.976；2:10.976；3:3.8416 | 1:172；2:172；3:60 | 1:475；2:475；3:166 | — |
| T4/Lv15 | 普通 | 669/2676 | 146/335 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1 | 1:10.8；2:10.8；3:10.8 | 1:183；2:183；3:183 | 1:503；2:503；3:503 | — |
| T4/Lv15 | 精英 | 803/3211 | 163/376 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:12.096；2:12.096；3:12.096；4:4.2336 | 1:204；2:204；3:204；4:71 | 1:564；2:564；3:564；4:197 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 仅完成落地命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=0.610865238198015`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=true`；`landing_shape="cone"`；`path_mode="leap"`；`radius=26.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=75.0` |
| T2-1 | 物理 | 仅完成落地命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=0.610865238198015`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=true`；`landing_shape="cone"`；`path_mode="leap"`；`radius=26.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=75.0` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.418879020478639`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.7`；`radius=12.0`；`range=80.0`；`shape="line"`；`track=true` |
| T3-1 | 物理 | 仅完成落地命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=0.610865238198015`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=true`；`landing_shape="cone"`；`path_mode="leap"`；`radius=26.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=75.0` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.418879020478639`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.7`；`radius=12.0`；`range=80.0`；`shape="line"`；`track=true` |
| T4-1 | 物理 | 仅完成落地命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=0.610865238198015`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.85`；`landing_only=true`；`landing_shape="cone"`；`path_mode="leap"`；`radius=26.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=75.0` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-22.0`；`angle=0.418879020478639`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.85`；`radius=12.0`；`range=80.0`；`shape="line"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=22.0`；`angle=0.418879020478639`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.85`；`radius=12.0`；`range=80.0`；`shape="line"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M05 晴辉构装滚轮猎犬（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1053/4212 | 216/497 | 1.位移攻击×1 | 1:16 | 1:216 | 1:596 | — |
| T1/Lv1 | 精英 | 1264/5054 | 242/556 | 1.位移攻击×1<br>2.地面区×0.35 | 1:17.92；2:6.272 | 1:242；2:85 | 1:667；2:234 | — |
| T2/Lv5 | 普通 | 1285/5139 | 238/546 | 1.位移攻击×1 | 1:17.6 | 1:257 | 1:708 | — |
| T2/Lv5 | 精英 | 1542/6166 | 266/612 | 1.位移攻击×1<br>2.地面区×0.35 | 1:19.712；2:6.8992 | 1:287；2:101 | 1:793；2:278 | — |
| T3/Lv10 | 普通 | 1574/6297 | 265/609 | 1.位移攻击×1<br>2.近战×1 | 1:19.6；2:19.6 | 1:307；2:307 | 1:848；2:848 | — |
| T3/Lv10 | 精英 | 1889/7556 | 296/682 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:21.952；2:21.952；3:7.6832 | 1:343；2:343；3:120 | 1:949；2:949；3:332 | — |
| T4/Lv15 | 普通 | 1864/7455 | 292/671 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1 | 1:21.6；2:21.6；3:21.6 | 1:365；2:365；3:365 | 1:1007；2:1007；3:1007 | — |
| T4/Lv15 | 精英 | 2237/8946 | 327/751 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:24.192；2:24.192；3:24.192；4:8.4672 | 1:409；2:409；3:409；4:143 | 1:1127；2:1127；3:1127；4:394 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=false`；`path_mode="arc"`；`radius=28.0`；`range=260.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=200.0` |
| T2-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=1.48352986419518`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=false`；`path_mode="arc"`；`radius=28.0`；`range=260.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=200.0` |
| T3-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=1.48352986419518`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=false`；`path_mode="arc"`；`radius=28.0`；`range=260.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=200.0` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=65.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=36.0`；`range=78.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=1.48352986419518`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.5`；`landing_only=false`；`path_mode="arc"`；`radius=28.0`；`range=260.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=200.0` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=65.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.5`；`fixed_cycle_direction=true`；`radius=36.0`；`range=78.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-65.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.5`；`fixed_cycle_direction=true`；`radius=36.0`；`range=78.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M06 晴辉构装护翼师（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1037/4147 | 122/279 | 1.防护×1<br>2.近战×1 | 1:0；2:9 | 1:0；2:122 | 1:0；2:335 | 1.D0 cover_hp=280（同一掩体输入别名，不叠加）；anchor_health=280<br>D4 cover_hp=336（同一掩体输入别名，不叠加）；anchor_health=336 |
| T1/Lv1 | 精英 | 1244/4977 | 136/313 | 1.防护×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:10.08；3:3.528 | 1:0；2:136；3:48 | 1:0；2:376；3:131 | 1.D0 cover_hp=280（同一掩体输入别名，不叠加）；anchor_health=280<br>D4 cover_hp=336（同一掩体输入别名，不叠加）；anchor_health=336 |
| T2/Lv5 | 普通 | 1265/5060 | 134/307 | 1.防护×1<br>2.近战×1<br>3.近战×1 | 1:0；2:9.9；3:9.9 | 1:0；2:145；3:145 | 1:0；2:398；3:398 | 1.D0 cover_hp=302（同一掩体输入别名，不叠加）；anchor_health=302<br>D4 cover_hp=363（同一掩体输入别名，不叠加）；anchor_health=363 |
| T2/Lv5 | 精英 | 1518/6072 | 150/344 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:11.088；3:11.088；4:3.8808 | 1:0；2:162；3:162；4:57 | 1:0；2:446；3:446；4:156 | 1.D0 cover_hp=302（同一掩体输入别名，不叠加）；anchor_health=302<br>D4 cover_hp=363（同一掩体输入别名，不叠加）；anchor_health=363 |
| T3/Lv10 | 普通 | 1550/6200 | 149/342 | 1.防护×1<br>2.近战×1<br>3.近战×1 | 1:0；2:11.025；3:11.025 | 1:0；2:173；3:173 | 1:0；2:476；3:476 | 1.D0 cover_hp=325（同一掩体输入别名，不叠加）；anchor_health=325<br>D4 cover_hp=390（同一掩体输入别名，不叠加）；anchor_health=390 |
| T3/Lv10 | 精英 | 1860/7440 | 167/383 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:12.348；3:12.348；4:4.3218 | 1:0；2:194；3:194；4:68 | 1:0；2:533；3:533；4:187 | 1.D0 cover_hp=325（同一掩体输入别名，不叠加）；anchor_health=325<br>D4 cover_hp=390（同一掩体输入别名，不叠加）；anchor_health=390 |
| T4/Lv15 | 普通 | 1835/7341 | 164/377 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:12.15；3:12.15；4:12.15 | 1:0；2:205；3:205；4:205 | 1:0；2:566；3:566；4:566 | 1.D0 cover_hp=350（同一掩体输入别名，不叠加）；anchor_health=350<br>D4 cover_hp=420（同一掩体输入别名，不叠加）；anchor_health=420 |
| T4/Lv15 | 精英 | 2202/8809 | 184/423 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:13.608；3:13.608；4:13.608；5:4.7628 | 1:0；2:230；3:230；4:230；5:81 | 1:0；2:635；3:635；4:635；5:222 | 1.D0 cover_hp=350（同一掩体输入别名，不叠加）；anchor_health=350<br>D4 cover_hp=420（同一掩体输入别名，不叠加）；anchor_health=420 |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `anchor_health=28.0`；`angle=1.74532925199433`；`charges=1`；`cover_hp=28.0`；`cover_rebuild_seconds=8.0`；`damage_kind="fire"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_seconds=1.0`；`max_targets=1`；`mode="cover"`；`radius=200.0`；`range=200.0`；`shape="circle"`；`support_charges=1`；`support_targets=1`；`track=true` |
| T1-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=122；每1s原伤害15<br>D4：burn 2s；系数0.8；power=335；每1s原伤害40 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |
| T2-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `anchor_health=28.0`；`angle=1.74532925199433`；`charges=1`；`cover_hp=28.0`；`cover_rebuild_seconds=8.0`；`damage_kind="fire"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_seconds=1.0`；`max_targets=1`；`mode="cover"`；`radius=200.0`；`range=200.0`；`shape="circle"`；`support_charges=1`；`support_targets=1`；`track=true` |
| T2-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=145；每1s原伤害17<br>D4：burn 2s；系数0.8；power=398；每1s原伤害48 | `aim_offset=-30.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |
| T2-3 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=145；每1s原伤害17<br>D4：burn 2s；系数0.8；power=398；每1s原伤害48 | `aim_offset=30.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |
| T3-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `anchor_health=28.0`；`angle=1.74532925199433`；`charges=1`；`cover_hp=28.0`；`cover_rebuild_seconds=8.0`；`damage_kind="fire"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_seconds=1.0`；`max_targets=2`；`mode="cover"`；`radius=180.0`；`range=180.0`；`shape="circle"`；`support_charges=1`；`support_targets=2`；`track=true` |
| T3-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=173；每1s原伤害21<br>D4：burn 2s；系数0.8；power=476；每1s原伤害57 | `aim_offset=-30.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |
| T3-3 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=173；每1s原伤害21<br>D4：burn 2s；系数0.8；power=476；每1s原伤害57 | `aim_offset=30.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |
| T4-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `anchor_health=28.0`；`angle=1.74532925199433`；`charges=1`；`cover_hp=28.0`；`cover_rebuild_seconds=10.0`；`damage_kind="fire"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_seconds=1.2`；`max_targets=2`；`mode="cover"`；`radius=180.0`；`range=180.0`；`shape="circle"`；`support_charges=1`；`support_targets=2`；`track=true` |
| T4-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=205；每1s原伤害25<br>D4：burn 2s；系数0.8；power=566；每1s原伤害68 | `aim_offset=-30.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.2`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |
| T4-3 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=205；每1s原伤害25<br>D4：burn 2s；系数0.8；power=566；每1s原伤害68 | `aim_offset=30.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.2`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |
| T4-4 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | burn 2s；系数0.8；power=205；每1s原伤害25<br>D4：burn 2s；系数0.8；power=566；每1s原伤害68 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=0.0`；`exposure_seconds=1.2`；`radius=36.0`；`range=150.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M07 晴辉构装磁叉牵引师（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 864/3456 | 149/342 | 1.牵引攻击×1 | 1:11 | 1:149 | 1:410 | — |
| T1/Lv1 | 精英 | 1037/4147 | 166/383 | 1.牵引攻击×1<br>2.地面区×0.35 | 1:12.32；2:4.312 | 1:166；2:58 | 1:460；2:161 | — |
| T2/Lv5 | 普通 | 1054/4216 | 163/376 | 1.牵引攻击×1<br>2.近战×1 | 1:12.1；2:12.1 | 1:176；2:176 | 1:487；2:487 | — |
| T2/Lv5 | 精英 | 1265/5060 | 183/421 | 1.牵引攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:13.552；2:13.552；3:4.7432 | 1:198；2:198；3:69 | 1:546；2:546；3:191 | — |
| T3/Lv10 | 普通 | 1292/5167 | 182/418 | 1.牵引攻击×1<br>2.近战×1 | 1:13.475；2:13.475 | 1:211；2:211 | 1:582；2:582 | — |
| T3/Lv10 | 精英 | 1550/6200 | 204/469 | 1.牵引攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:15.092；2:15.092；3:5.2822 | 1:237；2:237；3:83 | 1:653；2:653；3:228 | — |
| T4/Lv15 | 普通 | 1529/6117 | 200/461 | 1.牵引攻击×1<br>2.近战×1<br>3.近战×1 | 1:14.85；2:14.85；3:14.85 | 1:250；2:250；3:250 | 1:692；2:692；3:692 | — |
| T4/Lv15 | 精英 | 1835/7341 | 225/516 | 1.牵引攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:16.632；2:16.632；3:16.632；4:5.8212 | 1:281；2:281；3:281；4:98 | 1:774；2:774；3:774；4:271 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`pull_distance=70.0`；`radius=12.0`；`range=310.0`；`requires_hit=true`；`shape="line"`；`track=true` |
| T2-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`pull_distance=70.0`；`radius=12.0`；`range=310.0`；`requires_hit=true`；`shape="line"`；`track=true` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=1.30899693899575`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=75.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`pull_distance=70.0`；`radius=12.0`；`range=310.0`；`requires_hit=true`；`shape="line"`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=1.30899693899575`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=75.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.15`；`pull_distance=85.0`；`radius=12.0`；`range=310.0`；`requires_hit=true`；`shape="line"`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=1.30899693899575`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.15`；`fixed_cycle_direction=true`；`radius=36.0`；`range=75.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-35.0`；`angle=1.30899693899575`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.15`；`fixed_cycle_direction=true`；`radius=36.0`；`range=75.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M08 晴辉构装塔盾卫（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1184/4737 | 158/363 | 1.防护×1<br>2.近战×1 | 1:0；2:11.7 | 1:0；2:158 | 1:0；2:436 | 1.D0 shield_ratio=0.35；按本体生命样例414（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例1658（受益目标生命×原比例） |
| T1/Lv1 | 精英 | 1421/5684 | 177/407 | 1.防护×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:13.104；3:4.5864 | 1:0；2:177；3:62 | 1:0；2:488；3:171 | 1.D0 shield_ratio=0.35；按本体生命样例497（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例1989（受益目标生命×原比例） |
| T2/Lv5 | 普通 | 1445/5779 | 174/400 | 1.防护×1<br>2.近战×1<br>3.近战×1 | 1:0；2:12.87；3:12.87 | 1:0；2:188；3:188 | 1:0；2:518；3:518 | 1.D0 shield_ratio=0.35；按本体生命样例506（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例2023（受益目标生命×原比例） |
| T2/Lv5 | 精英 | 1734/6935 | 195/448 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:14.4144；3:14.4144；4:5.04504 | 1:0；2:211；3:211；4:74 | 1:0；2:581；3:581；4:203 | 1.D0 shield_ratio=0.35；按本体生命样例607（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例2427（受益目标生命×原比例） |
| T3/Lv10 | 普通 | 1770/7082 | 193/445 | 1.防护×1<br>2.近战×1<br>3.近战×1 | 1:0；2:14.3325；3:14.3325 | 1:0；2:224；3:224 | 1:0；2:619；3:619 | 1.D0 shield_ratio=0.35；按本体生命样例620（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例2479（受益目标生命×原比例） |
| T3/Lv10 | 精英 | 2124/8498 | 217/498 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:16.0524；3:16.0524；4:5.61834 | 1:0；2:252；3:252；4:88 | 1:0；2:693；3:693；4:243 | 1.D0 shield_ratio=0.35；按本体生命样例743（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例2974（受益目标生命×原比例） |
| T4/Lv15 | 普通 | 2096/8384 | 213/490 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:15.795；3:15.795；4:15.795 | 1:0；2:266；3:266；4:266 | 1:0；2:735；3:735；4:735 | 1.D0 shield_ratio=0.35；按本体生命样例734（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例2934（受益目标生命×原比例） |
| T4/Lv15 | 精英 | 2515/10061 | 239/549 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:17.6904；3:17.6904；4:17.6904；5:6.19164 | 1:0；2:299；3:299；4:299；5:105 | 1:0；2:824；3:824；4:824；5:288 | 1.D0 shield_ratio=0.35；按本体生命样例880（受益目标生命×原比例）<br>D4 shield_ratio=0.35；按本体生命样例3521（受益目标生命×原比例） |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.74532925199433`；`charges=3`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.1`；`mode="directional"`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.35`；`track=true` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.65s；系数0.82<br>D4：slow 0.65s；系数0.82 | `aim_offset=0.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.74532925199433`；`charges=3`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.1`；`mode="directional"`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.35`；`track=true` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.75s；系数0.8<br>D4：slow 0.75s；系数0.8 | `aim_offset=0.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.75s；系数0.8<br>D4：slow 0.75s；系数0.8 | `aim_offset=40.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=90.0`；`angle=1.74532925199433`；`charges=3`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=0.9`；`mode="directional"`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.35`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.85s；系数0.78<br>D4：slow 0.85s；系数0.78 | `aim_offset=0.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.85s；系数0.78<br>D4：slow 0.85s；系数0.78 | `aim_offset=40.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=90.0`；`angle=1.74532925199433`；`charges=3`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.25`；`mode="directional"`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.35`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.95s；系数0.76<br>D4：slow 0.95s；系数0.76 | `aim_offset=0.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.25`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.95s；系数0.76<br>D4：slow 0.95s；系数0.76 | `aim_offset=40.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.25`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | slow 0.95s；系数0.76<br>D4：slow 0.95s；系数0.76 | `aim_offset=-40.0`；`angle=1.65806278939461`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.25`；`fixed_cycle_direction=true`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M09 晴辉构装鸣炉支援者（B1，F_HP=1 / F_A=1）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 674/2696 | 85/196 | 1.加速×1 | 1:0 | 1:0 | 1:0 | — |
| T1/Lv1 | 精英 | 809/3235 | 95/219 | 1.加速×1<br>2.地面区×0.35 | 1:0；2:2.4696 | 1:0；2:33 | 1:0；2:92 | — |
| T2/Lv5 | 普通 | 822/3289 | 94/215 | 1.加速×1 | 1:0 | 1:0 | 1:0 | — |
| T2/Lv5 | 精英 | 987/3946 | 105/241 | 1.加速×1<br>2.地面区×0.35 | 1:0；2:2.71656 | 1:0；2:40 | 1:0；2:109 | — |
| T3/Lv10 | 普通 | 1008/4030 | 104/240 | 1.加速×1<br>2.近战×1<br>3.近战×1 | 1:0；2:7.7175；3:7.7175 | 1:0；2:121；3:121 | 1:0；2:334；3:334 | — |
| T3/Lv10 | 精英 | 1209/4836 | 117/268 | 1.加速×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:8.6436；3:8.6436；4:3.02526 | 1:0；2:136；3:136；4:48 | 1:0；2:373；3:373；4:131 | — |
| T4/Lv15 | 普通 | 1193/4771 | 115/264 | 1.加速×1<br>2.近战×1<br>3.近战×1 | 1:0；2:8.505；3:8.505 | 1:0；2:144；3:144 | 1:0；2:396；3:396 | — |
| T4/Lv15 | 精英 | 1431/5726 | 129/296 | 1.加速×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:9.5256；3:9.5256；4:3.33396 | 1:0；2:161；3:161；4:56 | 1:0；2:444；3:444；4:155 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=1`；`consume_corpse=true`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exposure_seconds=1.0`；`max_targets=1`；`multiplier=1.15`；`radius=220.0`；`range=220.0`；`require_corpse=true`；`shape="circle"`；`support_charges=1`；`support_targets=1`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=1`；`consume_corpse=true`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exposure_seconds=1.0`；`max_targets=2`；`multiplier=1.15`；`radius=245.0`；`range=245.0`；`require_corpse=true`；`shape="circle"`；`support_charges=1`；`support_targets=2`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=1`；`consume_corpse=true`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exposure_seconds=1.0`；`max_targets=2`；`multiplier=1.15`；`radius=245.0`；`range=245.0`；`require_corpse=true`；`shape="circle"`；`support_charges=1`；`support_targets=2`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-30.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=62.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=30.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=62.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=1`；`consume_corpse=true`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exposure_seconds=1.3`；`max_targets=3`；`multiplier=1.15`；`radius=245.0`；`range=245.0`；`require_corpse=true`；`shape="circle"`；`support_charges=1`；`support_targets=3`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-30.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.3`；`radius=36.0`；`range=62.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=30.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.3`；`radius=36.0`；`range=62.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M10 琥珀虫族镰足刺虫（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 653/2613 | 245/563 | 1.近战×1 | 1:16.8 | 1:245 | 1:676 | — |
| T1/Lv1 | 精英 | 784/3135 | 274/631 | 1.近战×1<br>2.地面区×0.35 | 1:18.816；2:6.5856 | 1:274；2:96 | 1:757；2:265 | — |
| T2/Lv5 | 普通 | 797/3188 | 269/620 | 1.近战×1<br>2.近战×1 | 1:18.48；2:18.48 | 1:291；2:291 | 1:804；2:804 | — |
| T2/Lv5 | 精英 | 956/3825 | 302/694 | 1.近战×1<br>2.近战×1<br>3.地面区×0.35 | 1:20.6976；2:20.6976；3:7.24416 | 1:326；2:326；3:114 | 1:899；2:899；3:315 | — |
| T3/Lv10 | 普通 | 977/3906 | 300/690 | 1.近战×1<br>2.近战×1 | 1:20.58；2:20.58 | 1:348；2:348 | 1:960；2:960 | — |
| T3/Lv10 | 精英 | 1172/4687 | 336/773 | 1.近战×1<br>2.近战×1<br>3.地面区×0.35 | 1:23.0496；2:23.0496；3:8.06736 | 1:390；2:390；3:136 | 1:1076；2:1076；3:377 | — |
| T4/Lv15 | 普通 | 1156/4625 | 331/761 | 1.近战×1<br>2.近战×1<br>3.近战×1 | 1:22.68；2:22.68；3:22.68 | 1:414；2:414；3:414 | 1:1142；2:1142；3:1142 | — |
| T4/Lv15 | 精英 | 1387/5549 | 370/852 | 1.近战×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:25.4016；2:25.4016；3:25.4016；4:8.89056 | 1:463；2:463；3:463；4:162 | 1:1278；2:1278；3:1278；4:447 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |
| T2-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=18.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |
| T3-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-18.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=18.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |
| T4-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-18.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=18.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.383972435438752`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=12.0`；`range=68.0`；`shape="line"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M11 琥珀虫族针吻酸炮（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 780/3121 | 203/467 | 1.地面区×1 | 1:13.92 | 1:203 | 1:560 | — |
| T1/Lv1 | 精英 | 936/3745 | 227/523 | 1.地面区×1<br>2.地面区×0.35 | 1:15.5904；2:5.45664 | 1:227；2:79 | 1:628；2:220 | — |
| T2/Lv5 | 普通 | 952/3807 | 223/513 | 1.地面区×1<br>2.地面区×1 | 1:15.312；2:15.312 | 1:241；2:241 | 1:665；2:665 | — |
| T2/Lv5 | 精英 | 1142/4569 | 250/575 | 1.地面区×1<br>2.地面区×1<br>3.地面区×0.35 | 1:17.14944；2:17.14944；3:6.002304 | 1:270；2:270；3:95 | 1:745；2:745；3:261 | — |
| T3/Lv10 | 普通 | 1166/4666 | 249/572 | 1.地面区×1<br>2.地面区×1<br>3.地面区×1 | 1:17.052；2:17.052；3:17.052 | 1:289；2:289；3:289 | 1:796；2:796；3:796 | — |
| T3/Lv10 | 精英 | 1400/5599 | 278/640 | 1.地面区×1<br>2.地面区×1<br>3.地面区×1<br>4.地面区×0.35 | 1:19.09824；2:19.09824；3:19.09824；4:6.684384 | 1:322；2:322；3:322；4:113 | 1:891；2:891；3:891；4:312 | — |
| T4/Lv15 | 普通 | 1381/5524 | 274/630 | 1.地面区×1<br>2.地面区×1<br>3.地面区×1 | 1:18.792；2:18.792；3:18.792 | 1:343；2:343；3:343 | 1:945；2:945；3:945 | — |
| T4/Lv15 | 精英 | 1657/6629 | 307/706 | 1.地面区×1<br>2.地面区×1<br>3.地面区×1<br>4.地面区×0.35 | 1:21.04704；2:21.04704；3:21.04704；4:7.366464 | 1:384；2:384；3:384；4:134 | 1:1059；2:1059；3:1059；4:371 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=203；每1s原伤害16<br>D4：corrosion 2s；系数0.8；power=560；每1s原伤害45 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.2`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[0.0,-46.0]]`；`tick_interval=0.65`；`track=true` |
| T2-1 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=241；每1s原伤害19<br>D4：corrosion 2s；系数0.8；power=665；每1s原伤害53 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.2`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[-65.0,0.0]]`；`tick_interval=0.65`；`track=true` |
| T2-2 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=241；每1s原伤害19<br>D4：corrosion 2s；系数0.8；power=665；每1s原伤害53 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.2`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[35.0,-65.0]]`；`tick_interval=0.65`；`track=true` |
| T3-1 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=289；每1s原伤害23<br>D4：corrosion 2s；系数0.8；power=796；每1s原伤害64 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.2`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[-80.0,-35.0]]`；`tick_interval=0.65`；`track=true` |
| T3-2 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=289；每1s原伤害23<br>D4：corrosion 2s；系数0.8；power=796；每1s原伤害64 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.2`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[0.0,35.0]]`；`tick_interval=0.65`；`track=true` |
| T3-3 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=289；每1s原伤害23<br>D4：corrosion 2s；系数0.8；power=796；每1s原伤害64 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.2`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[80.0,-35.0]]`；`tick_interval=0.65`；`track=true` |
| T4-1 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=343；每1s原伤害27<br>D4：corrosion 2s；系数0.8；power=945；每1s原伤害76 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.3`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[-80.0,45.0]]`；`tick_interval=0.65`；`track=true` |
| T4-2 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=343；每1s原伤害27<br>D4：corrosion 2s；系数0.8；power=945；每1s原伤害76 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.3`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[0.0,-45.0]]`；`tick_interval=0.65`；`track=true` |
| T4-3 | 魔法 | 落点一次+每0.65s/跳；持续2.4s（最多4次/区） | 预警0.85s；锁定0.4s | corrosion 2s；系数0.8；power=343；每1s原伤害27<br>D4：corrosion 2s；系数0.8；power=945；每1s原伤害76 | `angle=1.5707963267949`；`damage_kind="corrosion"`；`duration=2.4`；`exposure_seconds=1.3`；`lob=true`；`max_active_hazards=2`；`max_count=2`；`radius=42.0`；`range=360.0`；`shape="circle"`；`target_offsets=[[80.0,45.0]]`；`tick_interval=0.65`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M12 琥珀虫族育卵萤母（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 943/3774 | 105/241 | 1.召唤×1 | 1:0 | 1:0 | 1:0 | 1.D0 pod_health=180；pod_break_armor_loss=0<br>D4 pod_health=216；pod_break_armor_loss=0 |
| T1/Lv1 | 精英 | 1132/4529 | 118/270 | 1.召唤×1<br>2.地面区×0.35 | 1:0；2:2.8224 | 1:0；2:41 | 1:0；2:113 | 1.D0 pod_health=180；pod_break_armor_loss=0<br>D4 pod_health=216；pod_break_armor_loss=0 |
| T2/Lv5 | 普通 | 1151/4604 | 115/266 | 1.召唤×1 | 1:0 | 1:0 | 1:0 | 1.D0 pod_health=194；pod_break_armor_loss=0<br>D4 pod_health=233；pod_break_armor_loss=0 |
| T2/Lv5 | 精英 | 1381/5525 | 129/297 | 1.召唤×1<br>2.地面区×0.35 | 1:0；2:3.10464 | 1:0；2:49 | 1:0；2:135 | 1.D0 pod_health=194；pod_break_armor_loss=0<br>D4 pod_health=233；pod_break_armor_loss=0 |
| T3/Lv10 | 普通 | 1411/5642 | 129/296 | 1.召唤×1 | 1:0 | 1:0 | 1:0 | 1.D0 pod_health=209；pod_break_armor_loss=0<br>D4 pod_health=251；pod_break_armor_loss=0 |
| T3/Lv10 | 精英 | 1693/6770 | 144/331 | 1.召唤×1<br>2.地面区×0.35 | 1:0；2:3.45744 | 1:0；2:58 | 1:0；2:161 | 1.D0 pod_health=209；pod_break_armor_loss=0<br>D4 pod_health=251；pod_break_armor_loss=0 |
| T4/Lv15 | 普通 | 1670/6680 | 142/326 | 1.召唤×1 | 1:0 | 1:0 | 1:0 | 1.D0 pod_health=225；pod_break_armor_loss=100<br>D4 pod_health=270；pod_break_armor_loss=100 |
| T4/Lv15 | 精英 | 2004/8016 | 159/365 | 1.召唤×1<br>2.地面区×0.35 | 1:0；2:3.81024 | 1:0；2:70 | 1:0；2:192 | 1.D0 pod_health=225；pod_break_armor_loss=100<br>D4 pod_health=270；pod_break_armor_loss=100 |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable=true`；`charges=2`；`count=1`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_after_hatch=0.0`；`exposure_seconds=1.2`；`hatch_delay=1.4`；`max_alive=2`；`max_targets=1`；`pod_break_armor_loss=0.0`；`pod_health=18.0`；`radius=200.0`；`range=200.0`；`reserve_budget=true`；`shape="circle"`；`summon_cap=2`；`support_charges=2`；`support_targets=1`；`target_offsets=[]`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable=true`；`charges=2`；`count=2`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_after_hatch=0.0`；`exposure_seconds=1.2`；`hatch_delay=1.6`；`max_alive=2`；`max_targets=1`；`pod_break_armor_loss=0.0`；`pod_health=18.0`；`radius=200.0`；`range=200.0`；`reserve_budget=true`；`shape="circle"`；`summon_cap=2`；`support_charges=2`；`support_targets=1`；`target_offsets=[[-45.0,0.0],[45.0,0.0]]`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable=true`；`charges=2`；`count=2`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_after_hatch=0.0`；`exposure_seconds=1.2`；`hatch_delay=1.6`；`max_alive=2`；`max_targets=1`；`pod_break_armor_loss=0.0`；`pod_health=18.0`；`radius=200.0`；`range=200.0`；`reserve_budget=true`；`shape="circle"`；`summon_cap=2`；`support_charges=2`；`support_targets=1`；`target_offsets=[[-80.0,-25.0],[80.0,-25.0]]`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable=true`；`charges=2`；`count=2`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=false`；`exposure_after_hatch=1.6`；`exposure_seconds=1.6`；`hatch_delay=1.6`；`max_alive=2`；`max_targets=1`；`pod_break_armor_loss=10.0`；`pod_health=18.0`；`radius=200.0`；`range=200.0`；`reserve_budget=true`；`shape="circle"`；`summon_cap=2`；`support_charges=2`；`support_targets=1`；`target_offsets=[[-80.0,-25.0],[80.0,-25.0]]`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M13 琥珀虫族剪钳幼蜓（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 588/2351 | 219/503 | 1.近战×1<br>2.近战×1 | 1:15；2:15 | 1:219；2:219 | 1:604；2:604 | — |
| T1/Lv1 | 精英 | 705/2822 | 245/563 | 1.近战×1<br>2.近战×1<br>3.地面区×0.35 | 1:16.8；2:16.8；3:5.88 | 1:245；2:245；3:86 | 1:676；2:676；3:236 | — |
| T2/Lv5 | 普通 | 717/2869 | 241/553 | 1.近战×1<br>2.近战×1<br>3.近战×1 | 1:16.5；2:16.5；3:16.5 | 1:260；2:260；3:260 | 1:717；2:717；3:717 | — |
| T2/Lv5 | 精英 | 861/3443 | 269/620 | 1.近战×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:18.48；2:18.48；3:18.48；4:6.468 | 1:291；2:291；3:291；4:102 | 1:804；2:804；3:804；4:281 | — |
| T3/Lv10 | 普通 | 879/3515 | 268/616 | 1.近战×1<br>2.近战×1<br>3.近战×1 | 1:18.375；2:18.375；3:18.375 | 1:311；2:311；3:311 | 1:857；2:857；3:857 | — |
| T3/Lv10 | 精英 | 1055/4219 | 300/690 | 1.近战×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:20.58；2:20.58；3:20.58；4:7.203 | 1:348；2:348；3:348；4:122 | 1:960；2:960；3:960；4:336 | — |
| T4/Lv15 | 普通 | 1041/4162 | 295/679 | 1.近战×1<br>2.近战×1<br>3.近战×1 | 1:20.25；2:20.25；3:20.25 | 1:369；2:369；3:369 | 1:1019；2:1019；3:1019 | — |
| T4/Lv15 | 精英 | 1249/4995 | 331/761 | 1.近战×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:22.68；2:22.68；3:22.68；4:7.938 | 1:414；2:414；3:414；4:145 | 1:1142；2:1142；3:1142；4:400 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-35.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T2-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-35.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T3-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-50.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=50.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T4-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-55.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=55.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=0.610865238198015`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`fixed_cycle_direction=true`；`radius=17.0`；`range=80.0`；`shape="line"`；`track=false` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M14 琥珀虫族黏足幼虫（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 423/1693 | 117/268 | 1.位移攻击×1<br>2.地面区×0 | 1:8；2:0 | 1:117；2:0 | 1:322；2:0 | — |
| T1/Lv1 | 精英 | 508/2032 | 131/300 | 1.位移攻击×1<br>2.地面区×0<br>3.地面区×0.35 | 1:8.96；2:0；3:3.136 | 1:131；2:0；3:46 | 1:360；2:0；3:126 | — |
| T2/Lv5 | 普通 | 516/2066 | 128/295 | 1.位移攻击×1<br>2.地面区×0<br>3.近战×1 | 1:8.8；2:0；3:8.8 | 1:138；2:0；3:138 | 1:382；2:0；3:382 | — |
| T2/Lv5 | 精英 | 620/2479 | 144/331 | 1.位移攻击×1<br>2.地面区×0<br>3.近战×1<br>4.地面区×0.35 | 1:9.856；2:0；3:9.856；4:3.4496 | 1:156；2:0；3:156；4:54 | 1:429；2:0；3:429；4:150 | — |
| T3/Lv10 | 普通 | 633/2532 | 143/329 | 1.位移攻击×1<br>2.地面区×0<br>3.近战×1 | 1:9.8；2:0；3:9.8 | 1:166；2:0；3:166 | 1:458；2:0；3:458 | — |
| T3/Lv10 | 精英 | 760/3038 | 160/368 | 1.位移攻击×1<br>2.地面区×0<br>3.近战×1<br>4.地面区×0.35 | 1:10.976；2:0；3:10.976；4:3.8416 | 1:186；2:0；3:186；4:65 | 1:512；2:0；3:512；4:179 | — |
| T4/Lv15 | 普通 | 749/2997 | 157/362 | 1.位移攻击×1<br>2.地面区×0<br>3.近战×1 | 1:10.8；2:0；3:10.8 | 1:196；2:0；3:196 | 1:543；2:0；3:543 | — |
| T4/Lv15 | 精英 | 899/3597 | 176/406 | 1.位移攻击×1<br>2.地面区×0<br>3.近战×1<br>4.地面区×0.35 | 1:12.096；2:0；3:12.096；4:4.2336 | 1:220；2:0；3:220；4:77 | 1:609；2:0；3:609；4:213 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=27.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=65.0` |
| T1-2 | 物理 | 每0.65s/跳；持续1.8s（最多2跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `angle=1.5707963267949`；`center="self"`；`damage_kind="kinetic"`；`duration=1.8`；`exposure_seconds=0.7`；`max_active_hazards=1`；`max_count=2`；`radius=27.0`；`range=54.0`；`shape="circle"`；`target_offsets=[]`；`tick_interval=0.65`；`track=true` |
| T2-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=27.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=65.0` |
| T2-2 | 物理 | 每0.65s/跳；持续1.8s（最多2跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `angle=1.5707963267949`；`center="self"`；`damage_kind="kinetic"`；`duration=1.8`；`exposure_seconds=0.7`；`max_active_hazards=1`；`max_count=2`；`radius=27.0`；`range=54.0`；`shape="circle"`；`target_offsets=[]`；`tick_interval=0.65`；`track=true` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=0.523598775598299`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.7`；`radius=10.0`；`range=58.0`；`shape="line"`；`track=true` |
| T3-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=27.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=65.0` |
| T3-2 | 物理 | 每0.65s/跳；持续1.8s（最多2跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `angle=1.5707963267949`；`center="self"`；`damage_kind="kinetic"`；`duration=1.8`；`exposure_seconds=0.7`；`max_active_hazards=1`；`max_count=2`；`radius=27.0`；`range=54.0`；`shape="circle"`；`target_offsets=[]`；`tick_interval=0.65`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=0.523598775598299`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.7`；`radius=10.0`；`range=58.0`；`shape="line"`；`track=true` |
| T4-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.85`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=27.0`；`range=54.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=65.0` |
| T4-2 | 物理 | 每0.65s/跳；持续1.8s（最多2跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `angle=1.5707963267949`；`center="self"`；`damage_kind="kinetic"`；`duration=1.8`；`exposure_seconds=0.85`；`max_active_hazards=2`；`max_count=2`；`radius=27.0`；`range=54.0`；`shape="circle"`；`target_offsets=[[-28.0,0.0],[28.0,0.0]]`；`tick_interval=0.65`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=0.523598775598299`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.85`；`radius=10.0`；`range=58.0`；`shape="line"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M15 琥珀虫族掘地锹甲（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 653/2613 | 245/563 | 1.位移攻击×1 | 1:16.8 | 1:245 | 1:676 | — |
| T1/Lv1 | 精英 | 784/3135 | 274/631 | 1.位移攻击×1<br>2.地面区×0.35 | 1:18.816；2:6.5856 | 1:274；2:96 | 1:757；2:265 | — |
| T2/Lv5 | 普通 | 797/3188 | 269/620 | 1.位移攻击×1<br>2.近战×1 | 1:18.48；2:18.48 | 1:291；2:291 | 1:804；2:804 | — |
| T2/Lv5 | 精英 | 956/3825 | 302/694 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:20.6976；2:20.6976；3:7.24416 | 1:326；2:326；3:114 | 1:899；2:899；3:315 | — |
| T3/Lv10 | 普通 | 977/3906 | 300/690 | 1.位移攻击×1<br>2.近战×1 | 1:20.58；2:20.58 | 1:348；2:348 | 1:960；2:960 | — |
| T3/Lv10 | 精英 | 1172/4687 | 336/773 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:23.0496；2:23.0496；3:8.06736 | 1:390；2:390；3:136 | 1:1076；2:1076；3:377 | — |
| T4/Lv15 | 普通 | 1156/4625 | 331/761 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1 | 1:22.68；2:22.68；3:22.68 | 1:414；2:414；3:414 | 1:1142；2:1142；3:1142 | — |
| T4/Lv15 | 精英 | 1387/5549 | 370/852 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:25.4016；2:25.4016；3:25.4016；4:8.89056 | 1:463；2:463；3:463；4:162 | 1:1278；2:1278；3:1278；4:447 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=0.0`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=true`；`landing_shape="circle"`；`path_mode="burrow"`；`radius=46.0`；`range=240.0`；`shape="line"`；`speed=180.0`；`track=false`；`travel_distance=170.0`；`visible_path=true` |
| T2-1 | 物理 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=0.0`；`arc_height=0.0`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=true`；`landing_shape="circle"`；`path_mode="burrow"`；`radius=46.0`；`range=240.0`；`shape="line"`；`speed=180.0`；`track=false`；`travel_distance=170.0`；`visible_path=true` |
| T2-2 | 物理 | 每次命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `aim_offset=70.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=46.0`；`range=82.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=0.785398163397448`；`arc_height=42.0728534805996`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=true`；`landing_shape="circle"`；`path_mode="burrow"`；`radius=46.0`；`range=240.0`；`shape="line"`；`speed=180.0`；`track=false`；`travel_distance=170.0`；`visible_path=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `aim_offset=70.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=46.0`；`range=82.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=0.785398163397448`；`arc_height=42.0728534805996`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.5`；`landing_only=true`；`landing_shape="circle"`；`path_mode="burrow"`；`radius=46.0`；`range=240.0`；`shape="line"`；`speed=180.0`；`track=false`；`travel_distance=170.0`；`visible_path=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `aim_offset=70.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.5`；`fixed_cycle_direction=true`；`radius=46.0`；`range=82.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.85s；锁定0.4s | 无<br>D4：无 | `aim_offset=-70.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.5`；`fixed_cycle_direction=true`；`radius=46.0`；`range=82.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M16 琥珀虫族搬运丸甲（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 842/3368 | 131/302 | 1.机关交互×1<br>2.近战×1 | 1:0；2:9 | 1:0；2:131 | 1:0；2:362 | — |
| T1/Lv1 | 精英 | 1010/4041 | 147/338 | 1.机关交互×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:10.08；3:3.528 | 1:0；2:147；3:51 | 1:0；2:406；3:142 | — |
| T2/Lv5 | 普通 | 1027/4108 | 144/332 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:9.9；3:9.9 | 1:0；2:156；3:156 | 1:0；2:430；3:430 | — |
| T2/Lv5 | 精英 | 1233/4930 | 162/372 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:11.088；3:11.088；4:3.8808 | 1:0；2:175；3:175；4:61 | 1:0；2:482；3:482；4:169 | — |
| T3/Lv10 | 普通 | 1259/5034 | 161/370 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:11.025；3:11.025 | 1:0；2:187；3:187 | 1:0；2:515；3:515 | — |
| T3/Lv10 | 精英 | 1510/6041 | 180/414 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:12.348；3:12.348；4:4.3218 | 1:0；2:209；3:209；4:73 | 1:0；2:576；3:576；4:202 | — |
| T4/Lv15 | 普通 | 1490/5961 | 177/407 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:12.15；3:12.15；4:12.15 | 1:0；2:221；3:221；4:221 | 1:0；2:611；3:611；4:611 | — |
| T4/Lv15 | 精英 | 1788/7153 | 198/456 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:13.608；3:13.608；4:13.608；5:4.7628 | 1:0；2:248；3:248；4:248；5:87 | 1:0；2:684；3:684；4:684；5:239 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_quest_object"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=150.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_quest_object"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=150.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_quest_object"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`radius=36.0`；`range=150.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_quest_object"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`radius=36.0`；`range=150.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=90.0`；`angle=0.959931088596881`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`fixed_cycle_direction=true`；`radius=36.0`；`range=60.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M17 琥珀虫族回春萤卫（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 842/3368 | 79/181 | 1.治疗×1 | 1:0 | 1:0 | 1:0 | 1.D0 heal_ratio=0.08；按本体生命样例67（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例269（受益目标生命×原比例） |
| T1/Lv1 | 精英 | 1010/4041 | 88/203 | 1.治疗×1<br>2.地面区×0.35 | 1:0；2:2.1168 | 1:0；2:31 | 1:0；2:85 | 1.D0 heal_ratio=0.08；按本体生命样例81（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例323（受益目标生命×原比例） |
| T2/Lv5 | 普通 | 1027/4108 | 87/199 | 1.治疗×1 | 1:0 | 1:0 | 1:0 | 1.D0 heal_ratio=0.08；按本体生命样例82（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例329（受益目标生命×原比例） |
| T2/Lv5 | 精英 | 1233/4930 | 97/223 | 1.治疗×1<br>2.地面区×0.35 | 1:0；2:2.32848 | 1:0；2:37 | 1:0；2:101 | 1.D0 heal_ratio=0.08；按本体生命样例99（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例394（受益目标生命×原比例） |
| T3/Lv10 | 普通 | 1259/5034 | 96/222 | 1.治疗×1<br>2.近战×1<br>3.近战×1 | 1:0；2:6.615；3:6.615 | 1:0；2:111；3:111 | 1:0；2:309；3:309 | 1.D0 heal_ratio=0.08；按本体生命样例101（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例403（受益目标生命×原比例） |
| T3/Lv10 | 精英 | 1510/6041 | 108/248 | 1.治疗×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:7.4088；3:7.4088；4:2.59308 | 1:0；2:125；3:125；4:44 | 1:0；2:345；3:345；4:121 | 1.D0 heal_ratio=0.08；按本体生命样例121（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例483（受益目标生命×原比例） |
| T4/Lv15 | 普通 | 1490/5961 | 106/244 | 1.治疗×1<br>2.近战×1<br>3.近战×1 | 1:0；2:7.29；3:7.29 | 1:0；2:133；3:133 | 1:0；2:366；3:366 | 1.D0 heal_ratio=0.08；按本体生命样例119（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例477（受益目标生命×原比例） |
| T4/Lv15 | 精英 | 1788/7153 | 119/274 | 1.治疗×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:8.1648；3:8.1648；4:2.85768 | 1:0；2:149；3:149；4:52 | 1:0；2:411；3:411；4:144 | 1.D0 heal_ratio=0.08；按本体生命样例143（受益目标生命×原比例）<br>D4 heal_ratio=0.08；按本体生命样例572（受益目标生命×原比例） |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=2`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.2`；`heal_ratio=0.08`；`max_receives=2`；`max_targets=1`；`radius=240.0`；`range=240.0`；`shape="circle"`；`support_charges=2`；`support_targets=1`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=2`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.2`；`heal_ratio=0.08`；`max_receives=2`；`max_targets=2`；`radius=240.0`；`range=240.0`；`shape="circle"`；`support_charges=2`；`support_targets=2`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=2`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.2`；`heal_ratio=0.08`；`max_receives=2`；`max_targets=2`；`radius=240.0`；`range=240.0`；`shape="circle"`；`support_charges=2`；`support_targets=2`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-45.0`；`angle=1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.2`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=45.0`；`angle=1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.2`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`charges=2`；`damage_kind="kinetic"`；`duration=3.0`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.6`；`heal_ratio=0.08`；`max_receives=2`；`max_targets=3`；`radius=275.0`；`range=275.0`；`shape="circle"`；`support_charges=2`；`support_targets=3`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-45.0`；`angle=1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=45.0`；`angle=1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`radius=36.0`；`range=68.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

治疗已实际释放次数达到min(2,support_charges)后，序列第1项改为近战×0.6（角160°、距离58，无附加状态）；其后原近战与精英余震保持。下列来自带哈希的 [Brain条件分支](../../scripts/combat/enemy_brain.gd)，不冒充Godot初始状态导出的治疗命令。

| 阶/参考级 | 身份 | 耗尽后第1项D0 Q | 耗尽后第1项D4 Q |
| --- | --- | --- | --- |
| T1/Lv1 | normal | 47 | 130 |
| T1/Lv1 | elite | 53 | 146 |
| T2/Lv5 | normal | 56 | 155 |
| T2/Lv5 | elite | 63 | 173 |
| T3/Lv10 | normal | 67 | 185 |
| T3/Lv10 | elite | 75 | 207 |
| T4/Lv15 | normal | 80 | 220 |
| T4/Lv15 | elite | 89 | 247 |


### M18 琥珀虫族破墙犀甲（B2，F_HP=1.12 / F_A=1.08）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1203/4812 | 184/423 | 1.机关交互×1<br>2.近战×1 | 1:0；2:12.6 | 1:0；2:184 | 1:0；2:508 | — |
| T1/Lv1 | 精英 | 1444/5774 | 206/473 | 1.机关交互×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:14.112；3:4.9392 | 1:0；2:206；3:72 | 1:0；2:568；3:199 | — |
| T2/Lv5 | 普通 | 1468/5870 | 202/465 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:13.86；3:13.86 | 1:0；2:218；3:218 | 1:0；2:603；3:603 | — |
| T2/Lv5 | 精英 | 1761/7044 | 226/521 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:15.5232；3:15.5232；4:5.43312 | 1:0；2:244；3:244；4:85 | 1:0；2:675；3:675；4:236 | — |
| T3/Lv10 | 普通 | 1798/7194 | 225/518 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:15.435；3:15.435 | 1:0；2:261；3:261 | 1:0；2:721；3:721 | — |
| T3/Lv10 | 精英 | 2158/8632 | 252/580 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:17.2872；3:17.2872；4:6.05052 | 1:0；2:292；3:292；4:102 | 1:0；2:807；3:807；4:283 | — |
| T4/Lv15 | 普通 | 2129/8517 | 248/570 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:17.01；3:17.01；4:17.01 | 1:0；2:310；3:310；4:310 | 1:0；2:855；3:855；4:855 | — |
| T4/Lv15 | 精英 | 2555/10220 | 278/639 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:19.0512；3:19.0512；4:19.0512；5:6.66792 | 1:0；2:348；3:348；4:348；5:122 | 1:0；2:959；3:959；4:959；5:335 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="bite_breakable_wall"`；`angle=1.5707963267949`；`breakable_wall_cap=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=95.0`；`shape="circle"`；`track=false` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="bite_breakable_wall"`；`angle=1.5707963267949`；`breakable_wall_cap=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=95.0`；`shape="circle"`；`track=false` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="bite_breakable_wall"`；`angle=1.5707963267949`；`breakable_wall_cap=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=95.0`；`shape="circle"`；`track=false` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="bite_breakable_wall"`；`angle=1.5707963267949`；`breakable_wall_cap=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.65`；`radius=36.0`；`range=95.0`；`shape="circle"`；`track=false` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.65`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.65`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-25.0`；`angle=2.18166156499291`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.65`；`fixed_cycle_direction=true`；`radius=36.0`；`range=95.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M19 南瓜僵尸提灯哨兵（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 836/3343 | 99/227 | 1.机关交互×1 | 1:0 | 1:0 | 1:0 | — |
| T1/Lv1 | 精英 | 1003/4011 | 110/254 | 1.机关交互×1<br>2.地面区×0.35 | 1:0；2:2.4696 | 1:0；2:39 | 1:0；2:107 | — |
| T2/Lv5 | 普通 | 1020/4078 | 109/250 | 1.机关交互×1<br>2.机关交互×1 | 1:0；2:0 | 1:0；2:0 | 1:0；2:0 | — |
| T2/Lv5 | 精英 | 1223/4894 | 122/280 | 1.机关交互×1<br>2.机关交互×1<br>3.地面区×0.35 | 1:0；2:0；3:2.71656 | 1:0；2:0；3:46 | 1:0；2:0；3:127 | — |
| T3/Lv10 | 普通 | 1249/4997 | 121/278 | 1.机关交互×1<br>2.机关交互×1 | 1:0；2:0 | 1:0；2:0 | 1:0；2:0 | — |
| T3/Lv10 | 精英 | 1499/5997 | 135/311 | 1.机关交互×1<br>2.机关交互×1<br>3.地面区×0.35 | 1:0；2:0；3:3.02526 | 1:0；2:0；3:55 | 1:0；2:0；3:152 | — |
| T4/Lv15 | 普通 | 1479/5916 | 133/306 | 1.机关交互×1<br>2.机关交互×1<br>3.机关交互×1 | 1:0；2:0；3:0 | 1:0；2:0；3:0 | 1:0；2:0；3:0 | — |
| T4/Lv15 | 精英 | 1775/7100 | 149/343 | 1.机关交互×1<br>2.机关交互×1<br>3.机关交互×1<br>4.地面区×0.35 | 1:0；2:0；3:0；4:3.33396 | 1:0；2:0；3:0；4:65 | 1:0；2:0；3:0；4:180 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=0.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.0`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=-30.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.0`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |
| T2-2 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=30.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.0`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=-30.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.0`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |
| T3-2 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=30.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.0`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=-55.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.1`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |
| T4-2 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=0.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.1`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |
| T4-3 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="scan_mark"`；`aim_offset=55.0`；`angle=0.872664625997165`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.1`；`lock_multiplier=0.85`；`minimum_lock_seconds=0.4`；`radius=36.0`；`range=280.0`；`shape="cone"`；`support_targets=1`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M20 南瓜僵尸远程弩手（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 804/3214 | 204/468 | 1.弹体×1 | 1:13 | 1:204 | 1:562 | — |
| T1/Lv1 | 精英 | 964/3857 | 228/524 | 1.弹体×1<br>2.地面区×0.35 | 1:14.56；2:5.096 | 1:228；2:80 | 1:629；2:220 | — |
| T2/Lv5 | 普通 | 980/3921 | 224/515 | 1.弹体×1 | 1:14.3 | 1:242 | 1:667 | — |
| T2/Lv5 | 精英 | 1176/4705 | 251/577 | 1.弹体×1<br>2.地面区×0.35 | 1:16.016；2:5.6056 | 1:271；2:95 | 1:748；2:262 | — |
| T3/Lv10 | 普通 | 1201/4805 | 249/574 | 1.弹体×1 | 1:15.925 | 1:289 | 1:799 | — |
| T3/Lv10 | 精英 | 1442/5766 | 279/642 | 1.弹体×1<br>2.地面区×0.35 | 1:17.836；2:6.2426 | 1:324；2:113 | 1:894；2:313 | — |
| T4/Lv15 | 普通 | 1422/5689 | 275/632 | 1.弹体×1 | 1:17.55 | 1:344 | 1:948 | — |
| T4/Lv15 | 精英 | 1707/6827 | 308/708 | 1.弹体×1<br>2.地面区×0.35 | 1:19.656；2:6.8796 | 1:385；2:135 | 1:1062；2:372 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.95`；`pierce=1`；`projectile_angles=[0.0]`；`radius=5.0`；`range=420.0`；`shape="line"`；`speed=330.0`；`spread_degrees=70.0`；`track=true` |
| T2-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.95`；`pierce=1`；`projectile_angles=[-7.0,7.0]`；`radius=5.0`；`range=420.0`；`shape="line"`；`speed=330.0`；`spread_degrees=14.0`；`track=true` |
| T3-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.95`；`pierce=1`；`projectile_angles=[-7.0,7.0]`；`radius=5.0`；`range=420.0`；`shape="line"`；`speed=330.0`；`spread_degrees=14.0`；`track=true` |
| T4-1 | 物理 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`count=3`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.2`；`pierce=1`；`projectile_angles=[-14.0,0.0,14.0]`；`radius=5.0`；`range=420.0`；`shape="line"`；`speed=330.0`；`spread_degrees=28.0`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M21 南瓜僵尸蹦跳兵（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1004/4018 | 219/504 | 1.位移攻击×1 | 1:14 | 1:219 | 1:605 | — |
| T1/Lv1 | 精英 | 1205/4821 | 246/565 | 1.位移攻击×1<br>2.地面区×0.35 | 1:15.68；2:5.488 | 1:246；2:86 | 1:678；2:237 | — |
| T2/Lv5 | 普通 | 1225/4901 | 241/555 | 1.位移攻击×1<br>2.近战×1 | 1:15.4；2:15.4 | 1:260；2:260 | 1:719；2:719 | — |
| T2/Lv5 | 精英 | 1470/5882 | 270/621 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:17.248；2:17.248；3:6.0368 | 1:292；2:292；3:102 | 1:805；2:805；3:282 | — |
| T3/Lv10 | 普通 | 1502/6006 | 269/618 | 1.位移攻击×1<br>2.近战×1 | 1:17.15；2:17.15 | 1:312；2:312 | 1:860；2:860 | — |
| T3/Lv10 | 精英 | 1802/7208 | 301/692 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:19.208；2:19.208；3:6.7228 | 1:349；2:349；3:122 | 1:963；2:963；3:337 | — |
| T4/Lv15 | 普通 | 1778/7111 | 296/681 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1 | 1:18.9；2:18.9；3:18.9 | 1:370；2:370；3:370 | 1:1022；2:1022；3:1022 | — |
| T4/Lv15 | 精英 | 2133/8533 | 331/762 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:21.168；2:21.168；3:21.168；4:7.4088 | 1:414；2:414；3:414；4:145 | 1:1143；2:1143；3:1143；4:400 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=219；下次直伤追加55<br>D4：shock 2s；系数0.8；power=605；下次直伤追加151 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="electric"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`inner_radius=17.4`；`landing_only=true`；`landing_shape="ring"`；`path_mode="leap"`；`radius=58.0`；`range=240.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=165.0` |
| T2-1 | 魔法 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=260；下次直伤追加65<br>D4：shock 2s；系数0.8；power=719；下次直伤追加180 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="electric"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`inner_radius=17.4`；`landing_only=true`；`landing_shape="ring"`；`path_mode="leap"`；`radius=58.0`；`range=240.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=165.0` |
| T2-2 | 魔法 | 每次命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=260；下次直伤追加65<br>D4：shock 2s；系数0.8；power=719；下次直伤追加180 | `aim_offset=80.0`；`angle=1.13446401379631`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=58.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T3-1 | 魔法 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=312；下次直伤追加78<br>D4：shock 2s；系数0.8；power=860；下次直伤追加215 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="electric"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`inner_radius=17.4`；`landing_only=true`；`landing_shape="ring"`；`path_mode="leap"`；`radius=58.0`；`range=240.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=165.0` |
| T3-2 | 魔法 | 每次命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=312；下次直伤追加78<br>D4：shock 2s；系数0.8；power=860；下次直伤追加215 | `aim_offset=80.0`；`angle=1.13446401379631`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=58.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T4-1 | 魔法 | 仅完成落地命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=370；下次直伤追加93<br>D4：shock 2s；系数0.8；power=1022；下次直伤追加256 | `angle=1.5707963267949`；`arc_height=0.0`；`damage_kind="electric"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.5`；`inner_radius=17.4`；`landing_only=true`；`landing_shape="ring"`；`path_mode="leap"`；`radius=58.0`；`range=240.0`；`shape="line"`；`speed=290.0`；`track=false`；`travel_distance=165.0` |
| T4-2 | 魔法 | 每次命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=370；下次直伤追加93<br>D4：shock 2s；系数0.8；power=1022；下次直伤追加256 | `aim_offset=80.0`；`angle=1.13446401379631`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.5`；`fixed_cycle_direction=true`；`radius=58.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T4-3 | 魔法 | 每次命中一次 | 预警0.85s；锁定0.4s | shock 2s；系数0.8；power=370；下次直伤追加93<br>D4：shock 2s；系数0.8；power=1022；下次直伤追加256 | `aim_offset=-80.0`；`angle=1.13446401379631`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.5`；`fixed_cycle_direction=true`；`radius=58.0`；`range=80.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M22 南瓜僵尸熔糖炮手（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 864/3455 | 218/501 | 1.地面区×1 | 1:13.92 | 1:218 | 1:601 | — |
| T1/Lv1 | 精英 | 1037/4146 | 244/562 | 1.地面区×1<br>2.地面区×0.35 | 1:15.5904；2:5.45664 | 1:244；2:85 | 1:674；2:236 | — |
| T2/Lv5 | 普通 | 1054/4215 | 240/552 | 1.地面区×1<br>2.地面区×1 | 1:15.312；2:15.312 | 1:259；2:259 | 1:715；2:715 | — |
| T2/Lv5 | 精英 | 1265/5058 | 269/618 | 1.地面区×1<br>2.地面区×1<br>3.地面区×0.35 | 1:17.14944；2:17.14944；3:6.002304 | 1:291；2:291；3:102 | 1:801；2:801；3:280 | — |
| T3/Lv10 | 普通 | 1291/5165 | 267/614 | 1.地面区×1<br>2.地面区×1 | 1:17.052；2:17.052 | 1:310；2:310 | 1:855；2:855 | — |
| T3/Lv10 | 精英 | 1550/6199 | 299/688 | 1.地面区×1<br>2.地面区×1<br>3.地面区×0.35 | 1:19.09824；2:19.09824；3:6.684384 | 1:347；2:347；3:121 | 1:958；2:958；3:335 | — |
| T4/Lv15 | 普通 | 1529/6116 | 294/677 | 1.地面区×1<br>2.地面区×1<br>3.地面区×1 | 1:18.792；2:18.792；3:18.792 | 1:368；2:368；3:368 | 1:1016；2:1016；3:1016 | — |
| T4/Lv15 | 精英 | 1835/7339 | 330/758 | 1.地面区×1<br>2.地面区×1<br>3.地面区×1<br>4.地面区×0.35 | 1:21.04704；2:21.04704；3:21.04704；4:7.366464 | 1:413；2:413；3:413；4:144 | 1:1137；2:1137；3:1137；4:398 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=218；每1s原伤害26<br>D4：burn 2s；系数0.8；power=601；每1s原伤害72 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.2`；`max_active_hazards=1`；`max_count=2`；`radius=55.0`；`range=300.0`；`shape="cone"`；`tick_interval=0.65`；`track=true` |
| T2-1 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=259；每1s原伤害31<br>D4：burn 2s；系数0.8；power=715；每1s原伤害86 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.2`；`max_active_hazards=1`；`max_count=2`；`radius=55.0`；`range=300.0`；`shape="cone"`；`tick_interval=0.65`；`track=true` |
| T2-2 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=259；每1s原伤害31<br>D4：burn 2s；系数0.8；power=715；每1s原伤害86 | `aim_offset=30.0`；`angle=1.5707963267949`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.2`；`max_active_hazards=1`；`max_count=2`；`origin_offset=[65.0,40.0]`；`radius=16.0`；`range=300.0`；`shape="line"`；`tick_interval=0.65`；`track=true` |
| T3-1 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=310；每1s原伤害37<br>D4：burn 2s；系数0.8；power=855；每1s原伤害103 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.2`；`max_active_hazards=1`；`max_count=2`；`radius=55.0`；`range=300.0`；`shape="cone"`；`tick_interval=0.65`；`track=true` |
| T3-2 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=310；每1s原伤害37<br>D4：burn 2s；系数0.8；power=855；每1s原伤害103 | `aim_offset=-30.0`；`angle=1.5707963267949`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.2`；`max_active_hazards=1`；`max_count=2`；`origin_offset=[65.0,-40.0]`；`radius=16.0`；`range=300.0`；`shape="line"`；`tick_interval=0.65`；`track=true` |
| T4-1 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=368；每1s原伤害44<br>D4：burn 2s；系数0.8；power=1016；每1s原伤害122 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.6`；`max_active_hazards=1`；`max_count=2`；`radius=55.0`；`range=300.0`；`shape="cone"`；`tick_interval=0.65`；`track=true` |
| T4-2 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=368；每1s原伤害44<br>D4：burn 2s；系数0.8；power=1016；每1s原伤害122 | `aim_offset=50.0`；`angle=0.785398163397448`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.6`；`max_active_hazards=1`；`max_count=2`；`radius=55.0`；`range=300.0`；`shape="cone"`；`tick_interval=0.65`；`track=true` |
| T4-3 | 魔法 | 每0.65s/跳；持续2.8s（最多4跳/区） | 预警0.85s；锁定0.4s | burn 2s；系数0.8；power=368；每1s原伤害44<br>D4：burn 2s；系数0.8；power=1016；每1s原伤害122 | `aim_offset=-30.0`；`angle=1.5707963267949`；`damage_kind="fire"`；`duration=2.8`；`exposure_seconds=1.6`；`max_active_hazards=1`；`max_count=2`；`origin_offset=[65.0,-40.0]`；`radius=16.0`；`range=300.0`；`shape="line"`；`tick_interval=0.65`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M23 南瓜僵尸牵引术士（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1071/4285 | 172/396 | 1.机关交互×1 | 1:0 | 1:0 | 1:0 | — |
| T1/Lv1 | 精英 | 1286/5143 | 193/444 | 1.机关交互×1<br>2.地面区×0.35 | 1:0；2:4.312 | 1:0；2:68 | 1:0；2:186 | — |
| T2/Lv5 | 普通 | 1307/5228 | 189/436 | 1.机关交互×1<br>2.机关交互×1 | 1:0；2:0 | 1:0；2:0 | 1:0；2:0 | — |
| T2/Lv5 | 精英 | 1568/6274 | 212/488 | 1.机关交互×1<br>2.机关交互×1<br>3.地面区×0.35 | 1:0；2:0；3:4.7432 | 1:0；2:0；3:80 | 1:0；2:0；3:221 | — |
| T3/Lv10 | 普通 | 1602/6407 | 211/485 | 1.机关交互×1<br>2.机关交互×1 | 1:0；2:0 | 1:0；2:0 | 1:0；2:0 | — |
| T3/Lv10 | 精英 | 1922/7688 | 236/544 | 1.机关交互×1<br>2.机关交互×1<br>3.地面区×0.35 | 1:0；2:0；3:5.2822 | 1:0；2:0；3:96 | 1:0；2:0；3:265 | — |
| T4/Lv15 | 普通 | 1896/7585 | 233/535 | 1.机关交互×1<br>2.机关交互×1<br>3.机关交互×1 | 1:0；2:0；3:0 | 1:0；2:0；3:0 | 1:0；2:0；3:0 | — |
| T4/Lv15 | 精英 | 2276/9102 | 260/599 | 1.机关交互×1<br>2.机关交互×1<br>3.机关交互×1<br>4.地面区×0.35 | 1:0；2:0；3:0；4:5.8212 | 1:0；2:0；3:0；4:114 | 1:0；2:0；3:0；4:314 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=0.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=2.5`；`duration=0.0`；`exposure_seconds=1.0`；`player_pull=true`；`polarity="pull"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=-35.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=3.0`；`duration=0.0`；`exposure_seconds=1.0`；`player_pull=true`；`polarity="pull"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |
| T2-2 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=35.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=3.0`；`duration=0.0`；`exposure_seconds=1.0`；`player_pull=true`；`polarity="push"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=-35.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=3.0`；`duration=0.0`；`exposure_seconds=1.0`；`player_pull=true`；`polarity="pull"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |
| T3-2 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=35.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=3.0`；`duration=0.0`；`exposure_seconds=1.0`；`player_pull=true`；`polarity="push"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=-35.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=3.0`；`duration=0.0`；`exposure_seconds=1.5`；`player_pull=true`；`polarity="pull"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |
| T4-2 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=35.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=3.0`；`duration=0.0`；`exposure_seconds=1.5`；`player_pull=true`；`polarity="push"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |
| T4-3 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="polarity_displacement"`；`aim_offset=0.0`；`angle=1.39626340159546`；`damage_kind="kinetic"`；`displacement_cooldown=3.0`；`duration=0.0`；`exposure_seconds=1.5`；`player_pull=true`；`polarity="pull"`；`preserve_dash=true`；`radius=36.0`；`range=180.0`；`shape="cone"`；`track=true`；`travel_distance=35.0` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M24 南瓜僵尸冰雾泵手（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 691/2764 | 236/543 | 1.地面区×1 | 1:15.08 | 1:236 | 1:652 | — |
| T1/Lv1 | 精英 | 829/3317 | 264/608 | 1.地面区×1<br>2.地面区×0.35 | 1:16.8896；2:5.91136 | 1:264；2:92 | 1:730；2:255 | — |
| T2/Lv5 | 普通 | 843/3372 | 260/597 | 1.地面区×1 | 1:16.588 | 1:281 | 1:774 | — |
| T2/Lv5 | 精英 | 1012/4047 | 291/669 | 1.地面区×1<br>2.地面区×0.35 | 1:18.57856；2:6.502496 | 1:314；2:110 | 1:867；2:303 | — |
| T3/Lv10 | 普通 | 1033/4132 | 289/665 | 1.地面区×1 | 1:18.473 | 1:335 | 1:926 | — |
| T3/Lv10 | 精英 | 1240/4959 | 324/745 | 1.地面区×1<br>2.地面区×0.35 | 1:20.68976；2:7.241416 | 1:376；2:132 | 1:1037；2:363 | — |
| T4/Lv15 | 普通 | 1223/4892 | 319/733 | 1.地面区×1<br>2.近战×1 | 1:20.358；2:20.358 | 1:399；2:399 | 1:1100；2:1100 | — |
| T4/Lv15 | 精英 | 1468/5871 | 357/821 | 1.地面区×1<br>2.近战×1<br>3.地面区×0.35 | 1:22.80096；2:22.80096；3:7.980336 | 1:446；2:446；3:156 | 1:1232；2:1232；3:431 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 每0.65s/跳；持续2.5s（最多3跳/区） | 预警0.85s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`damage_kind="cold"`；`duration=2.5`；`exposure_seconds=0.95`；`max_active_hazards=1`；`max_count=2`；`radius=60.0`；`range=250.0`；`shape="circle"`；`slow=0.2`；`target_offsets=[]`；`tick_interval=0.65`；`track=true` |
| T2-1 | 魔法 | 每0.65s/跳；持续2.5s（最多3跳/区） | 预警0.85s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`damage_kind="cold"`；`duration=2.5`；`exposure_seconds=0.95`；`max_active_hazards=2`；`max_count=2`；`radius=38.0`；`range=250.0`；`shape="circle"`；`slow=0.2`；`target_offsets=[[-52.0,0.0],[52.0,0.0]]`；`tick_interval=0.65`；`track=true` |
| T3-1 | 魔法 | 每0.65s/跳；持续2.5s（最多3跳/区） | 预警0.85s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`damage_kind="cold"`；`duration=2.5`；`exposure_seconds=0.95`；`max_active_hazards=2`；`max_count=2`；`radius=38.0`；`range=250.0`；`shape="circle"`；`slow=0.2`；`target_offsets=[[-45.0,-35.0],[45.0,35.0]]`；`tick_interval=0.65`；`track=true` |
| T4-1 | 魔法 | 每0.65s/跳；持续2.5s（最多3跳/区） | 预警0.85s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`damage_kind="cold"`；`duration=2.5`；`exposure_seconds=1.3`；`max_active_hazards=2`；`max_count=2`；`radius=38.0`；`range=250.0`；`shape="circle"`；`slow=0.2`；`target_offsets=[[-45.0,-35.0],[45.0,35.0]]`；`tick_interval=0.65`；`track=true` |
| T4-2 | 魔法 | 每次命中一次 | 预警0.85s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `aim_offset=35.0`；`angle=1.13446401379631`；`damage_kind="cold"`；`duration=0.0`；`exposure_seconds=1.3`；`radius=38.0`；`range=95.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M25 南瓜僵尸护盾卫士（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1468/5874 | 183/421 | 1.机关交互×1<br>2.近战×1 | 1:0；2:11.7 | 1:0；2:183 | 1:0；2:505 | 1.D0 guard_ratio=0.3；按本体生命样例440（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例1762（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |
| T1/Lv1 | 精英 | 1762/7048 | 205/472 | 1.机关交互×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:13.104；3:4.5864 | 1:0；2:205；3:72 | 1:0；2:566；3:198 | 1.D0 guard_ratio=0.3；按本体生命样例529（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例2114（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |
| T2/Lv5 | 普通 | 1791/7166 | 202/464 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:12.87；3:12.87 | 1:0；2:218；3:218 | 1:0；2:601；3:601 | 1.D0 guard_ratio=0.3；按本体生命样例537（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例2150（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |
| T2/Lv5 | 精英 | 2150/8599 | 226/519 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:14.4144；3:14.4144；4:5.04504 | 1:0；2:244；3:244；4:85 | 1:0；2:673；3:673；4:235 | 1.D0 guard_ratio=0.3；按本体生命样例645（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例2580（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |
| T3/Lv10 | 普通 | 2195/8781 | 224/516 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:14.3325；3:14.3325 | 1:0；2:260；3:260 | 1:0；2:718；3:718 | 1.D0 guard_ratio=0.3；按本体生命样例659（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例2634（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |
| T3/Lv10 | 精英 | 2634/10537 | 251/578 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:16.0524；3:16.0524；4:5.61834 | 1:0；2:291；3:291；4:102 | 1:0；2:805；3:805；4:282 | 1.D0 guard_ratio=0.3；按本体生命样例790（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例3161（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |
| T4/Lv15 | 普通 | 2599/10397 | 247/569 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:15.795；3:15.795；4:15.795 | 1:0；2:309；3:309；4:309 | 1:0；2:854；3:854；4:854 | 1.D0 guard_ratio=0.3；按本体生命样例780（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例3119（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |
| T4/Lv15 | 精英 | 3119/12476 | 277/637 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:17.6904；3:17.6904；4:17.6904；5:6.19164 | 1:0；2:346；3:346；4:346；5:121 | 1:0；2:956；3:956；4:956；5:334 | 1.D0 guard_ratio=0.3；按本体生命样例936（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加<br>D4 guard_ratio=0.3；按本体生命样例3743（受益目标生命×原比例）；shield_ratio为guard_ratio的回退别名，仅生成一次充盾，不叠加 |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="socket_recharge"`；`angle=1.5707963267949`；`damage_kind="electric"`；`duration=1.6`；`exposure_seconds=1.1`；`guard_ratio=0.3`；`only_if_depleted=true`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.3`；`track=false` |
| T1-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=183；下次直伤追加46<br>D4：shock 2s；系数0.8；power=505；下次直伤追加126 | `aim_offset=0.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T2-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="socket_recharge"`；`angle=1.5707963267949`；`damage_kind="electric"`；`duration=1.6`；`exposure_seconds=1.1`；`guard_ratio=0.3`；`only_if_depleted=true`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.3`；`track=false` |
| T2-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=218；下次直伤追加55<br>D4：shock 2s；系数0.8；power=601；下次直伤追加150 | `aim_offset=-25.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T2-3 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=218；下次直伤追加55<br>D4：shock 2s；系数0.8；power=601；下次直伤追加150 | `aim_offset=25.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T3-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="socket_recharge"`；`angle=1.5707963267949`；`damage_kind="electric"`；`duration=1.9`；`exposure_seconds=1.1`；`guard_ratio=0.3`；`only_if_depleted=true`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.3`；`track=false` |
| T3-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=260；下次直伤追加65<br>D4：shock 2s；系数0.8；power=718；下次直伤追加180 | `aim_offset=-25.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T3-3 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=260；下次直伤追加65<br>D4：shock 2s；系数0.8；power=718；下次直伤追加180 | `aim_offset=25.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T4-1 | 魔法 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="socket_recharge"`；`angle=1.5707963267949`；`damage_kind="electric"`；`duration=2.2`；`exposure_seconds=1.5`；`guard_ratio=0.3`；`only_if_depleted=true`；`radius=36.0`；`range=74.0`；`shape="circle"`；`shield_ratio=0.3`；`track=false` |
| T4-2 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=309；下次直伤追加77<br>D4：shock 2s；系数0.8；power=854；下次直伤追加214 | `aim_offset=-25.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.5`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T4-3 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=309；下次直伤追加77<br>D4：shock 2s；系数0.8；power=854；下次直伤追加214 | `aim_offset=25.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.5`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |
| T4-4 | 魔法 | 每次命中一次 | 预警0.65s；锁定0.4s | shock 2s；系数0.8；power=309；下次直伤追加77<br>D4：shock 2s；系数0.8；power=854；下次直伤追加214 | `aim_offset=0.0`；`angle=1.39626340159546`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.5`；`radius=36.0`；`range=74.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M26 南瓜僵尸裁缝护卫（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1468/5874 | 183/421 | 1.防护×1<br>2.近战×1 | 1:0；2:11.7 | 1:0；2:183 | 1:0；2:505 | — |
| T1/Lv1 | 精英 | 1762/7048 | 205/472 | 1.防护×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:13.104；3:4.5864 | 1:0；2:205；3:72 | 1:0；2:566；3:198 | — |
| T2/Lv5 | 普通 | 1791/7166 | 202/464 | 1.防护×1<br>2.近战×1<br>3.近战×1 | 1:0；2:12.87；3:12.87 | 1:0；2:218；3:218 | 1:0；2:601；3:601 | — |
| T2/Lv5 | 精英 | 2150/8599 | 226/519 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:14.4144；3:14.4144；4:5.04504 | 1:0；2:244；3:244；4:85 | 1:0；2:673；3:673；4:235 | — |
| T3/Lv10 | 普通 | 2195/8781 | 224/516 | 1.防护×1<br>2.近战×1<br>3.近战×1 | 1:0；2:14.3325；3:14.3325 | 1:0；2:260；3:260 | 1:0；2:718；3:718 | — |
| T3/Lv10 | 精英 | 2634/10537 | 251/578 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:16.0524；3:16.0524；4:5.61834 | 1:0；2:291；3:291；4:102 | 1:0；2:805；3:805；4:282 | — |
| T4/Lv15 | 普通 | 2599/10397 | 247/569 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:15.795；3:15.795；4:15.795 | 1:0；2:309；3:309；4:309 | 1:0；2:854；3:854；4:854 | — |
| T4/Lv15 | 精英 | 3119/12476 | 277/637 | 1.防护×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:17.6904；3:17.6904；4:17.6904；5:6.19164 | 1:0；2:346；3:346；4:346；5:121 | 1:0；2:956；3:956；4:956；5:334 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.5707963267949`；`charges=2`；`damage_kind="kinetic"`；`duration=1.0`；`exposure_seconds=1.1`；`mode="screen"`；`radius=42.0`；`range=74.0`；`shape="circle"`；`track=true` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.5707963267949`；`charges=2`；`damage_kind="kinetic"`；`duration=1.0`；`exposure_seconds=1.1`；`mode="screen"`；`radius=42.0`；`range=74.0`；`shape="circle"`；`track=true` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-35.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=90.0`；`angle=1.5707963267949`；`charges=2`；`damage_kind="kinetic"`；`duration=1.0`；`exposure_seconds=1.0`；`mode="screen"`；`radius=42.0`；`range=74.0`；`shape="circle"`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-35.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=90.0`；`angle=1.5707963267949`；`charges=3`；`damage_kind="kinetic"`；`duration=1.0`；`exposure_seconds=1.4`；`mode="screen"`；`radius=42.0`；`range=74.0`；`shape="circle"`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-35.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.4`；`radius=36.0`；`range=85.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M27 南瓜僵尸节拍铲兵（B3，F_HP=1.24 / F_A=1.16）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1004/4018 | 219/504 | 1.近战×1<br>2.近战×1 | 1:14；2:14 | 1:219；2:219 | 1:605；2:605 | — |
| T1/Lv1 | 精英 | 1205/4821 | 246/565 | 1.近战×1<br>2.近战×1<br>3.地面区×0.35 | 1:15.68；2:15.68；3:5.488 | 1:246；2:246；3:86 | 1:678；2:678；3:237 | — |
| T2/Lv5 | 普通 | 1225/4901 | 241/555 | 1.近战×1<br>2.近战×1<br>3.近战×1 | 1:15.4；2:15.4；3:15.4 | 1:260；2:260；3:260 | 1:719；2:719；3:719 | — |
| T2/Lv5 | 精英 | 1470/5882 | 270/621 | 1.近战×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:17.248；2:17.248；3:17.248；4:6.0368 | 1:292；2:292；3:292；4:102 | 1:805；2:805；3:805；4:282 | — |
| T3/Lv10 | 普通 | 1502/6006 | 269/618 | 1.近战×1<br>2.近战×1<br>3.近战×1 | 1:17.15；2:17.15；3:17.15 | 1:312；2:312；3:312 | 1:860；2:860；3:860 | — |
| T3/Lv10 | 精英 | 1802/7208 | 301/692 | 1.近战×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:19.208；2:19.208；3:19.208；4:6.7228 | 1:349；2:349；3:349；4:122 | 1:963；2:963；3:963；4:337 | — |
| T4/Lv15 | 普通 | 1778/7111 | 296/681 | 1.近战×1<br>2.近战×1<br>3.近战×1 | 1:18.9；2:18.9；3:18.9 | 1:370；2:370；3:370 | 1:1022；2:1022；3:1022 | — |
| T4/Lv15 | 精英 | 2133/8533 | 331/762 | 1.近战×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:21.168；2:21.168；3:21.168；4:7.4088 | 1:414；2:414；3:414；4:145 | 1:1143；2:1143；3:1143；4:400 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.610865238198015`；`beat=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="line"`；`track=false` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=80.0`；`angle=2.0943951023932`；`beat=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="cone"`；`track=false` |
| T2-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.610865238198015`；`beat=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="line"`；`track=false` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=80.0`；`angle=2.0943951023932`；`beat=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="cone"`；`track=false` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-80.0`；`angle=2.0943951023932`；`beat=3`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="cone"`；`track=false` |
| T3-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.610865238198015`；`beat=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="line"`；`track=false` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-80.0`；`angle=2.0943951023932`；`beat=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="cone"`；`track=false` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=80.0`；`angle=2.0943951023932`；`beat=3`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="cone"`；`track=false` |
| T4-1 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-35.0`；`angle=0.610865238198015`；`beat=1`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.45`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="line"`；`track=false` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=35.0`；`angle=2.0943951023932`；`beat=2`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.45`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="cone"`；`track=false` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=2.0943951023932`；`beat=3`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.45`；`fixed_cycle_direction=true`；`radius=18.0`；`range=68.0`；`shape="cone"`；`track=false` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M28 赤岩兽人疾行斥候（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 370/1481 | 251/578 | 1.位移攻击×1 | 1:15 | 1:251 | 1:694 | — |
| T1/Lv1 | 精英 | 444/1777 | 281/647 | 1.位移攻击×1<br>2.地面区×0.35 | 1:16.8；2:5.88 | 1:281；2:98 | 1:776；2:272 | — |
| T2/Lv5 | 普通 | 452/1806 | 276/635 | 1.位移攻击×1<br>2.近战×1 | 1:16.5；2:16.5 | 1:298；2:298 | 1:823；2:823 | — |
| T2/Lv5 | 精英 | 542/2168 | 309/712 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:18.48；2:18.48；3:6.468 | 1:334；2:334；3:117 | 1:923；2:923；3:323 | — |
| T3/Lv10 | 普通 | 553/2213 | 308/707 | 1.位移攻击×1<br>2.近战×1 | 1:18.375；2:18.375 | 1:357；2:357 | 1:984；2:984 | — |
| T3/Lv10 | 精英 | 664/2656 | 345/792 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:20.58；2:20.58；3:7.203 | 1:400；2:400；3:140 | 1:1102；2:1102；3:386 | — |
| T4/Lv15 | 普通 | 655/2621 | 339/780 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1 | 1:20.25；2:20.25；3:20.25 | 1:424；2:424；3:424 | 1:1170；2:1170；3:1170 | — |
| T4/Lv15 | 精英 | 786/3145 | 380/873 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:22.68；2:22.68；3:22.68；4:7.938 | 1:475；2:475；3:475；4:166 | 1:1310；2:1310；3:1310；4:458 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=false`；`path_mode="line"`；`radius=14.0`；`range=170.0`；`shape="line"`；`speed=320.0`；`target_last_sound=true`；`track=false`；`travel_distance=120.0` |
| T2-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=false`；`path_mode="line"`；`radius=14.0`；`range=170.0`；`shape="line"`；`speed=320.0`；`target_last_sound=true`；`track=false`；`travel_distance=120.0` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.7`；`fixed_cycle_direction=true`；`radius=36.0`；`range=52.0`；`shape="cone"`；`track=false` |
| T3-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=0.7`；`landing_only=false`；`path_mode="line"`；`radius=14.0`；`range=170.0`；`shape="line"`；`speed=320.0`；`target_last_sound=true`；`track=false`；`travel_distance=120.0` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.7`；`fixed_cycle_direction=true`；`radius=36.0`；`range=52.0`；`shape="cone"`；`track=false` |
| T4-1 | 物理 | 沿途每目标最多一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.0`；`landing_only=false`；`path_mode="line"`；`radius=14.0`；`range=170.0`；`shape="line"`；`speed=320.0`；`target_last_sound=true`；`track=false`；`travel_distance=120.0` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=52.0`；`shape="cone"`；`track=false` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-25.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`fixed_cycle_direction=true`；`radius=36.0`；`range=52.0`；`shape="cone"`；`track=false` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M29 赤岩兽人幻影刀手（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 714/2855 | 251/578 | 1.诱饵×0<br>2.近战×1 | 1:0；2:15 | 1:0；2:251 | 1:0；2:694 | — |
| T1/Lv1 | 精英 | 857/3426 | 281/647 | 1.诱饵×0<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:16.8；3:5.88 | 1:0；2:281；3:98 | 1:0；2:776；3:272 | — |
| T2/Lv5 | 普通 | 871/3484 | 276/635 | 1.诱饵×0<br>2.近战×1<br>3.近战×1 | 1:0；2:16.5；3:16.5 | 1:0；2:298；3:298 | 1:0；2:823；3:823 | — |
| T2/Lv5 | 精英 | 1045/4180 | 309/712 | 1.诱饵×0<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:18.48；3:18.48；4:6.468 | 1:0；2:334；3:334；4:117 | 1:0；2:923；3:923；4:323 | — |
| T3/Lv10 | 普通 | 1067/4269 | 308/707 | 1.诱饵×0<br>2.近战×1<br>3.近战×1 | 1:0；2:18.375；3:18.375 | 1:0；2:357；3:357 | 1:0；2:984；3:984 | — |
| T3/Lv10 | 精英 | 1281/5122 | 345/792 | 1.诱饵×0<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:20.58；3:20.58；4:7.203 | 1:0；2:400；3:400；4:140 | 1:0；2:1102；3:1102；4:386 | — |
| T4/Lv15 | 普通 | 1263/5054 | 339/780 | 1.诱饵×0<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:20.25；3:20.25；4:20.25 | 1:0；2:424；3:424；4:424 | 1:0；2:1170；3:1170；4:1170 | — |
| T4/Lv15 | 精英 | 1516/6065 | 380/873 | 1.诱饵×0<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:22.68；3:22.68；4:22.68；5:7.938 | 1:0；2:475；3:475；4:475；5:166 | 1:0；2:1310；3:1310；4:1310；5:458 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable_hits=1`；`count=1`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=0.9`；`radius=70.0`；`range=80.0`；`shape="circle"`；`solid_owner_ring=true`；`track=true` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable_hits=1`；`count=1`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=0.9`；`radius=70.0`；`range=80.0`；`shape="circle"`；`solid_owner_ring=true`；`track=true` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-25.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable_hits=1`；`count=1`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=0.9`；`radius=70.0`；`range=80.0`；`shape="circle"`；`solid_owner_ring=true`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-25.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`breakable_hits=1`；`count=1`；`damage_kind="kinetic"`；`duration=2.5`；`exposure_seconds=1.3`；`radius=70.0`；`range=80.0`；`shape="circle"`；`solid_owner_ring=true`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-25.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.3`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=25.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.3`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.0471975511966`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.3`；`fixed_cycle_direction=true`；`radius=36.0`；`range=80.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M30 赤岩兽人战鼓祭司（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 917/3666 | 105/243 | 1.防护×1 | 1:0 | 1:0 | 1:0 | 1.D0 shield_ratio=0.18；按本体生命样例165（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例660（受益目标生命×原比例） |
| T1/Lv1 | 精英 | 1100/4399 | 118/272 | 1.防护×1<br>2.地面区×0.35 | 1:0；2:2.4696 | 1:0；2:41 | 1:0；2:114 | 1.D0 shield_ratio=0.18；按本体生命样例198（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例792（受益目标生命×原比例） |
| T2/Lv5 | 普通 | 1118/4473 | 116/267 | 1.防护×1 | 1:0 | 1:0 | 1:0 | 1.D0 shield_ratio=0.18；按本体生命样例201（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例805（受益目标生命×原比例） |
| T2/Lv5 | 精英 | 1342/5367 | 130/299 | 1.防护×1<br>2.地面区×0.35 | 1:0；2:2.71656 | 1:0；2:49 | 1:0；2:136 | 1.D0 shield_ratio=0.18；按本体生命样例242（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例966（受益目标生命×原比例） |
| T3/Lv10 | 普通 | 1370/5481 | 129/297 | 1.防护×1<br>2.近战×0.65<br>3.近战×0.65 | 1:0；2:5.016375；3:5.016375 | 1:0；2:97；3:97 | 1:0；2:269；3:269 | 1.D0 shield_ratio=0.18；按本体生命样例247（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例987（受益目标生命×原比例） |
| T3/Lv10 | 精英 | 1644/6577 | 145/333 | 1.防护×1<br>2.近战×0.65<br>3.近战×0.65<br>4.地面区×0.35 | 1:0；2:5.61834；3:5.61834；4:3.02526 | 1:0；2:109；3:109；4:59 | 1:0；2:301；3:301；4:162 | 1.D0 shield_ratio=0.18；按本体生命样例296（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例1184（受益目标生命×原比例） |
| T4/Lv15 | 普通 | 1622/6489 | 142/327 | 1.防护×1<br>2.近战×0.65<br>3.近战×0.65 | 1:0；2:5.52825；3:5.52825 | 1:0；2:115；3:115 | 1:0；2:319；3:319 | 1.D0 shield_ratio=0.18；按本体生命样例292（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例1168（受益目标生命×原比例） |
| T4/Lv15 | 精英 | 1947/7787 | 159/367 | 1.防护×1<br>2.近战×0.65<br>3.近战×0.65<br>4.地面区×0.35 | 1:0；2:6.19164；3:6.19164；4:3.33396 | 1:0；2:129；3:129；4:70 | 1:0；2:358；3:358；4:193 | 1.D0 shield_ratio=0.18；按本体生命样例350（受益目标生命×原比例）<br>D4 shield_ratio=0.18；按本体生命样例1402（受益目标生命×原比例） |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`break_on_range=true`；`charges=2`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.0`；`max_targets=1`；`mode="network"`；`radius=240.0`；`range=240.0`；`shape="circle"`；`shield_ratio=0.18`；`support_charges=2`；`support_targets=1`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`break_on_range=true`；`charges=2`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.0`；`max_targets=2`；`mode="network"`；`radius=240.0`；`range=240.0`；`shape="circle"`；`shield_ratio=0.18`；`support_charges=2`；`support_targets=2`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`break_on_range=true`；`charges=2`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.0`；`max_targets=2`；`mode="network"`；`radius=240.0`；`range=240.0`；`shape="circle"`；`shield_ratio=0.18`；`support_charges=2`；`support_targets=2`；`track=true` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-50.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=50.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.0`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`break_on_range=true`；`charges=2`；`damage_kind="kinetic"`；`duration=2.5`；`exclude_same_behavior=true`；`exclude_self=true`；`exclude_support_recipients=true`；`exposure_seconds=1.6`；`max_targets=3`；`mode="network"`；`radius=270.0`；`range=270.0`；`shape="circle"`；`shield_ratio=0.18`；`support_charges=2`；`support_targets=3`；`track=true` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-50.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=50.0`；`angle=1.22173047639603`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M31 赤岩兽人冷晶弩手（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 758/3032 | 252/581 | 1.弹体×1 | 1:15.08 | 1:252 | 1:697 | — |
| T1/Lv1 | 精英 | 909/3638 | 283/650 | 1.弹体×1<br>2.地面区×0.35 | 1:16.8896；2:5.91136 | 1:283；2:99 | 1:780；2:273 | — |
| T2/Lv5 | 普通 | 925/3699 | 278/639 | 1.弹体×1 | 1:16.588 | 1:300 | 1:828 | — |
| T2/Lv5 | 精英 | 1110/4438 | 311/715 | 1.弹体×1<br>2.地面区×0.35 | 1:18.57856；2:6.502496 | 1:336；2:118 | 1:927；2:324 | — |
| T3/Lv10 | 普通 | 1133/4532 | 309/711 | 1.弹体×1 | 1:18.473 | 1:358 | 1:990 | — |
| T3/Lv10 | 精英 | 1360/5439 | 346/797 | 1.弹体×1<br>2.地面区×0.35 | 1:20.68976；2:7.241416 | 1:401；2:140 | 1:1109；2:388 | — |
| T4/Lv15 | 普通 | 1341/5366 | 341/784 | 1.弹体×1 | 1:20.358 | 1:426 | 1:1176 | — |
| T4/Lv15 | 精英 | 1610/6439 | 382/878 | 1.弹体×1<br>2.地面区×0.35 | 1:22.80096；2:7.980336 | 1:478；2:167 | 1:1317；2:461 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`count=1`；`damage_kind="cold"`；`duration=0.0`；`exposure_seconds=0.95`；`max_reflections=1`；`pierce=true`；`projectile_angles=[0.0]`；`radius=7.0`；`range=430.0`；`refraction=true`；`shape="line"`；`speed=330.0`；`spread_degrees=70.0`；`track=true` |
| T2-1 | 魔法 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`count=2`；`damage_kind="cold"`；`duration=0.0`；`exposure_seconds=0.95`；`max_reflections=1`；`pierce=true`；`projectile_angles=[-8.0,8.0]`；`radius=7.0`；`range=430.0`；`refraction=true`；`shape="line"`；`speed=330.0`；`spread_degrees=16.0`；`track=true` |
| T3-1 | 魔法 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`count=2`；`damage_kind="cold"`；`duration=0.0`；`exposure_seconds=0.95`；`max_reflections=1`；`pierce=true`；`projectile_angles=[-8.0,8.0]`；`radius=7.0`；`range=430.0`；`refraction=true`；`shape="line"`；`speed=330.0`；`spread_degrees=16.0`；`track=true` |
| T4-1 | 魔法 | 每枚弹体命中一次 | 预警0.65s；锁定0.4s | chill 2s；系数0.8<br>D4：chill 2s；系数0.8 | `angle=1.5707963267949`；`count=3`；`damage_kind="cold"`；`duration=0.0`；`exposure_seconds=1.5`；`max_reflections=1`；`pierce=true`；`projectile_angles=[-16.0,0.0,16.0]`；`radius=7.0`；`range=430.0`；`refraction=true`；`shape="line"`；`speed=330.0`；`spread_degrees=32.0`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M32 赤岩兽人跃袭猎手（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 793/3173 | 281/647 | 1.位移攻击×1 | 1:16.8 | 1:281 | 1:776 | — |
| T1/Lv1 | 精英 | 952/3807 | 315/724 | 1.位移攻击×1<br>2.地面区×0.35 | 1:18.816；2:6.5856 | 1:315；2:110 | 1:869；2:304 | — |
| T2/Lv5 | 普通 | 968/3871 | 309/712 | 1.位移攻击×1<br>2.近战×1 | 1:18.48；2:18.48 | 1:334；2:334 | 1:923；2:923 | — |
| T2/Lv5 | 精英 | 1161/4645 | 346/797 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:20.6976；2:20.6976；3:7.24416 | 1:374；2:374；3:131 | 1:1033；2:1033；3:362 | — |
| T3/Lv10 | 普通 | 1186/4743 | 345/792 | 1.位移攻击×1<br>2.近战×1 | 1:20.58；2:20.58 | 1:400；2:400 | 1:1102；2:1102 | — |
| T3/Lv10 | 精英 | 1423/5692 | 386/887 | 1.位移攻击×1<br>2.近战×1<br>3.地面区×0.35 | 1:23.0496；2:23.0496；3:8.06736 | 1:448；2:448；3:157 | 1:1235；2:1235；3:432 | — |
| T4/Lv15 | 普通 | 1404/5616 | 380/873 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1 | 1:22.68；2:22.68；3:22.68 | 1:475；2:475；3:475 | 1:1310；2:1310；3:1310 | — |
| T4/Lv15 | 精英 | 1685/6739 | 425/978 | 1.位移攻击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:25.4016；2:25.4016；3:25.4016；4:8.89056 | 1:531；2:531；3:531；4:186 | 1:1467；2:1467；3:1467；4:513 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=true`；`landing_shape="circle"`；`path_mode="arc"`；`radius=36.0`；`range=250.0`；`requires_stealth_terrain=true`；`shape="line"`；`speed=240.0`；`track=false`；`travel_distance=180.0` |
| T2-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=true`；`landing_shape="circle"`；`path_mode="arc"`；`radius=36.0`；`range=250.0`；`requires_stealth_terrain=true`；`shape="line"`；`speed=240.0`；`track=false`；`travel_distance=180.0` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=65.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=-1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.1`；`landing_only=true`；`landing_shape="circle"`；`path_mode="arc"`；`radius=36.0`；`range=250.0`；`requires_stealth_terrain=true`；`shape="line"`；`speed=240.0`；`track=false`；`travel_distance=180.0` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=65.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 仅完成落地命中一次 | 预警0.8s；锁定0.4s | 无<br>D4：无 | `angle=1.5707963267949`；`arc_angle=-1.13446401379631`；`damage_kind="kinetic"`；`duration=0.0`；`expose_on_wall=true`；`exposure_seconds=1.6`；`landing_only=true`；`landing_shape="circle"`；`path_mode="arc"`；`radius=36.0`；`range=250.0`；`requires_stealth_terrain=true`；`shape="line"`；`speed=240.0`；`track=false`；`travel_distance=180.0` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=65.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-65.0`；`angle=1.74532925199433`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M33 赤岩兽人绳网猎手（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1375/5499 | 211/485 | 1.地面区×0 | 1:0 | 1:0 | 1:0 | 1.D0 anchor_health=160<br>D4 anchor_health=192 |
| T1/Lv1 | 精英 | 1650/6599 | 236/543 | 1.地面区×0<br>2.地面区×0.35 | 1:0；2:4.9392 | 1:0；2:83 | 1:0；2:228 | 1.D0 anchor_health=160<br>D4 anchor_health=192 |
| T2/Lv5 | 普通 | 1677/6709 | 232/534 | 1.地面区×0<br>2.地面区×0 | 1:0；2:0 | 1:0；2:0 | 1:0；2:0 | 1.D0 anchor_health=173<br>D4 anchor_health=207<br>2.D0 anchor_health=173<br>D4 anchor_health=207 |
| T2/Lv5 | 精英 | 2013/8051 | 260/598 | 1.地面区×0<br>2.地面区×0<br>3.地面区×0.35 | 1:0；2:0；3:5.43312 | 1:0；2:0；3:98 | 1:0；2:0；3:271 | 1.D0 anchor_health=173<br>D4 anchor_health=207<br>2.D0 anchor_health=173<br>D4 anchor_health=207 |
| T3/Lv10 | 普通 | 2055/8221 | 258/594 | 1.地面区×0<br>2.地面区×0 | 1:0；2:0 | 1:0；2:0 | 1:0；2:0 | 1.D0 anchor_health=186<br>D4 anchor_health=223<br>2.D0 anchor_health=186<br>D4 anchor_health=223 |
| T3/Lv10 | 精英 | 2466/9866 | 289/666 | 1.地面区×0<br>2.地面区×0<br>3.地面区×0.35 | 1:0；2:0；3:6.05052 | 1:0；2:0；3:117 | 1:0；2:0；3:324 | 1.D0 anchor_health=186<br>D4 anchor_health=223<br>2.D0 anchor_health=186<br>D4 anchor_health=223 |
| T4/Lv15 | 普通 | 2433/9734 | 285/655 | 1.地面区×0<br>2.地面区×0 | 1:0；2:0 | 1:0；2:0 | 1:0；2:0 | 1.D0 anchor_health=150<br>D4 anchor_health=180<br>2.D0 anchor_health=150<br>D4 anchor_health=180 |
| T4/Lv15 | 精英 | 2920/11680 | 319/734 | 1.地面区×0<br>2.地面区×0<br>3.地面区×0.35 | 1:0；2:0；3:6.66792 | 1:0；2:0；3:140 | 1:0；2:0；3:385 | 1.D0 anchor_health=150<br>D4 anchor_health=180<br>2.D0 anchor_health=150<br>D4 anchor_health=180 |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 每0.65s/跳；持续3s（最多4跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `aim_offset=0.0`；`anchor_health=16.0`；`angle=1.5707963267949`；`breakable=true`；`damage_kind="kinetic"`；`duration=3.0`；`exposure_seconds=1.05`；`max_active_hazards=2`；`max_count=2`；`origin_offset=[]`；`radius=9.0`；`range=250.0`；`shape="line"`；`tick_interval=0.65`；`track=false` |
| T2-1 | 物理 | 每0.65s/跳；持续3s（最多4跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `aim_offset=0.0`；`anchor_health=16.0`；`angle=1.5707963267949`；`breakable=true`；`damage_kind="kinetic"`；`duration=3.0`；`exposure_seconds=1.05`；`max_active_hazards=2`；`max_count=2`；`origin_offset=[-60.0,-30.0]`；`radius=9.0`；`range=250.0`；`shape="line"`；`tick_interval=0.65`；`track=false` |
| T2-2 | 物理 | 每0.65s/跳；持续3s（最多4跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `aim_offset=25.0`；`anchor_health=16.0`；`angle=1.5707963267949`；`breakable=true`；`damage_kind="kinetic"`；`duration=3.0`；`exposure_seconds=1.05`；`max_active_hazards=2`；`max_count=2`；`origin_offset=[60.0,30.0]`；`radius=9.0`；`range=250.0`；`shape="line"`；`tick_interval=0.65`；`track=false` |
| T3-1 | 物理 | 每0.65s/跳；持续3s（最多4跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `aim_offset=0.0`；`anchor_health=16.0`；`angle=1.5707963267949`；`breakable=true`；`damage_kind="kinetic"`；`duration=3.0`；`exposure_seconds=1.05`；`max_active_hazards=2`；`max_count=2`；`origin_offset=[-70.0,0.0]`；`radius=9.0`；`range=250.0`；`shape="line"`；`tick_interval=0.65`；`track=false` |
| T3-2 | 物理 | 每0.65s/跳；持续3s（最多4跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `aim_offset=25.0`；`anchor_health=16.0`；`angle=1.5707963267949`；`breakable=true`；`damage_kind="kinetic"`；`duration=3.0`；`exposure_seconds=1.05`；`max_active_hazards=2`；`max_count=2`；`origin_offset=[70.0,0.0]`；`radius=9.0`；`range=250.0`；`shape="line"`；`tick_interval=0.65`；`track=false` |
| T4-1 | 物理 | 每0.65s/跳；持续3s（最多4跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `aim_offset=-30.0`；`anchor_health=12.0`；`angle=1.5707963267949`；`breakable=true`；`damage_kind="kinetic"`；`duration=3.0`；`exposure_seconds=1.5`；`max_active_hazards=2`；`max_count=2`；`origin_offset=[-70.0,0.0]`；`radius=9.0`；`range=250.0`；`shape="line"`；`tick_interval=0.65`；`track=false` |
| T4-2 | 物理 | 每0.65s/跳；持续3s（最多4跳/区） | 预警0.8s；锁定0.4s | slow 0.8s；系数0.8<br>D4：slow 0.8s；系数0.8 | `aim_offset=30.0`；`anchor_health=12.0`；`angle=1.5707963267949`；`breakable=true`；`damage_kind="kinetic"`；`duration=3.0`；`exposure_seconds=1.5`；`max_active_hazards=2`；`max_count=2`；`origin_offset=[70.0,0.0]`；`radius=9.0`；`range=250.0`；`shape="line"`；`tick_interval=0.65`；`track=false` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M34 赤岩食人魔反击卫（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1611/6442 | 196/450 | 1.受击反击×1<br>2.近战×1 | 1:0；2:11.7 | 1:0；2:196 | 1:0；2:540 | — |
| T1/Lv1 | 精英 | 1933/7731 | 219/505 | 1.受击反击×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:13.104；3:4.5864 | 1:0；2:219；3:77 | 1:0；2:606；3:212 | — |
| T2/Lv5 | 普通 | 1965/7859 | 215/496 | 1.受击反击×1<br>2.近战×1<br>3.近战×1 | 1:0；2:12.87；3:12.87 | 1:0；2:232；3:232 | 1:0；2:643；3:643 | — |
| T2/Lv5 | 精英 | 2358/9431 | 241/555 | 1.受击反击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:14.4144；3:14.4144；4:5.04504 | 1:0；2:260；3:260；4:91 | 1:0；2:719；3:719；4:252 | — |
| T3/Lv10 | 普通 | 2408/9631 | 240/552 | 1.受击反击×1<br>2.近战×1<br>3.近战×1 | 1:0；2:14.3325；3:14.3325 | 1:0；2:278；3:278 | 1:0；2:768；3:768 | — |
| T3/Lv10 | 精英 | 2889/11557 | 269/618 | 1.受击反击×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:16.0524；3:16.0524；4:5.61834 | 1:0；2:312；3:312；4:109 | 1:0；2:860；3:860；4:301 | — |
| T4/Lv15 | 普通 | 2851/11403 | 264/608 | 1.受击反击×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:15.795；3:15.795；4:15.795 | 1:0；2:330；3:330；4:330 | 1:0；2:912；3:912；4:912 | — |
| T4/Lv15 | 精英 | 3421/13683 | 296/681 | 1.受击反击×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:17.6904；3:17.6904；4:17.6904；5:6.19164 | 1:0；2:370；3:370；4:370；5:130 | 1:0；2:1022；3:1022；4:1022；5:358 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 反击架势0伤害；随后独立近战命令计伤 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.74532925199433`；`auto_release=false`；`damage_kind="kinetic"`；`duration=1.2`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`hit_cap=2`；`radius=36.0`；`range=74.0`；`shape="circle"`；`track=false` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |
| T2-1 | 物理 | 反击架势0伤害；随后独立近战命令计伤 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.74532925199433`；`auto_release=false`；`damage_kind="kinetic"`；`duration=1.2`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`hit_cap=2`；`radius=36.0`；`range=74.0`；`shape="circle"`；`track=false` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=45.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |
| T3-1 | 物理 | 反击架势0伤害；随后独立近战命令计伤 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=1.74532925199433`；`auto_release=false`；`damage_kind="kinetic"`；`duration=1.2`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`hit_cap=2`；`radius=36.0`；`range=74.0`；`shape="circle"`；`track=false` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=45.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.1`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |
| T4-1 | 物理 | 反击架势0伤害；随后独立近战命令计伤 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=1.74532925199433`；`auto_release=false`；`damage_kind="kinetic"`；`duration=1.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`hit_cap=2`；`radius=36.0`；`range=74.0`；`shape="circle"`；`track=false` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=45.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=-45.0`；`angle=0.785398163397448`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=20.0`；`range=74.0`；`shape="line"`；`track=false` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M35 赤岩食人魔窃灯手（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 1022/4089 | 151/347 | 1.机关交互×1<br>2.近战×1 | 1:0；2:9 | 1:0；2:151 | 1:0；2:416 | — |
| T1/Lv1 | 精英 | 1227/4907 | 169/388 | 1.机关交互×1<br>2.近战×1<br>3.地面区×0.35 | 1:0；2:10.08；3:3.528 | 1:0；2:169；3:59 | 1:0；2:466；3:163 | — |
| T2/Lv5 | 普通 | 1247/4989 | 166/381 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:9.9；3:9.9 | 1:0；2:179；3:179 | 1:0；2:494；3:494 | — |
| T2/Lv5 | 精英 | 1497/5986 | 186/427 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:11.088；3:11.088；4:3.8808 | 1:0；2:201；3:201；4:70 | 1:0；2:553；3:553；4:194 | — |
| T3/Lv10 | 普通 | 1528/6113 | 185/424 | 1.机关交互×1<br>2.近战×1<br>3.近战×1 | 1:0；2:11.025；3:11.025 | 1:0；2:215；3:215 | 1:0；2:590；3:590 | — |
| T3/Lv10 | 精英 | 1834/7336 | 207/475 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.地面区×0.35 | 1:0；2:12.348；3:12.348；4:4.3218 | 1:0；2:240；3:240；4:84 | 1:0；2:661；3:661；4:231 | — |
| T4/Lv15 | 普通 | 1809/7238 | 203/468 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1 | 1:0；2:12.15；3:12.15；4:12.15 | 1:0；2:254；3:254；4:254 | 1:0；2:702；3:702；4:702 | — |
| T4/Lv15 | 精英 | 2171/8685 | 228/524 | 1.机关交互×1<br>2.近战×1<br>3.近战×1<br>4.近战×1<br>5.地面区×0.35 | 1:0；2:13.608；3:13.608；4:13.608；5:4.7628 | 1:0；2:285；3:285；4:285；5:100 | 1:0；2:786；3:786；4:786；5:275 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_scene_lamp"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=5.0`；`exposure_seconds=0.9`；`keep_telegraphs_visible=true`；`radius=110.0`；`range=180.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T1-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T2-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_scene_lamp"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=5.0`；`exposure_seconds=0.9`；`keep_telegraphs_visible=true`；`radius=110.0`；`range=180.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T2-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T2-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T3-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_scene_lamp"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=5.0`；`exposure_seconds=0.9`；`keep_telegraphs_visible=true`；`radius=110.0`；`range=180.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T3-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T3-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=0.9`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T4-1 | 物理 | 无直接伤害 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `action="steal_scene_lamp"`；`angle=1.5707963267949`；`carry_limit=1`；`damage_kind="kinetic"`；`duration=5.0`；`exposure_seconds=1.6`；`keep_telegraphs_visible=true`；`radius=110.0`；`range=180.0`；`return_intact=true`；`shape="circle"`；`track=false` |
| T4-2 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=0.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T4-3 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=180.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |
| T4-4 | 物理 | 每次命中一次 | 预警0.65s；锁定0.4s | 无<br>D4：无 | `aim_offset=70.0`；`angle=1.83259571459405`；`damage_kind="kinetic"`；`duration=0.0`；`exposure_seconds=1.6`；`fixed_cycle_direction=true`；`radius=36.0`；`range=70.0`；`shape="cone"`；`track=true` |


精英最后一项是已有固定方向余震：原系数0.35，线形半径20、持续/每跳0.35s、预警0.8s、锁定0.4s，理论1跳；伤害类型同原型。前列技能顺序与普通一致。

### M36 赤岩兽人雷符爆破兵（B4，F_HP=1.36 / F_A=1.24）

| 阶/参考级 | 身份 | 目标生命D0/D4 | 目标A D0/D4 | 完整命令序列与原系数 | 当前D0原伤害（浮点） | 目标D0整数Q | 目标D4整数Q | 盾/治疗/端点目标量 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1/Lv1 | 普通 | 600/2400 | 283/651 | 1.地面区×1 | 1:16.9 | 1:283 | 1:781 | — |
| T1/Lv1 | 精英 | 720/2880 | 317/729 | 1.地面区×1 | 1:18.928 | 1:317 | 1:875 | — |
| T2/Lv5 | 普通 | 732/2928 | 311/716 | 1.地面区×1 | 1:18.59 | 1:336 | 1:928 | — |
| T2/Lv5 | 精英 | 878/3514 | 349/802 | 1.地面区×1 | 1:20.8208 | 1:377 | 1:1039 | — |
| T3/Lv10 | 普通 | 897/3588 | 347/797 | 1.地面区×1 | 1:20.7025 | 1:403 | 1:1109 | — |
| T3/Lv10 | 精英 | 1076/4306 | 388/893 | 1.地面区×1 | 1:23.1868 | 1:450 | 1:1243 | — |
| T4/Lv15 | 普通 | 1062/4248 | 382/878 | 1.地面区×1 | 1:22.815 | 1:478 | 1:1317 | — |
| T4/Lv15 | 精英 | 1274/5098 | 428/984 | 1.地面区×1 | 1:25.5528 | 1:535 | 1:1476 | — |


| 命令位置 | 类型 | 计伤单位/持续区域每跳 | 保留时序 | 普通目标状态输入D0/D4 | 原机制参数（百分比/时空/数量保持） |
| --- | --- | --- | --- | --- | --- |
| T1-1 | 魔法 | 一次区域命中 | 预警1.3s；锁定0.4s | shock 2s；系数0.8；power=283；下次直伤追加71<br>D4：shock 2s；系数0.8；power=781；下次直伤追加195 | `angle=1.5707963267949`；`cancel_on_death=true`；`center="self"`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=0.9`；`inner_radius=0.0`；`max_active_hazards=1`；`max_count=2`；`radius=85.0`；`range=120.0`；`ring_gap_degrees=0.0`；`shape="ring"`；`single_use=true`；`tick_interval=0.65`；`track=true` |
| T2-1 | 魔法 | 一次区域命中 | 预警1.3s；锁定0.4s | shock 2s；系数0.8；power=336；下次直伤追加84<br>D4：shock 2s；系数0.8；power=928；下次直伤追加232 | `angle=1.5707963267949`；`cancel_on_death=true`；`center="self"`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=0.9`；`inner_radius=0.0`；`max_active_hazards=1`；`max_count=2`；`radius=85.0`；`range=120.0`；`ring_gap_degrees=0.0`；`shape="ring"`；`single_use=true`；`tick_interval=0.65`；`track=true` |
| T3-1 | 魔法 | 一次区域命中 | 预警1.3s；锁定0.4s | shock 2s；系数0.8；power=403；下次直伤追加101<br>D4：shock 2s；系数0.8；power=1109；下次直伤追加277 | `angle=1.5707963267949`；`cancel_on_death=true`；`center="self"`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=0.9`；`inner_radius=0.0`；`max_active_hazards=1`；`max_count=2`；`radius=85.0`；`range=120.0`；`ring_gap_degrees=65.0`；`shape="ring"`；`single_use=true`；`tick_interval=0.65`；`track=true` |
| T4-1 | 魔法 | 一次区域命中 | 预警1.6s；锁定0.4s | shock 2s；系数0.8；power=478；下次直伤追加120<br>D4：shock 2s；系数0.8；power=1317；下次直伤追加329 | `angle=1.5707963267949`；`cancel_on_death=true`；`center="self"`；`damage_kind="electric"`；`duration=0.0`；`exposure_seconds=1.2`；`inner_radius=0.0`；`max_active_hazards=1`；`max_count=2`；`radius=85.0`；`range=120.0`；`ring_gap_degrees=50.0`；`shape="ring"`；`single_use=true`；`tick_interval=0.65`；`track=true` |


精英以单次爆炸序列替换：半径至少95、缺口至少50°、预警至少1.6s；没有追加余震。

## 3. 种族技能、比例效果与条件增伤

种族技能沿用现状触发边界，盾/治疗依据最终整数HP或power自然扩大；不让首领继承普通怪的半血狂怒。此处不把百分比字段乘10，也不对比例盾/治疗额外叠技能倍率。

| 种族 | 目标计算方式 | 触发/时间保持 | 禁止重复倍率 |
| --- | --- | --- | --- |
| B01 构装护盾 | R(本体新HP×0.08) | 有效攻击命中触发；1.5s盾，4s冷却 | HP已×10；不叠技能倍率 |
| B02 寄生腐蚀 | 额外腐蚀power=R(本招Q×0.55)，每跳R(power×0.08) | 1.8s；本招已是corrosion则不另叠种族腐蚀 | Q已含技能倍率，power不能再次乘技能倍率 |
| B03 缝合回复 | R(min(本体HP×0.06,本招整数Q×0.25)) | 有效命中触发，3s冷却；受重伤再×0.6并R | Q已含技能增幅；回复不再乘技能倍率 |
| B04 巨人半血狂怒 | Q=R(A×本招系数×TierSkill×EnemySkillD×1.2) | 生命≤50%，移动倍率1.18保持 | 仅乘一次1.2；表中默认未狂怒 |
| BO01 首领开场盾 | R(首领新HP×0.22) | 开场护盾，原长时限3600s保持 | 首领HP已包括难度/挑战等级；不叠技能倍率 |
| BO04 未打断战鼓狂怒 | Q=R(A×本招系数×BossSkillD×Phase×1.25) | 5s；打断成功则不获得该增伤 | 不叠普通B04半血倍率；表中默认未狂怒 |


## 4. 四首领五难度的整型技能基础输入

| 首领/所属章 | 本章固定级 | 难度/实际级 | 新生命 | 新A | 新护甲 | 新魔抗 | 开场盾（仅BO01） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BO01/B1 | 5 | D0/Lv5 | 19575 | 270 | 180 | 180 | 4307 |
| BO01/B1 | 5 | D1/Lv5 | 27405 | 324 | 210 | 210 | 6029 |
| BO01/B1 | 5 | D2/Lv5 | 39150 | 405 | 240 | 240 | 8613 |
| BO01/B1 | 5 | D3/Lv5 | 54810 | 500 | 270 | 270 | 12058 |
| BO01/B1 | 5 | D4/Lv5 | 78300 | 621 | 300 | 300 | 17226 |
| BO02/B2 | 10 | D0/Lv10 | 24494 | 262 | 120 | 150 | — |
| BO02/B2 | 10 | D1/Lv10 | 34292 | 315 | 150 | 180 | — |
| BO02/B2 | 10 | D2/Lv10 | 48989 | 394 | 180 | 210 | — |
| BO02/B2 | 10 | D3/Lv10 | 68584 | 486 | 210 | 240 | — |
| BO02/B2 | 10 | D4/Lv10 | 97978 | 604 | 240 | 270 | — |
| BO03/B3 | 15 | D0/Lv15 | 24775 | 298 | 100 | 120 | — |
| BO03/B3 | 15 | D1/Lv15 | 34685 | 357 | 130 | 150 | — |
| BO03/B3 | 15 | D2/Lv15 | 49550 | 446 | 160 | 180 | — |
| BO03/B3 | 15 | D3/Lv15 | 69371 | 550 | 190 | 210 | — |
| BO03/B3 | 15 | D4/Lv15 | 99101 | 684 | 220 | 240 | — |
| BO04/B4 | 20 | D0/Lv20 | 34517 | 352 | 220 | 180 | — |
| BO04/B4 | 20 | D1/Lv20 | 48324 | 422 | 250 | 210 | — |
| BO04/B4 | 20 | D2/Lv20 | 69034 | 527 | 280 | 240 | — |
| BO04/B4 | 20 | D3/Lv20 | 96647 | 650 | 310 | 270 | — |
| BO04/B4 | 20 | D4/Lv20 | 138067 | 809 | 340 | 300 | — |


## 5. 40个首领技能的全部有效难度/阶段整数伤害

阶段沿用生命≤70%进入P2、≤35%进入P3；切阶段预警0.9s、出生0.8s。每项仅在原序列存在的阶段与解锁难度出现：表中`—`表示该阶段/难度没有该技能。P1/P2/P3数字是单次/单枚/每跳Q，不能相加当作一轮总伤害。额外难度技能原已在三个阶段都可出现；其原预警、释放数量与路径保持。

### BO01 日曜机关巨像

| 技能ID | 名称 | 命令 | 原系数 | 解锁 | D0整数Q | D1整数Q | D2整数Q | D3整数Q | D4整数Q |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hammer_fan | 机关臂横扫 | 近战 | 1.15 | D0+ | P1:311；P2:342；P3:373 | P1:395；P2:434；P3:474 | P1:522；P2:574；P3:626 | P1:690；P2:759；P3:828 | P1:928；P2:1021；P3:1114 |
| ladle_drag | 闪电拖痕 | 地面区 | 0.75 | D0+ | P1:203；P2:223；P3:243 | P1:258；P2:283；P3:309 | P1:340；P2:374；P3:408 | P1:450；P2:495；P3:540 | P1:605；P2:666；P3:727 |
| solar_cross | 日耀十字 | 地面区 | 0.5 | D0+ | P1:135；P2:149；P3:162 | P1:172；P2:189；P3:206 | P1:227；P2:249；P3:272 | P1:300；P2:330；P3:360 | P1:404；P2:444；P3:484 |
| prism_fan | 棱晶连射 | 弹体 | 0.42 | D1+ | P1:—；P2:—；P3:— | P1:144；P2:159；P3:173 | P1:191；P2:210；P3:229 | P1:252；P2:277；P3:302 | P1:339；P2:373；P3:407 |
| solar_mines | 日耀落雷 | 地面区 | 1.15 | D2+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:522；P2:574；P3:626 | P1:690；P2:759；P3:828 | P1:928；P2:1021；P3:1114 |
| gear_dash | 齿轮突进 | 位移攻击 | 1.2 | D3+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:720；P2:792；P3:864 | P1:969；P2:1066；P3:1163 |
| eclipse_ring | 日蚀光环 | 地面区 | 1.4 | D4+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:1130；P2:1243；P3:1356 |
| slag_lane | 日耀雷道 | 地面区 | 0.7 | D0+ | P1:—；P2:208；P3:— | P1:—；P2:264；P3:— | P1:—；P2:349；P3:— | P1:—；P2:462；P3:— | P1:—；P2:622；P3:— |
| back_heat | 炉心过载 | 地面区 | 1 | D0+ | P1:—；P2:—；P3:324 | P1:—；P2:—；P3:412 | P1:—；P2:—；P3:544 | P1:—；P2:—；P3:720 | P1:—；P2:—；P3:969 |


| 技能/阶段 | 伤害类型 | 单次/持续区域每跳 | 保留预警/锁定 | 有效最低D与D4状态输入 | 原机制与时空参数 | D4绝对端点/盾/治疗 |
| --- | --- | --- | --- | --- | --- | --- |
| hammer_fan/P1 | 魔法 | 每次命中一次 | 预警0.78s；锁定0.34s | D0：无<br>D4：无 | `angle=1.85`；`range=255.0`；`recovery=1.0`；`shape="cone"`；`target_count=1`；`thematic_action="gear_arm_sweep"`；`tracks_target=true` | — |
| hammer_fan/P2 | 魔法 | 每次命中一次 | 预警0.78s；锁定0.34s | D0：无<br>D4：无 | `angle=1.85`；`range=255.0`；`recovery=1.0`；`shape="cone"`；`target_count=1`；`thematic_action="gear_arm_sweep"`；`tracks_target=true` | — |
| hammer_fan/P3 | 魔法 | 每次命中一次 | 预警0.78s；锁定0.34s | D0：无<br>D4：无 | `angle=1.85`；`range=255.0`；`recovery=1.0`；`shape="cone"`；`target_count=1`；`thematic_action="gear_arm_sweep"`；`tracks_target=true` | — |
| ladle_drag/P1 | 魔法 | 每0.65s/跳；持续1s（最多1跳/区） | 预警0.95s；锁定0.4s | D0：shock 2.4s；power=203；下次直伤追加51<br>D4：shock 2.4s；power=605；下次直伤追加151 | `duration=1.0`；`max_active_hazards=2`；`range=680.0`；`recovery=1.15`；`shape="line"`；`target_count=1`；`thematic_action="lightning_trace"`；`tick_interval=0.65`；`tracks_target=true`；`width=58.0` | — |
| ladle_drag/P2 | 魔法 | 每0.65s/跳；持续1s（最多1跳/区） | 预警0.95s；锁定0.4s | D0：shock 2.4s；power=223；下次直伤追加56<br>D4：shock 2.4s；power=666；下次直伤追加167 | `duration=1.0`；`max_active_hazards=2`；`range=680.0`；`recovery=1.15`；`shape="line"`；`target_count=1`；`thematic_action="lightning_trace"`；`tick_interval=0.65`；`tracks_target=true`；`width=58.0` | — |
| ladle_drag/P3 | 魔法 | 每0.65s/跳；持续1s（最多1跳/区） | 预警0.95s；锁定0.4s | D0：shock 2.4s；power=243；下次直伤追加61<br>D4：shock 2.4s；power=727；下次直伤追加182 | `duration=1.0`；`max_active_hazards=2`；`range=680.0`；`recovery=1.15`；`shape="line"`；`target_count=1`；`thematic_action="lightning_trace"`；`tick_interval=0.65`；`tracks_target=true`；`width=58.0` | — |
| solar_cross/P1 | 魔法 | 每0.65s/跳；持续1.45s（最多2跳/区） | 预警1.1s；锁定0.5s | D0：shock 2s；power=135；下次直伤追加34<br>D4：shock 2s；power=404；下次直伤追加101 | `cooldown=7.0`；`count=2`；`duration=1.45`；`max_active_hazards=2`；`paths_count=2`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="solar_cross"`；`tick_interval=0.65`；`tracks_target=true`；`width=54.0` | — |
| solar_cross/P2 | 魔法 | 每0.65s/跳；持续1.45s（最多2跳/区） | 预警1.1s；锁定0.5s | D0：shock 2s；power=149；下次直伤追加37<br>D4：shock 2s；power=444；下次直伤追加111 | `cooldown=7.0`；`count=2`；`duration=1.45`；`max_active_hazards=2`；`paths_count=2`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="solar_cross"`；`tick_interval=0.65`；`tracks_target=true`；`width=54.0` | — |
| solar_cross/P3 | 魔法 | 每0.65s/跳；持续1.45s（最多2跳/区） | 预警1.1s；锁定0.5s | D0：shock 2s；power=162；下次直伤追加41<br>D4：shock 2s；power=484；下次直伤追加121 | `cooldown=7.0`；`count=2`；`duration=1.45`；`max_active_hazards=2`；`paths_count=2`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="solar_cross"`；`tick_interval=0.65`；`tracks_target=true`；`width=54.0` | — |
| prism_fan/P1 | 魔法 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：shock 2s；power=144；下次直伤追加36<br>D4：shock 2s；power=339；下次直伤追加85 | `cooldown=7.0`；`count=5`；`paths_count=5`；`projectile_radius=8.0`；`recovery=1.7`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="prism_fan"`；`tracks_target=true`；`unlock_difficulty=1`；`width=18.0` | — |
| prism_fan/P2 | 魔法 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：shock 2s；power=159；下次直伤追加40<br>D4：shock 2s；power=373；下次直伤追加93 | `cooldown=7.0`；`count=5`；`paths_count=5`；`projectile_radius=8.0`；`recovery=1.7`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="prism_fan"`；`tracks_target=true`；`unlock_difficulty=1`；`width=18.0` | — |
| prism_fan/P3 | 魔法 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：shock 2s；power=173；下次直伤追加43<br>D4：shock 2s；power=407；下次直伤追加102 | `cooldown=7.0`；`count=5`；`paths_count=5`；`projectile_radius=8.0`；`recovery=1.7`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="prism_fan"`；`tracks_target=true`；`unlock_difficulty=1`；`width=18.0` | — |
| solar_mines/P1 | 魔法 | 一次区域命中 | 预警1.4s；锁定0.5s | D2：无<br>D4：无 | `cooldown=8.5`；`duration=0.0`；`radius=70.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="solar_mines"`；`tracks_target=true`；`unlock_difficulty=2` | — |
| solar_mines/P2 | 魔法 | 一次区域命中 | 预警1.4s；锁定0.5s | D2：无<br>D4：无 | `cooldown=8.5`；`duration=0.0`；`radius=70.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="solar_mines"`；`tracks_target=true`；`unlock_difficulty=2` | — |
| solar_mines/P3 | 魔法 | 一次区域命中 | 预警1.4s；锁定0.5s | D2：无<br>D4：无 | `cooldown=8.5`；`duration=0.0`；`radius=70.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="solar_mines"`；`tracks_target=true`；`unlock_difficulty=2` | — |
| gear_dash/P1 | 魔法 | 沿途每目标最多一次 | 预警1.2s；锁定0.5s | D3：无<br>D4：无 | `cooldown=9.0`；`radius=45.0`；`range=480.0`；`recovery=1.7`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="gear_dash"`；`tracks_target=true`；`travel_distance=480.0`；`unlock_difficulty=3`；`width=90.0` | — |
| gear_dash/P2 | 魔法 | 沿途每目标最多一次 | 预警1.2s；锁定0.5s | D3：无<br>D4：无 | `cooldown=9.0`；`radius=45.0`；`range=480.0`；`recovery=1.7`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="gear_dash"`；`tracks_target=true`；`travel_distance=480.0`；`unlock_difficulty=3`；`width=90.0` | — |
| gear_dash/P3 | 魔法 | 沿途每目标最多一次 | 预警1.2s；锁定0.5s | D3：无<br>D4：无 | `cooldown=9.0`；`radius=45.0`；`range=480.0`；`recovery=1.7`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="gear_dash"`；`tracks_target=true`；`travel_distance=480.0`；`unlock_difficulty=3`；`width=90.0` | — |
| eclipse_ring/P1 | 魔法 | 一次区域命中 | 预警1.5s；锁定0.5s | D4：无<br>D4：无 | `cooldown=10.0`；`duration=0.0`；`inner_radius=155.0`；`radius=410.0`；`recovery=2.0`；`ring_gap_degrees=100.0`；`shape="ring"`；`target_count=1`；`thematic_action="eclipse_ring"`；`tracks_target=true`；`unlock_difficulty=4`；`weakpoint_duration=2.0`；`weakpoint_id="eclipse_core"` | — |
| eclipse_ring/P2 | 魔法 | 一次区域命中 | 预警1.5s；锁定0.5s | D4：无<br>D4：无 | `cooldown=10.0`；`duration=0.0`；`inner_radius=155.0`；`radius=410.0`；`recovery=2.0`；`ring_gap_degrees=100.0`；`shape="ring"`；`target_count=1`；`thematic_action="eclipse_ring"`；`tracks_target=true`；`unlock_difficulty=4`；`weakpoint_duration=2.0`；`weakpoint_id="eclipse_core"` | — |
| eclipse_ring/P3 | 魔法 | 一次区域命中 | 预警1.5s；锁定0.5s | D4：无<br>D4：无 | `cooldown=10.0`；`duration=0.0`；`inner_radius=155.0`；`radius=410.0`；`recovery=2.0`；`ring_gap_degrees=100.0`；`shape="ring"`；`target_count=1`；`thematic_action="eclipse_ring"`；`tracks_target=true`；`unlock_difficulty=4`；`weakpoint_duration=2.0`；`weakpoint_id="eclipse_core"` | — |
| slag_lane/P2 | 魔法 | 每0.7s/跳；持续1.1s（最多1跳/区） | 预警1s；锁定0.4s | D0：shock 2.6s；power=208；下次直伤追加52<br>D4：shock 2.6s；power=622；下次直伤追加156 | `duration=1.1`；`lane_index=0`；`max_active_hazards=2`；`range=740.0`；`recovery=1.1`；`shape="line"`；`target_count=1`；`thematic_action="solar_lightning_lane"`；`tick_interval=0.7`；`tracks_target=true`；`width=82.0` | — |
| back_heat/P3 | 魔法 | 一次区域命中 | 预警1s；锁定0.42s | D0：无<br>D4：无 | `duration=0.0`；`inner_radius=105.0`；`radius=285.0`；`recovery=2.1`；`ring_gap_degrees=92.0`；`shape="ring"`；`target_count=1`；`thematic_action="exposed_solar_core"`；`tracks_target=true`；`weakpoint_duration=2.1`；`weakpoint_id="furnace_back"` | — |


### BO02 琥珀虫后

| 技能ID | 名称 | 命令 | 原系数 | 解锁 | D0整数Q | D1整数Q | D2整数Q | D3整数Q | D4整数Q |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| root_fork | 蚁酸分叉 | 弹体 | 0.62 | D0+ | P1:162；P2:179；P3:— | P1:207；P2:228；P3:— | P1:274；P2:301；P3:— | P1:362；P2:398；P3:— | P1:487；P2:536；P3:— |
| spore_pod | 蚁酸弹池 | 地面区 | 0.42 | D0+ | P1:110；P2:121；P3:132 | P1:140；P2:154；P3:168 | P1:185；P2:204；P3:222 | P1:245；P2:269；P3:294 | P1:330；P2:363；P3:396 |
| brood_eggs | 召唤虫卵 | 召唤 | 0 | D0+ | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 |
| root_link | 虫翼切风 | 近战 | 0.9 | D0+ | P1:236；P2:259；P3:283 | P1:301；P2:331；P3:361 | P1:397；P2:437；P3:477 | P1:525；P2:577；P3:630 | P1:707；P2:777；P3:848 |
| acid_scatter | 蚁酸散射 | 地面区 | 0.58 | D0+ | P1:152；P2:167；P3:182 | P1:194；P2:213；P3:232 | P1:256；P2:282；P3:307 | P1:338；P2:372；P3:406 | P1:455；P2:501；P3:546 |
| venom_spiral | 回旋毒针 | 弹体 | 0.42 | D1+ | P1:—；P2:—；P3:— | P1:140；P2:154；P3:168 | P1:185；P2:204；P3:222 | P1:245；P2:269；P3:294 | P1:330；P2:363；P3:396 |
| royal_dive | 虫后俯冲 | 位移攻击 | 1.12 | D2+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:494；P2:544；P3:593 | P1:653；P2:719；P3:784 | P1:879；P2:967；P3:1055 |
| amber_trap | 琥珀毒巢 | 地面区 | 0.3 | D3+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:175；P2:192；P3:210 | P1:236；P2:259；P3:283 |
| wing_storm | 振翼风暴 | 近战 | 1.35 | D4+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:1060；P2:1166；P3:1272 |
| crown_open | 虫后开甲 | 地面区 | 0.9 | D0+ | P1:—；P2:—；P3:283 | P1:—；P2:—；P3:361 | P1:—；P2:—；P3:477 | P1:—；P2:—；P3:630 | P1:—；P2:—；P3:848 |


| 技能/阶段 | 伤害类型 | 单次/持续区域每跳 | 保留预警/锁定 | 有效最低D与D4状态输入 | 原机制与时空参数 | D4绝对端点/盾/治疗 |
| --- | --- | --- | --- | --- | --- | --- |
| root_fork/P1 | 魔法 | 每枚弹体命中一次 | 预警0.9s；锁定0.38s | D0：corrosion 2.8s；power=162；每1s原伤害13<br>D4：corrosion 2.8s；power=487；每1s原伤害39 | `count=3`；`paths_count=3`；`projectile_radius=10.0`；`recovery=1.0`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="acid_fork"`；`tracks_target=true`；`width=24.0` | — |
| root_fork/P2 | 魔法 | 每枚弹体命中一次 | 预警0.9s；锁定0.38s | D0：corrosion 2.8s；power=179；每1s原伤害14<br>D4：corrosion 2.8s；power=536；每1s原伤害43 | `count=3`；`paths_count=3`；`projectile_radius=10.0`；`recovery=1.0`；`shape="line"`；`speed=390.0`；`target_count=1`；`thematic_action="acid_fork"`；`tracks_target=true`；`width=24.0` | — |
| spore_pod/P1 | 魔法 | 落点一次+每0.65s/跳；持续3.3s（最多6次/区） | 预警0.88s；锁定0.4s | D0：corrosion 3s；power=110；每1s原伤害9<br>D4：corrosion 3s；power=330；每1s原伤害26 | `duration=3.3`；`lob=true`；`max_active_hazards=2`；`radius=105.0`；`recovery=1.15`；`shape="circle"`；`target_count=1`；`targets_count=1`；`thematic_action="acid_pool"`；`tick_interval=0.65`；`tracks_target=true` | — |
| spore_pod/P2 | 魔法 | 落点一次+每0.65s/跳；持续3.3s（最多6次/区） | 预警0.88s；锁定0.4s | D0：corrosion 3s；power=121；每1s原伤害10<br>D4：corrosion 3s；power=363；每1s原伤害29 | `duration=3.3`；`lob=true`；`max_active_hazards=2`；`radius=105.0`；`recovery=1.15`；`shape="circle"`；`target_count=1`；`targets_count=1`；`thematic_action="acid_pool"`；`tick_interval=0.65`；`tracks_target=true` | — |
| spore_pod/P3 | 魔法 | 落点一次+每0.65s/跳；持续3.3s（最多6次/区） | 预警0.88s；锁定0.4s | D0：corrosion 3s；power=132；每1s原伤害11<br>D4：corrosion 3s；power=396；每1s原伤害32 | `duration=3.3`；`lob=true`；`max_active_hazards=2`；`radius=105.0`；`recovery=1.15`；`shape="circle"`；`target_count=1`；`targets_count=1`；`thematic_action="acid_pool"`；`tick_interval=0.65`；`tracks_target=true` | — |
| brood_eggs/P1 | 魔法 | 无直接伤害 | 预警1s；锁定0.35s | D0：无<br>D4：无 | `count=2`；`hatch_delay=2.2`；`max_alive=2`；`pod_break_armor_loss=2.0`；`pod_health=40.0`；`radius=46.0`；`recovery=2.6`；`shape="circle"`；`summon_enemy_id="M14"`；`target_count=1`；`targets_count=2`；`thematic_action="brood_eggs"`；`tracks_target=true` | pod_health=520；pod_break_armor_loss=20 |
| brood_eggs/P2 | 魔法 | 无直接伤害 | 预警1s；锁定0.35s | D0：无<br>D4：无 | `count=2`；`hatch_delay=2.2`；`max_alive=2`；`pod_break_armor_loss=2.0`；`pod_health=40.0`；`radius=46.0`；`recovery=2.6`；`shape="circle"`；`summon_enemy_id="M14"`；`target_count=1`；`targets_count=2`；`thematic_action="brood_eggs"`；`tracks_target=true` | pod_health=572；pod_break_armor_loss=20 |
| brood_eggs/P3 | 魔法 | 无直接伤害 | 预警1s；锁定0.35s | D0：无<br>D4：无 | `count=2`；`hatch_delay=2.2`；`max_alive=2`；`pod_break_armor_loss=2.0`；`pod_health=40.0`；`radius=46.0`；`recovery=2.6`；`shape="circle"`；`summon_enemy_id="M14"`；`target_count=1`；`targets_count=2`；`thematic_action="brood_eggs"`；`tracks_target=true` | pod_health=624；pod_break_armor_loss=20 |
| root_link/P1 | 魔法 | 每次命中一次 | 预警1s；锁定0.4s | D0：slow 0.9s；系数0.78<br>D4：slow 0.9s；系数0.78 | `angle=1.6`；`range=350.0`；`recovery=1.25`；`shape="cone"`；`target_count=1`；`thematic_action="wing_cone"`；`tracks_target=true` | — |
| root_link/P2 | 魔法 | 每次命中一次 | 预警1s；锁定0.4s | D0：slow 0.9s；系数0.78<br>D4：slow 0.9s；系数0.78 | `angle=1.6`；`range=350.0`；`recovery=1.25`；`shape="cone"`；`target_count=1`；`thematic_action="wing_cone"`；`tracks_target=true` | — |
| root_link/P3 | 魔法 | 每次命中一次 | 预警1s；锁定0.4s | D0：slow 0.9s；系数0.78<br>D4：slow 0.9s；系数0.78 | `angle=1.6`；`range=350.0`；`recovery=1.25`；`shape="cone"`；`target_count=1`；`thematic_action="wing_cone"`；`tracks_target=true` | — |
| acid_scatter/P1 | 魔法 | 落点一次+每0.7s/跳；持续2.5s（最多4次/区） | 预警1.1s；锁定0.5s | D0：corrosion 2.6s；power=152；每1s原伤害12<br>D4：corrosion 2.6s；power=455；每1s原伤害36 | `cooldown=6.0`；`duration=2.5`；`lob=true`；`max_active_hazards=2`；`radius=82.0`；`recovery=1.6`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="acid_scatter"`；`tick_interval=0.7`；`tracks_target=true` | — |
| acid_scatter/P2 | 魔法 | 落点一次+每0.7s/跳；持续2.5s（最多4次/区） | 预警1.1s；锁定0.5s | D0：corrosion 2.6s；power=167；每1s原伤害13<br>D4：corrosion 2.6s；power=501；每1s原伤害40 | `cooldown=6.0`；`duration=2.5`；`lob=true`；`max_active_hazards=2`；`radius=82.0`；`recovery=1.6`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="acid_scatter"`；`tick_interval=0.7`；`tracks_target=true` | — |
| acid_scatter/P3 | 魔法 | 落点一次+每0.7s/跳；持续2.5s（最多4次/区） | 预警1.1s；锁定0.5s | D0：corrosion 2.6s；power=182；每1s原伤害15<br>D4：corrosion 2.6s；power=546；每1s原伤害44 | `cooldown=6.0`；`duration=2.5`；`lob=true`；`max_active_hazards=2`；`radius=82.0`；`recovery=1.6`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="acid_scatter"`；`tick_interval=0.7`；`tracks_target=true` | — |
| venom_spiral/P1 | 魔法 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：corrosion 2.4s；power=140；每1s原伤害11<br>D4：corrosion 2.4s；power=330；每1s原伤害26 | `cooldown=7.0`；`count=4`；`paths_count=4`；`projectile_radius=8.0`；`recovery=1.7`；`shape="line"`；`speed=310.0`；`target_count=1`；`thematic_action="venom_spiral"`；`tracks_target=true`；`unlock_difficulty=1`；`width=18.0` | — |
| venom_spiral/P2 | 魔法 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：corrosion 2.4s；power=154；每1s原伤害12<br>D4：corrosion 2.4s；power=363；每1s原伤害29 | `cooldown=7.0`；`count=4`；`paths_count=4`；`projectile_radius=8.0`；`recovery=1.7`；`shape="line"`；`speed=310.0`；`target_count=1`；`thematic_action="venom_spiral"`；`tracks_target=true`；`unlock_difficulty=1`；`width=18.0` | — |
| venom_spiral/P3 | 魔法 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：corrosion 2.4s；power=168；每1s原伤害13<br>D4：corrosion 2.4s；power=396；每1s原伤害32 | `cooldown=7.0`；`count=4`；`paths_count=4`；`projectile_radius=8.0`；`recovery=1.7`；`shape="line"`；`speed=310.0`；`target_count=1`；`thematic_action="venom_spiral"`；`tracks_target=true`；`unlock_difficulty=1`；`width=18.0` | — |
| royal_dive/P1 | 魔法 | 仅完成落地命中一次 | 预警1.2s；锁定0.5s | D2：corrosion 2s；power=494；每1s原伤害40<br>D4：corrosion 2s；power=879；每1s原伤害70 | `cooldown=8.0`；`damage_along_path=false`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=96.0`；`range=480.0`；`recovery=1.7`；`shape="line"`；`speed=450.0`；`target_count=1`；`thematic_action="royal_dive"`；`tracks_target=true`；`travel_distance=480.0`；`unlock_difficulty=2`；`width=28.0` | — |
| royal_dive/P2 | 魔法 | 仅完成落地命中一次 | 预警1.2s；锁定0.5s | D2：corrosion 2s；power=544；每1s原伤害44<br>D4：corrosion 2s；power=967；每1s原伤害77 | `cooldown=8.0`；`damage_along_path=false`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=96.0`；`range=480.0`；`recovery=1.7`；`shape="line"`；`speed=450.0`；`target_count=1`；`thematic_action="royal_dive"`；`tracks_target=true`；`travel_distance=480.0`；`unlock_difficulty=2`；`width=28.0` | — |
| royal_dive/P3 | 魔法 | 仅完成落地命中一次 | 预警1.2s；锁定0.5s | D2：corrosion 2s；power=593；每1s原伤害47<br>D4：corrosion 2s；power=1055；每1s原伤害84 | `cooldown=8.0`；`damage_along_path=false`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=96.0`；`range=480.0`；`recovery=1.7`；`shape="line"`；`speed=450.0`；`target_count=1`；`thematic_action="royal_dive"`；`tracks_target=true`；`travel_distance=480.0`；`unlock_difficulty=2`；`width=28.0` | — |
| amber_trap/P1 | 魔法 | 落点一次+每0.9s/跳；持续3s（最多4次/区） | 预警1.2s；锁定0.5s | D3：slow 0.8s；系数0.7<br>D4：slow 0.8s；系数0.7 | `cooldown=9.0`；`duration=3.0`；`lob=true`；`max_active_hazards=2`；`radius=66.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="amber_trap"`；`tick_interval=0.9`；`tracks_target=true`；`unlock_difficulty=3` | — |
| amber_trap/P2 | 魔法 | 落点一次+每0.9s/跳；持续3s（最多4次/区） | 预警1.2s；锁定0.5s | D3：slow 0.8s；系数0.7<br>D4：slow 0.8s；系数0.7 | `cooldown=9.0`；`duration=3.0`；`lob=true`；`max_active_hazards=2`；`radius=66.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="amber_trap"`；`tick_interval=0.9`；`tracks_target=true`；`unlock_difficulty=3` | — |
| amber_trap/P3 | 魔法 | 落点一次+每0.9s/跳；持续3s（最多4次/区） | 预警1.2s；锁定0.5s | D3：slow 0.8s；系数0.7<br>D4：slow 0.8s；系数0.7 | `cooldown=9.0`；`duration=3.0`；`lob=true`；`max_active_hazards=2`；`radius=66.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="amber_trap"`；`tick_interval=0.9`；`tracks_target=true`；`unlock_difficulty=3` | — |
| wing_storm/P1 | 魔法 | 每次命中一次 | 预警1.45s；锁定0.5s | D4：slow 1.3s；系数0.65<br>D4：slow 1.3s；系数0.65 | `angle=2.3`；`cooldown=10.0`；`range=440.0`；`recovery=1.7`；`shape="cone"`；`target_count=1`；`thematic_action="wing_storm"`；`tracks_target=true`；`unlock_difficulty=4` | — |
| wing_storm/P2 | 魔法 | 每次命中一次 | 预警1.45s；锁定0.5s | D4：slow 1.3s；系数0.65<br>D4：slow 1.3s；系数0.65 | `angle=2.3`；`cooldown=10.0`；`range=440.0`；`recovery=1.7`；`shape="cone"`；`target_count=1`；`thematic_action="wing_storm"`；`tracks_target=true`；`unlock_difficulty=4` | — |
| wing_storm/P3 | 魔法 | 每次命中一次 | 预警1.45s；锁定0.5s | D4：slow 1.3s；系数0.65<br>D4：slow 1.3s；系数0.65 | `angle=2.3`；`cooldown=10.0`；`range=440.0`；`recovery=1.7`；`shape="cone"`；`target_count=1`；`thematic_action="wing_storm"`；`tracks_target=true`；`unlock_difficulty=4` | — |
| crown_open/P3 | 魔法 | 一次区域命中 | 预警0.95s；锁定0.42s | D0：无<br>D4：无 | `duration=0.0`；`inner_radius=110.0`；`radius=260.0`；`recovery=2.35`；`ring_gap_degrees=78.0`；`shape="ring"`；`target_count=1`；`thematic_action="amber_carapace_open"`；`tracks_target=true`；`weakpoint_duration=2.35`；`weakpoint_id="open_crown"` | — |


### BO03 缝合镇长

| 技能ID | 名称 | 命令 | 原系数 | 解锁 | D0整数Q | D1整数Q | D2整数Q | D3整数Q | D4整数Q |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| glide | 缝线牵引 | 牵引攻击 | 0.6 | D0+ | P1:179；P2:197；P3:— | P1:227；P2:250；P3:— | P1:300；P2:330；P3:— | P1:396；P2:436；P3:— | P1:534；P2:587；P3:— |
| capacitor_burst | 糖桶投掷 | 弹体 | 0.95 | D0+ | P1:283；P2:311；P3:340 | P1:359；P2:395；P3:431 | P1:475；P2:522；P3:569 | P1:627；P2:690；P3:752 | P1:845；P2:929；P3:1014 |
| grave_recall | 墓穴召回 | 召唤 | 0 | D0+ | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 |
| stitch_cage | 缝线牢笼 | 弹体 | 0.45 | D0+ | P1:134；P2:148；P3:161 | P1:170；P2:187；P3:204 | P1:225；P2:247；P3:270 | P1:297；P2:327；P3:356 | P1:400；P2:440；P3:480 |
| needle_fan | 缝针散射 | 弹体 | 0.4 | D1+ | P1:—；P2:—；P3:— | P1:151；P2:167；P3:182 | P1:200；P2:220；P3:240 | P1:264；P2:290；P3:317 | P1:356；P2:391；P3:427 |
| grave_burst | 墓火三连 | 地面区 | 1 | D2+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:500；P2:549；P3:599 | P1:660；P2:726；P3:792 | P1:889；P2:978；P3:1067 |
| funeral_hook | 送葬钩索 | 牵引攻击 | 0.85 | D3+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:561；P2:617；P3:673 | P1:756；P2:831；P3:907 |
| seam_lock | 缝线封锁 | 地面区 | 1.2 | D4+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:1067；P2:1174；P3:1280 |
| runway_pair | 双缝针道 | 弹体 | 0.66 | D0+ | P1:—；P2:216；P3:236 | P1:—；P2:275；P3:300 | P1:—；P2:363；P3:396 | P1:—；P2:479；P3:523 | P1:—；P2:646；P3:704 |
| sweep_land | 镇长扑击 | 位移攻击 | 0.92 | D0+ | P1:—；P2:—；P3:329 | P1:—；P2:—；P3:418 | P1:—；P2:—；P3:551 | P1:—；P2:—；P3:729 | P1:—；P2:—；P3:982 |


| 技能/阶段 | 伤害类型 | 单次/持续区域每跳 | 保留预警/锁定 | 有效最低D与D4状态输入 | 原机制与时空参数 | D4绝对端点/盾/治疗 |
| --- | --- | --- | --- | --- | --- | --- |
| glide/P1 | 物理 | 每次命中一次 | 预警1s；锁定0.42s | D0：无<br>D4：无 | `pull_distance=85.0`；`range=500.0`；`recovery=1.2`；`shape="line"`；`target_count=1`；`thematic_action="stitch_pull"`；`tracks_target=true`；`width=62.0` | — |
| glide/P2 | 物理 | 每次命中一次 | 预警1s；锁定0.42s | D0：无<br>D4：无 | `pull_distance=85.0`；`range=500.0`；`recovery=1.2`；`shape="line"`；`target_count=1`；`thematic_action="stitch_pull"`；`tracks_target=true`；`width=62.0` | — |
| capacitor_burst/P1 | 物理 | 每枚弹体命中一次 | 预警1s；锁定0.4s | D0：无<br>D4：无 | `count=1`；`projectile_radius=19.0`；`range=800.0`；`recovery=1.2`；`shape="line"`；`speed=420.0`；`target_count=1`；`thematic_action="barrel_throw"`；`tracks_target=true`；`width=38.0` | — |
| capacitor_burst/P2 | 物理 | 每枚弹体命中一次 | 预警1s；锁定0.4s | D0：无<br>D4：无 | `count=1`；`projectile_radius=19.0`；`range=800.0`；`recovery=1.2`；`shape="line"`；`speed=420.0`；`target_count=1`；`thematic_action="barrel_throw"`；`tracks_target=true`；`width=38.0` | — |
| capacitor_burst/P3 | 物理 | 每枚弹体命中一次 | 预警1s；锁定0.4s | D0：无<br>D4：无 | `count=1`；`projectile_radius=19.0`；`range=800.0`；`recovery=1.2`；`shape="line"`；`speed=420.0`；`target_count=1`；`thematic_action="barrel_throw"`；`tracks_target=true`；`width=38.0` | — |
| grave_recall/P1 | 物理 | 无直接伤害 | 预警1.25s；锁定0.4s | D0：无<br>D4：无 | `count=1`；`radius=65.0`；`recovery=1.35`；`shape="circle"`；`summon_enemy_id="M27"`；`target_count=1`；`thematic_action="grave_recall"`；`tracks_target=true` | — |
| grave_recall/P2 | 物理 | 无直接伤害 | 预警1.25s；锁定0.4s | D0：无<br>D4：无 | `count=1`；`radius=65.0`；`recovery=1.35`；`shape="circle"`；`summon_enemy_id="M27"`；`target_count=1`；`thematic_action="grave_recall"`；`tracks_target=true` | — |
| grave_recall/P3 | 物理 | 无直接伤害 | 预警1.25s；锁定0.4s | D0：无<br>D4：无 | `count=1`；`radius=65.0`；`recovery=1.35`；`shape="circle"`；`summon_enemy_id="M27"`；`target_count=1`；`thematic_action="grave_recall"`；`tracks_target=true` | — |
| stitch_cage/P1 | 物理 | 每枚弹体命中一次 | 预警1.15s；锁定0.5s | D0：slow 1s；系数0.78<br>D4：slow 1s；系数0.78 | `cooldown=6.5`；`count=3`；`paths_count=3`；`projectile_radius=8.0`；`recovery=1.5`；`shape="line"`；`speed=350.0`；`target_count=1`；`thematic_action="stitch_cage"`；`tracks_target=true`；`width=20.0` | — |
| stitch_cage/P2 | 物理 | 每枚弹体命中一次 | 预警1.15s；锁定0.5s | D0：slow 1s；系数0.78<br>D4：slow 1s；系数0.78 | `cooldown=6.5`；`count=3`；`paths_count=3`；`projectile_radius=8.0`；`recovery=1.5`；`shape="line"`；`speed=350.0`；`target_count=1`；`thematic_action="stitch_cage"`；`tracks_target=true`；`width=20.0` | — |
| stitch_cage/P3 | 物理 | 每枚弹体命中一次 | 预警1.15s；锁定0.5s | D0：slow 1s；系数0.78<br>D4：slow 1s；系数0.78 | `cooldown=6.5`；`count=3`；`paths_count=3`；`projectile_radius=8.0`；`recovery=1.5`；`shape="line"`；`speed=350.0`；`target_count=1`；`thematic_action="stitch_cage"`；`tracks_target=true`；`width=20.0` | — |
| needle_fan/P1 | 物理 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：bleed 2.5s；power=151；每1s原伤害15<br>D4：bleed 2.5s；power=356；每1s原伤害36 | `cooldown=7.0`；`count=4`；`paths_count=4`；`projectile_radius=7.0`；`recovery=1.7`；`shape="line"`；`speed=460.0`；`target_count=1`；`thematic_action="needle_fan"`；`tracks_target=true`；`unlock_difficulty=1`；`width=16.0` | — |
| needle_fan/P2 | 物理 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：bleed 2.5s；power=167；每1s原伤害17<br>D4：bleed 2.5s；power=391；每1s原伤害39 | `cooldown=7.0`；`count=4`；`paths_count=4`；`projectile_radius=7.0`；`recovery=1.7`；`shape="line"`；`speed=460.0`；`target_count=1`；`thematic_action="needle_fan"`；`tracks_target=true`；`unlock_difficulty=1`；`width=16.0` | — |
| needle_fan/P3 | 物理 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D1：bleed 2.5s；power=182；每1s原伤害18<br>D4：bleed 2.5s；power=427；每1s原伤害43 | `cooldown=7.0`；`count=4`；`paths_count=4`；`projectile_radius=7.0`；`recovery=1.7`；`shape="line"`；`speed=460.0`；`target_count=1`；`thematic_action="needle_fan"`；`tracks_target=true`；`unlock_difficulty=1`；`width=16.0` | — |
| grave_burst/P1 | 物理 | 一次区域命中 | 预警1.35s；锁定0.5s | D2：burn 2s；power=500；每1s原伤害60<br>D4：burn 2s；power=889；每1s原伤害107 | `cooldown=7.0`；`duration=0.0`；`radius=76.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="grave_burst"`；`tracks_target=true`；`unlock_difficulty=2` | — |
| grave_burst/P2 | 物理 | 一次区域命中 | 预警1.35s；锁定0.5s | D2：burn 2s；power=549；每1s原伤害66<br>D4：burn 2s；power=978；每1s原伤害117 | `cooldown=7.0`；`duration=0.0`；`radius=76.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="grave_burst"`；`tracks_target=true`；`unlock_difficulty=2` | — |
| grave_burst/P3 | 物理 | 一次区域命中 | 预警1.35s；锁定0.5s | D2：burn 2s；power=599；每1s原伤害72<br>D4：burn 2s；power=1067；每1s原伤害128 | `cooldown=7.0`；`duration=0.0`；`radius=76.0`；`recovery=1.7`；`shape="circle"`；`target_count=1`；`targets_count=3`；`thematic_action="grave_burst"`；`tracks_target=true`；`unlock_difficulty=2` | — |
| funeral_hook/P1 | 物理 | 每次命中一次 | 预警1.4s；锁定0.5s | D3：grievous 3s<br>D4：grievous 3s | `cooldown=9.0`；`pull_distance=140.0`；`range=700.0`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="funeral_hook"`；`tracks_target=true`；`unlock_difficulty=3`；`width=80.0` | — |
| funeral_hook/P2 | 物理 | 每次命中一次 | 预警1.4s；锁定0.5s | D3：grievous 3s<br>D4：grievous 3s | `cooldown=9.0`；`pull_distance=140.0`；`range=700.0`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="funeral_hook"`；`tracks_target=true`；`unlock_difficulty=3`；`width=80.0` | — |
| funeral_hook/P3 | 物理 | 每次命中一次 | 预警1.4s；锁定0.5s | D3：grievous 3s<br>D4：grievous 3s | `cooldown=9.0`；`pull_distance=140.0`；`range=700.0`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="funeral_hook"`；`tracks_target=true`；`unlock_difficulty=3`；`width=80.0` | — |
| seam_lock/P1 | 物理 | 一次区域命中 | 预警1.5s；锁定0.5s | D4：slow 1.5s；系数0.7<br>D4：slow 1.5s；系数0.7 | `cooldown=10.0`；`duration=0.0`；`paths_count=3`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="seam_lock"`；`tracks_target=true`；`unlock_difficulty=4`；`width=42.0` | — |
| seam_lock/P2 | 物理 | 一次区域命中 | 预警1.5s；锁定0.5s | D4：slow 1.5s；系数0.7<br>D4：slow 1.5s；系数0.7 | `cooldown=10.0`；`duration=0.0`；`paths_count=3`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="seam_lock"`；`tracks_target=true`；`unlock_difficulty=4`；`width=42.0` | — |
| seam_lock/P3 | 物理 | 一次区域命中 | 预警1.5s；锁定0.5s | D4：slow 1.5s；系数0.7<br>D4：slow 1.5s；系数0.7 | `cooldown=10.0`；`duration=0.0`；`paths_count=3`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="seam_lock"`；`tracks_target=true`；`unlock_difficulty=4`；`width=42.0` | — |
| runway_pair/P2 | 物理 | 每枚弹体命中一次 | 预警1.05s；锁定0.42s | D0：slow 1s；系数0.82<br>D4：slow 1s；系数0.82 | `count=2`；`lane_indices=[0,1]`；`paths_count=2`；`projectile_radius=12.0`；`recovery=1.25`；`shape="line"`；`speed=420.0`；`target_count=1`；`thematic_action="stitch_lanes"`；`tracks_target=true`；`width=30.0` | — |
| runway_pair/P3 | 物理 | 每枚弹体命中一次 | 预警1.05s；锁定0.42s | D0：slow 1s；系数0.82<br>D4：slow 1s；系数0.82 | `count=2`；`lane_indices=[0,1]`；`paths_count=2`；`projectile_radius=12.0`；`recovery=1.25`；`shape="line"`；`speed=420.0`；`target_count=1`；`thematic_action="stitch_lanes"`；`tracks_target=true`；`width=30.0` | — |
| sweep_land/P3 | 物理 | 沿途一次+完成落地一次；每包均为Q，实收受无敌限制 | 预警1s；锁定0.45s | D0：无<br>D4：无 | `arc_height=0.0`；`damage_along_path=true`；`landing_only=false`；`landing_shape="circle"`；`path_mode="leap"`；`radius=72.0`；`range=620.0`；`recovery=3.3`；`shape="line"`；`speed=600.0`；`target_count=1`；`thematic_action="mayor_body_slam"`；`tracks_target=true`；`travel_distance=620.0`；`weakpoint_delay=1.05`；`weakpoint_duration=2.2`；`weakpoint_id="landed_core"`；`width=144.0` | — |


### BO04 裂岩大酋长

| 技能ID | 名称 | 命令 | 原系数 | 解锁 | D0整数Q | D1整数Q | D2整数Q | D3整数Q | D4整数Q |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| resonance_ring | 震地重击 | 地面区 | 0.88 | D0+ | P1:310；P2:341；P3:— | P1:394；P2:433；P3:— | P1:519；P2:571；P3:— | P1:686；P2:755；P3:— | P1:925；P2:1018；P3:— |
| sound_blade | 酋长冲锋 | 位移攻击 | 1.05 | D0+ | P1:370；P2:407；P3:444 | P1:470；P2:517；P3:564 | P1:620；P2:682；P3:744 | P1:819；P2:901；P3:983 | P1:1104；P2:1215；P3:1325 |
| war_drum_rage | 战鼓狂怒 | 加速 | 0 | D0+ | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 | P1:0；P2:0；P3:0 |
| crag_leap | 崩岩跳斩 | 位移攻击 | 1.22 | D0+ | P1:429；P2:472；P3:515 | P1:546；P2:600；P3:655 | P1:720；P2:792；P3:864 | P1:952；P2:1047；P3:1142 | P1:1283；P2:1411；P3:1540 |
| axe_fan | 裂甲斧扫 | 近战 | 1.15 | D1+ | P1:—；P2:—；P3:— | P1:514；P2:566；P3:617 | P1:679；P2:747；P3:815 | P1:897；P2:987；P3:1076 | P1:1209；P2:1330；P3:1451 |
| fault_lines | 双脊断层 | 地面区 | 1.2 | D2+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:708；P2:779；P3:850 | P1:936；P2:1030；P3:1123 | P1:1262；P2:1388；P3:1514 |
| boulder_volley | 飞岩齐射 | 弹体 | 0.78 | D3+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:608；P2:669；P3:730 | P1:820；P2:902；P3:984 |
| seismic_crown | 震地王冠 | 地面区 | 1.5 | D4+ | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:—；P2:—；P3:— | P1:1578；P2:1735；P3:1893 |
| replay_path | 岩缝追击 | 弹体 | 0.62 | D0+ | P1:—；P2:240；P3:262 | P1:—；P2:305；P3:333 | P1:—；P2:403；P3:439 | P1:—；P2:532；P3:580 | P1:—；P2:717；P3:782 |
| alternating_ring | 外圈震击 | 地面区 | 0.88 | D0+ | P1:—；P2:—；P3:372 | P1:—；P2:—；P3:472 | P1:—；P2:—；P3:623 | P1:—；P2:—；P3:824 | P1:—；P2:—；P3:1111 |
| heart_crack | 裂地喘息 | 地面区 | 0.88 | D0+ | P1:—；P2:—；P3:372 | P1:—；P2:—；P3:472 | P1:—；P2:—；P3:623 | P1:—；P2:—；P3:824 | P1:—；P2:—；P3:1111 |


| 技能/阶段 | 伤害类型 | 单次/持续区域每跳 | 保留预警/锁定 | 有效最低D与D4状态输入 | 原机制与时空参数 | D4绝对端点/盾/治疗 |
| --- | --- | --- | --- | --- | --- | --- |
| resonance_ring/P1 | 物理 | 一次区域命中 | 预警0.95s；锁定0.42s | D0：无<br>D4：无 | `duration=0.0`；`inner_radius=135.0`；`radius=310.0`；`recovery=1.1`；`ring_gap_degrees=82.0`；`shape="ring"`；`target_count=1`；`thematic_action="ground_slam"`；`tracks_target=true` | — |
| resonance_ring/P2 | 物理 | 一次区域命中 | 预警0.95s；锁定0.42s | D0：无<br>D4：无 | `duration=0.0`；`inner_radius=135.0`；`radius=310.0`；`recovery=1.1`；`ring_gap_degrees=82.0`；`shape="ring"`；`target_count=1`；`thematic_action="ground_slam"`；`tracks_target=true` | — |
| sound_blade/P1 | 物理 | 沿途每目标最多一次 | 预警1.1s；锁定0.45s | D0：无<br>D4：无 | `charge_past_target=true`；`radius=62.0`；`range=600.0`；`recovery=1.6`；`shape="line"`；`speed=430.0`；`target_count=1`；`thematic_action="warchief_charge"`；`tracks_target=true`；`travel_distance=600.0`；`width=124.0` | — |
| sound_blade/P2 | 物理 | 沿途每目标最多一次 | 预警1.1s；锁定0.45s | D0：无<br>D4：无 | `charge_past_target=true`；`radius=62.0`；`range=600.0`；`recovery=1.6`；`shape="line"`；`speed=430.0`；`target_count=1`；`thematic_action="warchief_charge"`；`tracks_target=true`；`travel_distance=600.0`；`width=124.0` | — |
| sound_blade/P3 | 物理 | 沿途每目标最多一次 | 预警1.1s；锁定0.45s | D0：无<br>D4：无 | `charge_past_target=true`；`radius=62.0`；`range=600.0`；`recovery=1.6`；`shape="line"`；`speed=430.0`；`target_count=1`；`thematic_action="warchief_charge"`；`tracks_target=true`；`travel_distance=600.0`；`width=124.0` | — |
| war_drum_rage/P1 | 物理 | 无直接伤害 | 预警1.2s；锁定0.4s | D0：无<br>D4：无 | `duration=5.0`；`max_targets=3`；`multiplier=1.18`；`radius=280.0`；`recovery=1.2`；`shape="circle"`；`target_count=1`；`thematic_action="war_drum_rage"`；`tracks_target=true` | — |
| war_drum_rage/P2 | 物理 | 无直接伤害 | 预警1.2s；锁定0.4s | D0：无<br>D4：无 | `duration=5.0`；`max_targets=3`；`multiplier=1.18`；`radius=280.0`；`recovery=1.2`；`shape="circle"`；`target_count=1`；`thematic_action="war_drum_rage"`；`tracks_target=true` | — |
| war_drum_rage/P3 | 物理 | 无直接伤害 | 预警1.2s；锁定0.4s | D0：无<br>D4：无 | `duration=5.0`；`max_targets=3`；`multiplier=1.18`；`radius=280.0`；`recovery=1.2`；`shape="circle"`；`target_count=1`；`thematic_action="war_drum_rage"`；`tracks_target=true` | — |
| crag_leap/P1 | 物理 | 仅完成落地命中一次 | 预警1.15s；锁定0.55s | D0：无<br>D4：无 | `arc_height=0.0`；`cooldown=7.0`；`damage_along_path=false`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=110.0`；`range=500.0`；`recovery=2.6`；`shape="line"`；`speed=520.0`；`target_count=1`；`thematic_action="crag_leap"`；`tracks_target=true`；`travel_distance=500.0`；`weakpoint_delay=0.97`；`weakpoint_duration=1.45`；`weakpoint_id="landed_warchief"`；`width=34.0` | — |
| crag_leap/P2 | 物理 | 仅完成落地命中一次 | 预警1.15s；锁定0.55s | D0：无<br>D4：无 | `arc_height=0.0`；`cooldown=7.0`；`damage_along_path=false`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=110.0`；`range=500.0`；`recovery=2.6`；`shape="line"`；`speed=520.0`；`target_count=1`；`thematic_action="crag_leap"`；`tracks_target=true`；`travel_distance=500.0`；`weakpoint_delay=0.97`；`weakpoint_duration=1.45`；`weakpoint_id="landed_warchief"`；`width=34.0` | — |
| crag_leap/P3 | 物理 | 仅完成落地命中一次 | 预警1.15s；锁定0.55s | D0：无<br>D4：无 | `arc_height=0.0`；`cooldown=7.0`；`damage_along_path=false`；`landing_only=true`；`landing_shape="circle"`；`path_mode="leap"`；`radius=110.0`；`range=500.0`；`recovery=2.6`；`shape="line"`；`speed=520.0`；`target_count=1`；`thematic_action="crag_leap"`；`tracks_target=true`；`travel_distance=500.0`；`weakpoint_delay=0.97`；`weakpoint_duration=1.45`；`weakpoint_id="landed_warchief"`；`width=34.0` | — |
| axe_fan/P1 | 物理 | 每次命中一次 | 预警1.2s；锁定0.5s | D1：bleed 2s；power=514；每1s原伤害51<br>D4：bleed 2s；power=1209；每1s原伤害121 | `angle=2.15`；`cooldown=7.0`；`range=285.0`；`recovery=1.7`；`shape="cone"`；`target_count=1`；`thematic_action="axe_fan"`；`tracks_target=true`；`unlock_difficulty=1` | — |
| axe_fan/P2 | 物理 | 每次命中一次 | 预警1.2s；锁定0.5s | D1：bleed 2s；power=566；每1s原伤害57<br>D4：bleed 2s；power=1330；每1s原伤害133 | `angle=2.15`；`cooldown=7.0`；`range=285.0`；`recovery=1.7`；`shape="cone"`；`target_count=1`；`thematic_action="axe_fan"`；`tracks_target=true`；`unlock_difficulty=1` | — |
| axe_fan/P3 | 物理 | 每次命中一次 | 预警1.2s；锁定0.5s | D1：bleed 2s；power=617；每1s原伤害62<br>D4：bleed 2s；power=1451；每1s原伤害145 | `angle=2.15`；`cooldown=7.0`；`range=285.0`；`recovery=1.7`；`shape="cone"`；`target_count=1`；`thematic_action="axe_fan"`；`tracks_target=true`；`unlock_difficulty=1` | — |
| fault_lines/P1 | 物理 | 一次区域命中 | 预警1.4s；锁定0.5s | D2：无<br>D4：无 | `cooldown=8.0`；`duration=0.0`；`paths_count=2`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="fault_lines"`；`tracks_target=true`；`unlock_difficulty=2`；`width=64.0` | — |
| fault_lines/P2 | 物理 | 一次区域命中 | 预警1.4s；锁定0.5s | D2：无<br>D4：无 | `cooldown=8.0`；`duration=0.0`；`paths_count=2`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="fault_lines"`；`tracks_target=true`；`unlock_difficulty=2`；`width=64.0` | — |
| fault_lines/P3 | 物理 | 一次区域命中 | 预警1.4s；锁定0.5s | D2：无<br>D4：无 | `cooldown=8.0`；`duration=0.0`；`paths_count=2`；`recovery=1.7`；`shape="line"`；`target_count=1`；`thematic_action="fault_lines"`；`tracks_target=true`；`unlock_difficulty=2`；`width=64.0` | — |
| boulder_volley/P1 | 物理 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D3：slow 0.9s；系数0.8<br>D4：slow 0.9s；系数0.8 | `cooldown=9.0`；`count=3`；`paths_count=3`；`projectile_radius=14.0`；`recovery=1.7`；`shape="line"`；`speed=330.0`；`target_count=1`；`thematic_action="boulder_volley"`；`tracks_target=true`；`unlock_difficulty=3`；`width=28.0` | — |
| boulder_volley/P2 | 物理 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D3：slow 0.9s；系数0.8<br>D4：slow 0.9s；系数0.8 | `cooldown=9.0`；`count=3`；`paths_count=3`；`projectile_radius=14.0`；`recovery=1.7`；`shape="line"`；`speed=330.0`；`target_count=1`；`thematic_action="boulder_volley"`；`tracks_target=true`；`unlock_difficulty=3`；`width=28.0` | — |
| boulder_volley/P3 | 物理 | 每枚弹体命中一次 | 预警1.2s；锁定0.5s | D3：slow 0.9s；系数0.8<br>D4：slow 0.9s；系数0.8 | `cooldown=9.0`；`count=3`；`paths_count=3`；`projectile_radius=14.0`；`recovery=1.7`；`shape="line"`；`speed=330.0`；`target_count=1`；`thematic_action="boulder_volley"`；`tracks_target=true`；`unlock_difficulty=3`；`width=28.0` | — |
| seismic_crown/P1 | 物理 | 一次区域命中 | 预警1.6s；锁定0.5s | D4：无<br>D4：无 | `cooldown=11.0`；`duration=0.0`；`inner_radius=250.0`；`radius=550.0`；`recovery=2.3`；`ring_gap_degrees=105.0`；`shape="ring"`；`target_count=1`；`thematic_action="seismic_crown"`；`tracks_target=true`；`unlock_difficulty=4`；`weakpoint_duration=2.3`；`weakpoint_id="seismic_exhaustion"` | — |
| seismic_crown/P2 | 物理 | 一次区域命中 | 预警1.6s；锁定0.5s | D4：无<br>D4：无 | `cooldown=11.0`；`duration=0.0`；`inner_radius=250.0`；`radius=550.0`；`recovery=2.3`；`ring_gap_degrees=105.0`；`shape="ring"`；`target_count=1`；`thematic_action="seismic_crown"`；`tracks_target=true`；`unlock_difficulty=4`；`weakpoint_duration=2.3`；`weakpoint_id="seismic_exhaustion"` | — |
| seismic_crown/P3 | 物理 | 一次区域命中 | 预警1.6s；锁定0.5s | D4：无<br>D4：无 | `cooldown=11.0`；`duration=0.0`；`inner_radius=250.0`；`radius=550.0`；`recovery=2.3`；`ring_gap_degrees=105.0`；`shape="ring"`；`target_count=1`；`thematic_action="seismic_crown"`；`tracks_target=true`；`unlock_difficulty=4`；`weakpoint_duration=2.3`；`weakpoint_id="seismic_exhaustion"` | — |
| replay_path/P2 | 物理 | 每枚弹体命中一次 | 预警1.05s；锁定0.45s | D0：无<br>D4：无 | `count=2`；`paths_count=2`；`projectile_radius=11.0`；`recovery=1.25`；`shape="line"`；`speed=470.0`；`target_count=1`；`thematic_action="rock_fissures"`；`tracks_target=true`；`width=28.0` | — |
| replay_path/P3 | 物理 | 每枚弹体命中一次 | 预警1.05s；锁定0.45s | D0：无<br>D4：无 | `count=4`；`paths_count=4`；`projectile_radius=11.0`；`recovery=1.25`；`shape="line"`；`speed=470.0`；`target_count=1`；`thematic_action="rock_fissures"`；`tracks_target=true`；`width=28.0` | — |
| alternating_ring/P3 | 物理 | 一次区域命中 | 预警0.95s；锁定0.42s | D0：无<br>D4：无 | `duration=0.0`；`inner_radius=350.0`；`radius=520.0`；`recovery=1.1`；`ring_gap_degrees=82.0`；`shape="ring"`；`target_count=1`；`thematic_action="outer_ground_slam"`；`tracks_target=true` | — |
| heart_crack/P3 | 物理 | 一次区域命中 | 预警1.05s；锁定0.45s | D0：无<br>D4：无 | `duration=0.0`；`inner_radius=145.0`；`radius=315.0`；`recovery=2.8`；`ring_gap_degrees=105.0`；`shape="ring"`；`target_count=1`；`thematic_action="exhausted_ground_slam"`；`tracks_target=true`；`weakpoint_duration=2.8`；`weakpoint_id="cracked_heart"` | — |


## 6. 持续伤害、可反制窗口与奖励边界

持续区域：duration夹0–8s、tick_interval夹0.35–2s；非投掷区域从第一个间隔开始跳，投掷区域落点立即一次再按间隔跳。表列理论次数以目标始终在区内计算；玩家已有受击无敌、离开区域与区域清理会减少实际命中。既有同施法者持久区域最多2个，三落点都落地命中但只保留最新两个持久区；不要把伤害增加解释为扩张区域数量。现状边界见 [运行实现](../../scripts/combat/enemy_skill_runtime.gd)。

Boss弱点窗口仍使**玩家对Boss伤害**×1.35，不属于Boss对玩家增伤；窗口延迟/持续见技能表。BO03 sweep_land保留固定弱点延迟1.05s；BO04 crag_leap释放时按实际位移路程/速度更新弱点延迟。强制位移免疫保持，首领chill幅度系数0.5保持。

召唤类Q=0表示召唤动作自身无直接伤害，召出的怪物仍按其原型独立产生攻击；召唤怪、复生怪、机关端点零金币、零经验、零历练、零装备，不计自然击杀奖励或可奖励尸体。强化后的虫卵/掩体只能提高战斗耐久，不能生成额外掉落。自然怪、房间与首领奖励另见 [奖励现状](CURRENT_REWARD_CATALOG.md) 与主方案目标表。

## 7. 冻结来源与复现

运行 `python tools/balance/render_target_enemy_skills.py --check`，校验36×4阶、完整命令顺序、36种精英差异、40技能/103阶段变体/有效组合、17份运行源SHA256、非负整数四舍五入和文档逐字一致。普通生成命令不读存档、不启Godot、不依赖artifacts，也不写运行数据。首次冻结/刷新须先按现状生成器隔离APPDATA与LOCALAPPDATA导出纯解析JSON，再运行 `python tools/balance/render_target_enemy_skills.py --freeze-export artifacts/balance-enemy-catalog/current.json`；这是显式维护操作。

空间fixture坐标已从小型冻结输入移除，保留targets_count/paths_count与所有伤害、状态、时间、半径、系数及原机制标量；完整几何由带源哈希的Brain实现负责，不据此改变真实移动轨迹。

| 来源 | SHA256 |
| --- | --- |
| [config/balance.gd](../../config/balance.gd) | 6b7a1bdc4f66b18c21699e26cabdaea09aff679b916a5dad011a289f1e24c2da |
| [data/enemies.json](../../data/enemies.json) | c9a787100b47d0e668d13cc0fa64ce43f83088dfa1ae68208881e5c7ef52197b |
| [data/enemy_progression.json](../../data/enemy_progression.json) | f8b16d6d8b991b5413b264d00ef6e6524166af13ce4c7ca37389fab967674465 |
| [data/rooms.json](../../data/rooms.json) | 21c593c8156111530adc7d50e6092e02c531fb283305ec1ba70f0becaf53c73e |
| [scripts/combat/boss.gd](../../scripts/combat/boss.gd) | e76e521b73cf6a3ef71a277d16ef6612abf3a717ce017cbd963448821b810f1c |
| [scripts/combat/boss_ability_catalog.gd](../../scripts/combat/boss_ability_catalog.gd) | c835b080ef74e07f7d89a0ac3071ce727a2df5f704a7f455343e332774822cc9 |
| [scripts/combat/boss_brain.gd](../../scripts/combat/boss_brain.gd) | 0fc756b22762736c7a9e340a2ac427a906352bdb1f83abfb9ae9a182a00e9a30 |
| [scripts/combat/boss_profiles.gd](../../scripts/combat/boss_profiles.gd) | ae93ec4e934be788d5bd993d6a93f8c50673e819f187e91e72c8a84d7b7c6d70 |
| [scripts/combat/combat_status.gd](../../scripts/combat/combat_status.gd) | abf0ec44667192d8b566c7523811bc1a97f49a7aec12f1ffadb2f98977e4404e |
| [scripts/combat/damage_resolver.gd](../../scripts/combat/damage_resolver.gd) | 71b5e58cae2d227f7795df79f2bd731b84d3686acf5f1d7da5febdb883f0ac10 |
| [scripts/combat/enemy_biome_skills.gd](../../scripts/combat/enemy_biome_skills.gd) | 77672d43b47a1b62534a90c295eec4ea991ca0010c840b625fcb34329753af3a |
| [scripts/combat/enemy_brain.gd](../../scripts/combat/enemy_brain.gd) | 8faf684605b52a9fcca1910c4844616b94a98ee93a5a721a04092d2fa3f83b40 |
| [scripts/combat/enemy_difficulty.gd](../../scripts/combat/enemy_difficulty.gd) | 0e6b5bc43f048e71e07f586c6f724af958fe39fd4380d0a1216242816e1ef12c |
| [scripts/combat/enemy_profiles.gd](../../scripts/combat/enemy_profiles.gd) | 1baf92e353ea9e878124e51565b5af33f4acf1e9a2dde9e2970107d7bc3af80f |
| [scripts/combat/enemy_skill_runtime.gd](../../scripts/combat/enemy_skill_runtime.gd) | 6df1f27cfccd460f921873e2108e3539cf05f417a55fc61cb4d546236bd55b34 |
| [scripts/combat/player.gd](../../scripts/combat/player.gd) | 5356b3cffe05d466c5a12e487f445d854fd3a349779e053ba5c603c0f3db7833 |
| [scripts/combat/room.gd](../../scripts/combat/room.gd) | 69d2109acd31d5c3c36bec812afbda06fc4d585129bbe11a66026d4d789e47db |


文档校验只证明公式与表格一致。新倍率、盾治疗叠加、整数舍入与高难度战斗体验仍需获得方案确认后实现，并以普通/精英、各Boss阶段的实际对战样本校准；当前游戏仍执行CURRENT册中的旧值。
