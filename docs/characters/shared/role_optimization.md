# 三职业共用规则

> 状态：新职业、十二选四、成长与装备适配已接入新版 UI；三十六技能实际释放及三职业首关章节复查完成。完整手绘连续动作、法师战斗美术身份与人工主观手感未验收。

战士 CH01、枪手 CH02、法师 CH03 使用当前角色登记和统一解析器。战士积怒进入八秒狂暴；成年女性枪手机动射击并精准装填；成年暗黑法师与唯一团团协同，实际技能释放驱动星辉协奏。旧破势、三击盾、目标弱点、猎印与法晶不继续暗中触发。不能把所有套装条件统一为普攻，或把“共有三职业”自动扩展为未实现召唤师。

职业身体统一 112 世界像素，脚点与武器释放点以注册为准。目标屏幕为 2560×1440，保留 1280×720 逻辑布局与 canvas_items 缩放；手绘动作按方向拆分，单帧主体目标高度至少约 448 像素，不能用整张大图集尺寸掩盖每帧像素不足。成长、技能、被动、连击、装备资格与显示数值来自同一套运行规则。镜像和关键姿态不等于完整八方向连续动画；自然战斗手感与获取平衡仍待验证。

本轮操作反馈沿用已有有限时间轴和真实事件。战士普攻冻结起手方向，实际伤害锥与斧光一致；攻击者和受击怪物共用接触定帧，游戏时钟、移动和预警继续运行。枪手及法师普通弹不再叠加统一大推力，战士的确认命中位移和技能自身推拉保留。枪手装填开始、普通完成、精准成功、精准失败分别产生一次反馈，自动空弹匣走相同入口。法师共鸣、巡游、跃步分别使用联合圈、实际周身波及原点寒冷圈，团团亮点与真实弹体的视觉发射点一致。

开源参考仅用于核对时序和状态组织，没有复制第三方美术或导入整套框架：[GDQuest Juicy Attack 时间轴](https://github.com/gdquest-demos/godot-4-juicy-attack/blob/main/sword/sword_2d.tscn)、[GDQuest 受击反馈](https://github.com/gdquest-demos/godot-4-juicy-attack/blob/main/enemies/scarecrow_2d.gd)、[Jeh3no 装填状态](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system/blob/main/addons/JehenoSimpleFPSWeaponSystem/Weapons/Scripts/reload_manager_script.gd)。脚本许可分别见 [GDQuest LICENSE](https://github.com/gdquest-demos/godot-4-juicy-attack/blob/main/LICENSE) 与 [Jeh3no LICENSE](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system/blob/main/LICENSE)；GDQuest 的图片、模型与脚本许可不同，本项目继续使用原创资源。

- [职业入口](../README.md)
- [技能规则](../../system/combat/role_skills.md)
- [装备资格](../../system/equipment/class_policy.md)
- [运行英雄定义](../../../data/characters/heroes.json)
