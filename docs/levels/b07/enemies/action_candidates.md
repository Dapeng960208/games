# B07 首房与蜥王：动作／独立特效候选

> 2026-10-03，08:54更新。已落盘46张动作PNG（44个姿态设计点，另含2张蓄势修订/替代来源）+ 11张独立特效，逐张查看并保存来源。不是连续动画，未接入运行。没有改数值、碰撞、房间、运行登记或技能代码。

## 本批覆盖与实际代码

依据 scripts/levels/b07/combat/enemy_skills.gd、enemy_brain.gd、enemy_runtime.gd、boss_brain.gd；不以设计表覆盖当前运行参数。

| 身份/真实技能 | 关键姿态路径（assets/levels/b07 下） | 当前命令约束 |
|---|---|---|
| B07-M01 sun_spear | enemies/m01/actions/sun_spear/{telegraph,execute,recovery}_candidate.png | 线180/宽30；D0 authored tell .9s，经timing规则解析；D2另有反向半圆尾扫，独立.8s提示；D4受光后无伤前移60 |
| B07-M02 camouflage_leap | enemies/m02/actions/camouflage_leap/{telegraph,execute,recovery}_candidate.png | 跃击上限210、落点半径55、运动.4s、预警最低1s、恢复1.2s；仅落地伤害；D2后续沙团 |
| B07-M03 returning_disc | enemies/m03/actions/returning_disc/{telegraph,execute,recovery}_candidate.png | 飞盘距离260/宽22/半径11/速度320；D2回返gap .8s，D4受光固定斜回，不重新追踪 |
| BO07 sun_spear | bosses/bo07/actions/sun_spear/{telegraph,execute,recovery}_candidate.png | 线240/宽38，authored tell1.2s，经boss timing规则解析；恢复1.3s |

预警姿态只表达蓄势。地面line/circle/ring和锁定方向仍由原命令绘制；不能把一幅美术环当实际半径或把矛尖当碰撞终点。M02跳跃关键帧的脚只是空中足底标记，无实际地面脚点，不能拿它平移落地根节点。

## 6张独立特效

所有路径均在 assets/levels/b07/effects/<id>/effect_candidate.png。

- spear_impact：矛尖小型金白命中光；可作M01/BO07视觉风格候选，不延长真实矛线。
- sand_landing：M02落地沙环，非持续伤害地形、非预警几何。
- sand_ball：M02 D2落地后沙团弹体候选。
- sand_disc：M03独立青绿心铜砂飞盘；去回共用同物件，路线/时序独立。
- sun_disc：BO07日盘独立金色弹体；真实命令距离360/宽28/速度360、回返gap1s。此图不表示Boss掷盘身体动作已做。
- altar_beam：BO07最多两条固定祭坛光线的窄光材质；真实宽24/恢复1.5s，不能自行新增线或堵第三安全区。生成末端是圆滑淡出，不是可无缝平铺成品。

## 来源、像素与连续性 QA

每张源PNG字节未改；同目录provenance记录提示词、生成文件名/哈希、身份参考哈希、实际原生尺寸和alpha>=128内容包围盒。汇总 [action_batch_qa.json](action_batch_qa.json)。有效内容按单帧测，不计透明留白或整atlas。当前所有18张alpha>=128均未触画布边，但M01突刺/斥候跳跃手指/Boss冠等边距很窄。

12张姿态记录人工足底点和解剖顶点，约±20px；这些是审阅标记，不是运行帧注册。动作压低身姿后，不能把每帧当前冠顶至脚的高度都拉回idle高度，这会造成角色膨胀；下一步应按同个头骨/躯干稳定尺寸确定统一倍率，再统一地面根脚点，空中帧单独保留运动根节点。当前 scale_and_foot_continuity_passed=false。

明确待修：

- M01蓄势矛/盾手相对idle疑似交换，暂不能接成动作序列。
- M03蓄势与施放躯干转动导致手臂交叠变化，同手连续性须按肩部追踪核实，不能仅凭屏幕左右位置断言换手。施放和恢复已正确没有手持主盘，腰间备盘保留。
- 几组原生画幅/角色大小不同，脚点与稳定解剖比例尚未统一，不能直接拼图集冒充连续帧。
- M02已画空中与落地不同姿态，地面root不能跟空中脚走；尾卷/衣摆与手部仍需过渡帧。
- M03独立盘纹样与手持盘有细节差异，统一修改时匹配。特效低alpha杂边/砂环透明中心/暗浅背景可读性需真实合成复核。
- RGB中存在被alpha=0完全遮住的暖色背景，不等于透明失败；禁止忽略alpha读RGB就认作实底，也不能盲目清零低alpha假造干净边缘。

## 尚未覆盖

当前仍缺：全身份walk/hit/death、全方向和连续过渡帧；伪装进入/退出、受光护罩完整转态、完整附加技能连续动作。M01尾扫、M02投沙、M03接盘、Boss尾扫/掷盘/光网和压坛露背已在后续批次补候选，见下方清单。Boss王卫和日轮归位在实际代码仍未实现，不宣称覆盖。其余10种未实现主动身份的三阶段设计候选正在独立目录生成，完成来源QA后再落入本目录。房间仍暂停。


## 后续批次覆盖（08:54）

- stage2_qa.json：M01尾扫3、BO07尾扫/日盘/光网9，共12关键姿态；另保留M01持手修订失败候选1张。
- stage3_qa.json：M04盾击、M05治疗、M06出土各3姿态，共9。
- stage4_qa.json：M07沙涡、M13光束各3姿态，共6。
- stage5_qa.json：M02 D2沙团3、M03接盘1、BO07压坛露背1，共5。
- effects_batch2_qa.json：日鳞盾弧、绿松石治疗线、掘地土丘、沙涡、太阳折光节点，共5特效。
- 已实现8普通主动与BO07四招均有主技能三阶段候选。设计尚未实现主动的M08/09/10/11/12/14/15/16/17/18正在各制3动作+1物件/VFX。是否技能实现与是否有美术资源分开统计。
- 完整运行连续动画仍为0套；当前覆盖不是全方向/行走/死亡/受击/过渡动画完成。

新增目录保持身份/actions/技能名/{phase}_candidate.png；特效在effects/语义ID/effect_candidate.png。最新逐PNG索引与alpha16/128内容测量见art_coverage.json。旧批QA保留其当时的来源与明确问题，不以较新批次数量改写原测量。

独立alpha合成抽查：M18 idle、M01突刺、沙涡、治疗线在浅砂色和暗紫色平底上正常合成，未见原始RGB预览中的大范围背景光晕；沙涡中心可透底。仅4张抽样，不是全背景/实机/全部边缘验收，PNG源字节未修改。诊断图不入库。


09:02 M01蓄势定向修订：从已正确持手的execute直接回收同侧肘部，新增telegraph_retracted_candidate.png。实际查看盾/大肩甲保持同臂、矛仍在另一原臂，持手问题在此候选改善；把它作为下一轮审阅优先项，保留两张旧失败蓄势来源。身体倍率/脚点仍未统一，不宣布动画已通过。
