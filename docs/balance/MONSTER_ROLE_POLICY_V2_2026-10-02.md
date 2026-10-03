# B01–B06 普通/精英定位政策 v2（待实战校准）

> 历史基线保留：本文原公式/表格对应当时冻结版本，不是archive14当前面板。当前B01–B06统一模型、双防成长、取整与实际导出见[原数值总案第9节](LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md#9-野怪首领与难度标尺)及各章原正文；旧档仍按原快照回放。下文“当前”均指本文原记录时点，不作新模型验收证明。

## 方案与范围

全部已实现普通/精英的生命、实际伤害属性、护甲、魔抗统一×1.5，再只应用一个定位专项分支。不再采用全体仅攻击×2.5/3.5实验。

|定位|额外HP|额外damage|额外armor/MR|相对旧v1总倍率（HP/伤害/双防）|
|---|---|---|---|---|
|坦克|×1.20|×1|×1.15|1.8 / 1.5 / 1.725|
|法师、刺客、远程输出|×1|×1.15|×1|1.5 / 1.725 / 1.5|
|近战/游击|×1.10|×1.05|×1|1.65 / 1.575 / 1.5|
|辅助|×1.10|×1|×1.10|1.65 / 1.5 / 1.65|

以冻结v1最终整数属性为基线，共同倍率与专项乘积在政策边界半向上取整一次；旧基线的等级/精英/难度计算和取整不变，不倒推浮点raw。生产仅有统一damage属性，物理/魔法技能读取该属性，不虚构独立法强字段或改伤害类型。M38的caster身份配physical伤害仍保留。

坦克/辅助身份优先于攻击几何：M54虽然artillery仍走坦克，远程辅助不误归输出。未知archetype显式拒绝，不静默混类。重新resolve从numerical_legacy_base生成；已应用政策对象不能直接再apply。

B05/B06同role同D旧双防相同，新政策保持这一继承关系；HP/攻击随固定等级和章系数上升。双防持平不等于综合强度倒退，也未暗加第二个章节防御倍率。

移速、攻速/收势、射程、预警、锁定、技能系数、玩家成长/装备/护盾、SU6与潮盾规则不变。根井等机制端点明确继续旧HP基线，不纳入野怪。Boss独立采用boss_progression_policy v2，不叠野怪×1.5，见[BOSS_MONOTONIC_POLICY_V2_2026-10-02.md](BOSS_MONOTONIC_POLICY_V2_2026-10-02.md)。

## 版本与回退

- 新run默认enemy_calibration archive13，同时选择普通定位和Boss递增v2；不改变章节发布gate。B05/B06仍只按原candidate入口开放。
- 空快照/archive1永久旧v1；archive2–12原系数保留作旧实验档回放，旧CLI不再选为新默认。
- B05/B06 Numbers/Skills保留calibration参数并支持显式数值version，按同一档案版本严格重建验证。旧进行中run不换成当前配置。
- 旧测量JSON、旧配装清单和旧数值合同保留，不能把旧结果标成新方案通过。

## 定向验证

2700配置：90物种×3合法等级×5D×普通/精英；验证共同倍率及唯一专项、旧档/JSON往返、命令冻结/防双算、同模板逐D四字段严格上升。720个入口/尾级、D0/D4、普通/精英端点通过真实演员configure/_ready验证HP/damage/armor/MR。51527项0失败；只证明对应接线，不能替代自然战斗或难度验收。B05/B06新自然样本另行记录。

## 接线检查点（不等于平衡验收）

2026-10-02 23:24 UTC冻结当前参数，后续按用户要求先将B06合入B05，再做整合测试。当前表格及51527项矩阵证明的是版本接线和属性规则，不能将分支自然样本当作合并后验收。

B06潮相快照带Boss数值版本及校准来源；旧快照缺来源字段固定回放v1，不读取当前默认。Boss潮相状态和演员最大HP交叉验证，非canonical HP拒绝且不改现有状态。生产房间潮相与召唤沿用run校准快照。B06最小检查：潮相75项0失败（archive0/1/7/12/13及篡改拒绝），战斗快照20项0失败；没有改潮相时序、壳体或玩家规则。

新run开关为data/numerical_v2.json中enemy_calibration archive13；B05/B06章节仍需现有candidate入口，不由数值版本发布。D4 Boss实际基础属性依次为B05 HP158780/damage984/双防380，B06 HP182596/damage1130/双防400。不叠加旧B05×8.7或旧职业候选。裸装目标是正常操作无法通关，不要求短时间死亡；当前普通参数不为站桩快死追加系数。

## 逐物种分类

来源为现有data/enemies.json的archetype/role和B05/B06 authored profile；不是依新数值反推角色。

|章|ID|名称|archetype|原role|原伤害类型|唯一专项|
|---|---|---|---|---|---|---|
|B01|M01|晴辉构装巡庭夹卫|skirmisher|melee|physical|skirmisher|
|B01|M02|晴辉构装冲锋蛛卫|skirmisher|charger|physical|skirmisher|
|B01|M03|晴辉构装远程炮手|skirmisher|ranged|physical|output|
|B01|M04|晴辉构装蜂群微卫|skirmisher|swarm|physical|skirmisher|
|B01|M05|晴辉构装滚轮猎犬|skirmisher|charger|physical|skirmisher|
|B01|M06|晴辉构装护翼师|support|cover_support|magic|support|
|B01|M07|晴辉构装磁叉牵引师|skirmisher|displacement|physical|skirmisher|
|B01|M08|晴辉构装塔盾卫|tank|defender|physical|tank|
|B01|M09|晴辉构装鸣炉支援者|support|support|physical|support|
|B02|M10|琥珀虫族镰足刺虫|assassin|melee|physical|output|
|B02|M11|琥珀虫族针吻酸炮|caster|artillery|magic|output|
|B02|M12|琥珀虫族育卵萤母|support|summoner|physical|support|
|B02|M13|琥珀虫族剪钳幼蜓|assassin|flanker|physical|output|
|B02|M14|琥珀虫族黏足幼虫|skirmisher|swarm|physical|skirmisher|
|B02|M15|琥珀虫族掘地锹甲|assassin|ambusher|physical|output|
|B02|M16|琥珀虫族搬运丸甲|support|interference|physical|support|
|B02|M17|琥珀虫族回春萤卫|support|healer|physical|support|
|B02|M18|琥珀虫族破墙犀甲|tank|terrain|physical|tank|
|B03|M19|南瓜僵尸提灯哨兵|support|support|physical|support|
|B03|M20|南瓜僵尸远程弩手|skirmisher|ranged|physical|output|
|B03|M21|南瓜僵尸蹦跳兵|skirmisher|ambusher|magic|skirmisher|
|B03|M22|南瓜僵尸熔糖炮手|caster|artillery|magic|output|
|B03|M23|南瓜僵尸牵引术士|skirmisher|displacement|physical|skirmisher|
|B03|M24|南瓜僵尸冰雾泵手|caster|ranged|magic|output|
|B03|M25|南瓜僵尸护盾卫士|tank|defender|magic|tank|
|B03|M26|南瓜僵尸裁缝护卫|tank|defender|physical|tank|
|B03|M27|南瓜僵尸节拍铲兵|skirmisher|melee|physical|skirmisher|
|B04|M28|赤岩兽人疾行斥候|assassin|swarm|physical|output|
|B04|M29|赤岩兽人幻影刀手|assassin|flanker|physical|output|
|B04|M30|赤岩兽人战鼓祭司|support|support|physical|support|
|B04|M31|赤岩兽人冷晶弩手|caster|ranged|magic|output|
|B04|M32|赤岩兽人跃袭猎手|assassin|ambusher|physical|output|
|B04|M33|赤岩兽人绳网猎手|support|terrain|physical|support|
|B04|M34|赤岩食人魔反击卫|tank|defender|physical|tank|
|B04|M35|赤岩食人魔窃灯手|support|interference|physical|support|
|B04|M36|赤岩兽人雷符爆破兵|caster|bomber|magic|output|
|B02|M37|琥珀织网螳|caster|displacement|magic|output|
|B02|M38|晶翅回针蛾|caster|ranged|physical|output|
|B02|M39|鼓腹震巢虫|tank|melee|physical|tank|
|B03|M40|提灯引魂僵|caster|displacement|magic|output|
|B03|M41|缝袋抛种僵|caster|artillery|magic|output|
|B03|M42|棺盖铁卫|tank|defender|physical|tank|
|B03|M43|钟铃送葬僵|support|support|magic|support|
|B03|M44|稻草换影僵|assassin|flanker|physical|output|
|B03|M45|南瓜缝线医|support|healer|physical|support|
|B04|M46|双斧回旋兽人|skirmisher|ranged|physical|output|
|B04|M47|岩索拖拽兽人|skirmisher|displacement|physical|skirmisher|
|B04|M48|战鼓催阵兽人|support|support|physical|support|
|B04|M49|獠牙冲阵兽人|tank|charger|physical|tank|
|B04|M50|投网猎手兽人|skirmisher|terrain|physical|skirmisher|
|B04|M51|巨盾反击食人魔|tank|defender|physical|tank|
|B04|M52|裂地锤手食人魔|tank|melee|physical|tank|
|B04|M53|掷桶火油食人魔|caster|artillery|magic|output|
|B04|M54|震步搬岩食人魔|tank|artillery|physical|tank|
|B05|B05-M01|藤鞭树卫|skirmisher|F|physical|skirmisher|
|B05|B05-M02|种荚炮手|skirmisher|R|physical|output|
|B05|B05-M03|苔靴芽灵|assassin|A|physical|output|
|B05|B05-M04|露珠护蕊|support|S|physical|support|
|B05|B05-M05|刺篱搬运者|tank|T|physical|tank|
|B05|B05-M06|卷叶斥候|assassin|A|physical|output|
|B05|B05-M07|花冠术士|caster|C|magic|output|
|B05|B05-M08|根线织工|support|S|physical|support|
|B05|B05-M09|棘轮滚果|assassin|A|physical|output|
|B05|B05-M10|香粉铃兰|caster|C|magic|output|
|B05|B05-M11|树脂盾卫|tank|T|physical|tank|
|B05|B05-M12|捕虫花匠|skirmisher|R|physical|output|
|B05|B05-M13|寄枝槲卫|skirmisher|F|physical|skirmisher|
|B05|B05-M14|日照蓄能花|caster|C|magic|output|
|B05|B05-M15|藤桥看守|skirmisher|F|physical|skirmisher|
|B05|B05-M16|蒴果散射手|skirmisher|R|physical|output|
|B05|B05-M17|古年树精|tank|T|physical|tank|
|B05|B05-M18|四季园监|support|S|physical|support|
|B06|B06-M01|三叉戟鱼卫|skirmisher|F|physical|skirmisher|
|B06|B06-M02|寄居蟹炮手|skirmisher|R|physical|output|
|B06|B06-M03|甲壳盾卫|tank|T|physical|tank|
|B06|B06-M04|银鳍针鱼|assassin|A|physical|output|
|B06|B06-M05|泡沫司祭|support|S|physical|support|
|B06|B06-M06|海胆布雷者|skirmisher|R|physical|output|
|B06|B06-M07|涡歌鲛人|caster|C|magic|output|
|B06|B06-M08|珊瑚筑垒师|support|S|physical|support|
|B06|B06-M09|蓝钳冲城蟹|tank|T|physical|tank|
|B06|B06-M10|珠光水母|caster|C|magic|output|
|B06|B06-M11|海马骑枪卫|skirmisher|F|physical|skirmisher|
|B06|B06-M12|螺旋喷流螺|skirmisher|R|physical|output|
|B06|B06-M13|潮钟领唱者|support|S|physical|support|
|B06|B06-M14|锯鳍潜猎者|assassin|A|physical|output|
|B06|B06-M15|砗磲护珠者|tank|T|physical|tank|
|B06|B06-M16|深渠网捕手|skirmisher|R|physical|output|
|B06|B06-M17|浮礁背负兽|tank|T|physical|tank|
|B06|B06-M18|潮庭执旗官|support|S|physical|support|

分类计数：{'skirmisher': 16, 'output': 37, 'support': 19, 'tank': 18}。
