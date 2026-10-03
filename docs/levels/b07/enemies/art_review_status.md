# B07 角色资源审阅包

> 2026-10-03 09:20 UTC。全身份／主职责姿态／独立技能物件已有审阅候选，整体质量未通过。未改房间、运行登记、战斗数值或碰撞；未运行游戏／测试、未提交或推送。

## 已落盘的真实数量

- 19身份图：B07-M01–M18与BO07；M01既有idle不变，其余18张本次新增。
- 76动作PNG：74个关键姿态设计点＋2张M01蓄势修订/替代来源。不是76帧连续动画。
- 21张独立技能物件/VFX。
- 完整连续动画0套；新候选运行接入0。
- 精英没有独立稳定ID；王卫是M02派生，尚未另外制出独立变体。

总计116张当前角色/技能PNG，不含房间。每张有prompt、原生成路径与SHA、原生字节保存、有效alpha内容像素或人工脚点测量。原始低alpha未阈值剪除，未放大／补留白伪装更高有效采样。

完整文件索引与逐PNG alpha16/128包围盒：[art_coverage.json](art_coverage.json)。逐ID职责与配色/器具规范：[art_roster.md](art_roster.md)。

## 每身份主动作覆盖

每个下列技能目录均在 assets/levels/b07/enemies/<id>/actions/<skill>/ 下，含 telegraph_candidate.png、execute_candidate.png、recovery_candidate.png。

| ID | 技能目录 | 真实主动状态 |
|---|---|---|
| M01 | sun_spear | 已实现候选；优先审阅telegraph_retracted_candidate.png，原蓄势持手问题保留 |
| M02 | camouflage_leap | 已实现候选 |
| M03 | returning_disc | 已实现候选 |
| M04 | sunscale_shield | 已实现候选 |
| M05 | turquoise_heal | 已实现候选 |
| M06 | sand_emerge | 已实现候选 |
| M07 | sand_vortex | 已实现候选 |
| M08 | mirror_slash | 尚未实现；基础攻击后备，图仅设计 |
| M09 | dart_venom | 尚未实现；基础攻击后备，图仅设计 |
| M10 | mirror_attendant | 尚未实现；基础攻击后备，图仅设计 |
| M11 | sand_ridge | 尚未实现；蓄势读感blocked |
| M12 | awning_bolt | 尚未实现；基础攻击后备，图仅设计 |
| M13 | sun_beam | 已实现候选 |
| M14 | twin_slash | 尚未实现；仅首斩/收刀设计，非完整双拍 |
| M15 | camouflage_banner | 尚未实现；基础攻击后备，图仅设计 |
| M16 | stargazer_arc | 尚未实现；恢复含单眼罩打开设计 |
| M17 | obelisk_cross | 尚未实现；基础攻击后备，图仅设计 |
| M18 | light_ceremony | 尚未实现；恢复含断镜失衡设计 |

BO07在 assets/levels/b07/bosses/bo07/actions/ 下：sun_spear、golden_tail、sun_disc、altar_lines四招各三姿态。四招已有实际代码候选；王卫/日轮归位仍未实现，不借此补画谎称实现。

另有M01 tail_sweep三姿态、M02 sand_ball三姿态、M03 returning_disc/catch_candidate.png、BO07 altar_suppressed/exposed_candidate.png。

## 独立技能物件与特效

均在 assets/levels/b07/effects/<id>/effect_candidate.png：

spear_impact、sand_landing、sand_ball、sand_disc、sun_disc、altar_beam、sunscale_shield、turquoise_link、sand_mound、sand_vortex、sun_beam_node、mirror_short_light、poison_dart、mirror_state_indicator、sand_ridge_segment、heavy_crossbow_bolt、blade_arc、fallen_banner、eye_light_arc、sandstone_impact、support_node。

它们只是原色视觉材料。预警线/圆/扇/十字、安全扇区、方向锁定、伤害范围和持续时间仍以现有命令为权威；不得用美术曲线扩大命中。M10三态镜是单图概念，尚不是可切换运行状态层。M13独立节点也不表示折线路径实现完成。

## 主要未过项与下一次统一收敛

1. M11蓄势抬前足读感不成立；一次修版丢远后脚被拒。保留初版为blocked，不当合格动画。
2. 脚点／骨架稳定倍率／透视未统一。不同姿态画幅和当前身体纵高不同；不能把蹲姿独立拉到idle同高。需固定头骨/躯干比例，按地面root统一脚点；空中帧的足底不是地面root。
3. M01新telegraph_retracted修订持手关系改善，旧两张来源不优先。M03须按肩部/肘部轨迹核实同手，不能仅凭屏幕左右判断。Boss日盘/光网持杖侧跨姿态、M15旗杆连续性、M18持杖方向仍需检查。
4. M11施放已补四脚、M12恢复已修多手。M17落拳仍遮远脚部分趾，M05/M18尤其偏低机位。Boss尾扫施放仍偏卷尾，动作读感未过。
5. 多图武器/镜顶/旗尖留边不足。所有选定中/末段图alpha≥16/128不碰边，不等于留边质量通过；低alpha杂边仍保留。
6. 已查原图及中/末段全部浅砂/暗紫正常合成，无预览RGB中的大片光晕；主批仅部分双背景抽查。依然不是目标场景/缩放/硬件/动态边缘验收。
7. 行走、受击、死亡、全方向、连续过渡、精英/王卫派生及完整追加技能状态未制成。此包是造型与关键动作可审阅覆盖，不是整关完整动画成品。

## 分批证据

- first_batch_qa.json / roster_qa.json：身份图单帧/身体像素
- action_batch_qa.json：首批12姿态和6特效
- stage2_qa.json–stage6_qa.json：追加动作、持手修订及明确失败
- effects_batch2_qa.json：五类已实现职责特效
- mid_actions_qa.json：M08–M12三姿态/独立物件，含M11 blocked
- late_actions_qa.json：M14–M18三姿态/独立物件与来源修版

仅通用资源索引登记，不改registration/native_art.json。最初8个WIP文件diff与开工快照逐字节相同，M01既有idle源哈希不变。截图/双背景诊断图未入库。
