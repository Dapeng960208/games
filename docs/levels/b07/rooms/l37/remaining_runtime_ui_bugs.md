# L37 已确认剩余 UI 问题（只读记录）

基线 `854c40b`，证据批次 `20261003T122349570762Z-6cb9a02e`。以下保留修前只读诊断；后续修复及窄范围实际图验证见 [terminal_ui_review.md](terminal_ui_review.md)。此前 280 次正常运行 post-draw 检查只证明运行中卡片批次、身份、布局；不覆盖终态清理或反制文案语义。

## 死亡残值和卡片

`L37_live_06_terminal_player_death.png` 显示 Defeated，但仍显示 HP 451/6091、被动 1/3、技能、任务及 2 张敌技能卡。报告最后活帧 t=24.35/frame1462 HP451；终态 t=24.3667/frame1463 Game.run 已清空；截图 t=24.3833/frame1464 仍有2张卡。M01 recovery、M03 execute 的旧命令保留。

- `scripts/app/game.gd:319–320,472–476` 清空 run 并发 run_finished。
- `scripts/levels/b07/world/candidate_scene.gd:62–71,79–83` 只持局部 HUD 引用，死亡只追加状态文字。
- `scripts/presentation/hud/hud.gd:792` 在 null run 直接返回，保留旧 HP、资源、技能值。
- `scripts/gameplay/monsters/enemy_actor.gd:173–174` 在清理旧 brain commands 之前停止。
- `scripts/levels/b07/art/l37_skill_card_layout.gd:43–61` 继续基于存活敌人的残留命令发布卡片。

最小建议：候选入口在 run_finished 处理其战斗 HUD 的终态显示；卡片协调器必须发布空终态批次、清空选中/信息/命令并隐藏卡片。不能只 hide 一次或直接早退。增终态 post-draw 断言。目前没有实施。

## D0 文案包含未启用 D2 技能

`L37_live_01_timed_0_8.png` M01 显示“侧走离开矛线，尾扫有0.8s独立提示；胸”，M03 显示“两段预警分别显示，不追踪回返；头”。同报告 difficulty=0，followups=0，无 disc_return。

- `scripts/levels/b07/combat/enemy_skills.gd:74–76` 把 counter_and_drop_text 全文作为实时反制文案。
- `data/levels/b07/content.json:222,334` 原字段混合跨难度反制和掉落槽。
- 实际尾扫在 enemy_skills.gd:81–84 需 d>=2；飞盘回返在 :96、:173–181 需 d>=2。
- enemy_ability_catalog.gd:778–779 / enemy_skill_presentation.gd:81 如实展示了上游不适用文字。

最小建议：从实际 command 机制/难度构造 B07 实时反制提示。D0 仅矛线/去程飞盘，存在追加尾扫/返程时才显示对应提示；不把装备槽显示在战斗卡上，保留原设计和掉落资料。测试增加 D0/D2 文案断言。本轮没有实施。

输入为固定脚本、Lv31 开场装备，24秒死亡不能作为正式难度或自然战斗平衡结论。
