# 职业技能与表现约定

更新：2026-10-03。**状态：三职业已接入；完整连续动作与自然手感待验证。** 具体职业内容分别见 [战士](../../characters/warrior/README.md)、[枪手](../../characters/gunner/README.md)、[法师](../../characters/mage/README.md) 和 [共用职业约定](../../characters/shared/role_optimization.md)。召唤师未实现。

## 代码与资源

角色节点和技能提交位于 `scripts/gameplay/characters`，职业成长与战斗规则分别位于 `scripts/domain/progression`、`scripts/domain/combat`。动作采样与反馈位于 `scripts/presentation/characters`，不能发放奖励或决定真实命中。

美术按 `assets/characters/<profession>/{animations,portraits,skills,ui}` 保存；纹理、动作区域、脚点、来源与许可一起维护。当前动作通过 `assets/manifest.json` 注册并由 `AssetCatalog` 解析，逻辑 ID 不因目录搬迁重排。

战士使用当前战斧完整动作家族及八方向攻击；旧采矿人物、液压锤动作与被替换候选已删除。枪手、法师仍使用当前节点实际引用的前后动作与八方向攻击资源。法师完整连续行走尚未实现，停用的旧行走候选已删除。缺少某个姿态时只能使用当前注册待机身体，不能回退到旧人物立绘或旧程序人物。

## 输入与提交

默认技能键 Q/W/E/R 对应内部 `q/secondary/f/ultimate`；F 为交互。HUD 从实际绑定显示提示。普攻默认鼠标左键，右键移动，空格闪避。

本次攻击或闪避方向在提交时冻结。鼠标后续移动不能改变已释放弹体、攻击命中、收势或闪避方向。枪口、身体、脚点和可见弹体共用来源变换；身体尺度由 `scripts/shared/presentation_metrics.gd` 统一控制，当前为112世界像素。

步态按实际解算后的移动推进；贴墙、传送和单纯按键不能伪造步行。暂停、弹窗、背包、闪避、死亡及切房清空动作队列。表现不会改变已经提交的资源成本、冷却、碰撞、伤害或奖励。

枪手 E 使用定时榴弹，法师部署物为法晶与领域。职业被动、连击、状态及装备效果按当前配置与实际技能链路结算；目标设计和候选倍率不能覆盖正式默认参数。

## 检查与待完成

当前检查入口包括 `hero_storybook_family`、`numerical_hero_skills`、`equipment_class_policy`；实际结果以当前源码的隔离运行日志为准。旧锤动作时序断言与旧阶段截图成绩已移除。

尚待完成完整连续行走/闪避动作、可见装备附件、所有分辨率与方向的枪口/脚点体验，以及密集敌群、长时间输入和自然战斗平衡。无界面采样检查不能作为目标硬件或完整自然玩法验收。
