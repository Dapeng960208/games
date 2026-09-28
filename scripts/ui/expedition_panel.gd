extends Control
## Original compact expedition chart, built from live committed route state.
signal choice_requested(room_id: String)
signal close_requested()
signal early_extract_requested()

const ROLE_ZH := {"entrance":"入口", "branch":"分支", "objective":"目标", "supply":"补给", "elite_objective":"精英", "boss":"首领"}
const ROLE_EN := {"entrance":"ENTRY", "branch":"BRANCH", "objective":"OBJECTIVE", "supply":"SUPPLY", "elite_objective":"ELITE", "boss":"BOSS"}
const ENEMY_ZH := {"melee":"近战", "charger":"冲锋", "ranged":"射手", "swarm":"虫群", "cover_support":"掩体", "displacement":"牵引", "defender":"盾卫", "support":"支援", "artillery":"抛射", "summoner":"召唤", "flanker":"侧袭", "ambusher":"伏击", "controller":"控场", "healer":"治疗"}
var controller: RefCounted
var allow_advance := false
var submitted := false

func configure(source: RefCounted, can_advance: bool) -> void:
	controller = source
	allow_advance = can_advance
	_build()

func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _build() -> void:
	var state: Dictionary = controller.snapshot()
	var nodes: Array = state.get("route", {}).get("nodes", [])
	var current: int = int(state.get("node_index", 0))
	var completed: Array = state.get("completed_nodes", [])
	for index in nodes.size():
		var node: Dictionary = nodes[index]
		var at := Vector2(index * 127, 0)
		var tile := MineStyle.panel(self, at, Vector2(117, 70))
		tile.name = "RouteNode" + str(index)
		var accent := MineStyle.GREEN if completed.has(index) else (MineStyle.AMBER if index == current else MineStyle.MUTED)
		MineStyle.literal(tile, "%02d" % (index+1), Vector2(10,6), Vector2(31,26), 21, accent)
		var role := str(node.get("role", ""))
		var role_name: String = (ROLE_EN if Words.locale == "en" else ROLE_ZH).get(role, role)
		MineStyle.literal(tile, role_name, Vector2(10,35), Vector2(99,27), 15, accent)
		var marker := "✓" if completed.has(index) else ("●" if index == current else "·")
		MineStyle.literal(tile, marker, Vector2(85,7), Vector2(24,26), 18, accent)
	var current_node: Dictionary = controller.current_node()
	MineStyle.literal(self, _t("当前 ", "CURRENT ") + str(current+1) + "/8 · " + str(current_node.get("name", "")), Vector2(0,85), Vector2(990,34), 23, MineStyle.INK)
	var ready: bool = controller.current_complete()
	var explanation := _t("完成当前房间主目标与敌群后，在出口选择下一站。", "Complete this room's objective and enemies, then choose at the exit.")
	if ready:
		explanation = _t("选择后锁定路线。生命、资源与剩余技能冷却延续到下一房。", "Your choice locks the route. Health, resource and cooldowns carry forward.")
	MineStyle.literal(self, explanation, Vector2(0,123), Vector2(1000,46), 17, MineStyle.MUTED)
	var next: Dictionary = controller.next_node()
	if next.is_empty():
		MineStyle.literal(self, _t("远征终点 · 击败首领后从升降台带回战利品。", "Expedition endpoint · defeat the boss and extract with your loot."), Vector2(0,193), Vector2(1000,120), 23, MineStyle.AMBER)
	else:
		_build_options(next, ready)
	var close := MineStyle.button(self, "BACK", Vector2(790,428), Vector2(214,48), func(): close_requested.emit())
	close.name = "CloseRoute"
	close.grab_focus()
	if allow_advance and controller.can_extract():
		var exit_button := MineStyle.button(self, "", Vector2(0,428), Vector2(286,48), func(): early_extract_requested.emit())
		exit_button.name = "RouteEarlyExtract"
		exit_button.text = _t("带回战利品 · 撤离", "Extract with loot")
	elif not ready:
		MineStyle.literal(self, _t("主目标未完成，出口尚未开放", "Exit closed until the objective is complete"), Vector2(0,434), Vector2(750,36), 17, MineStyle.MUTED)

func _build_options(next: Dictionary, ready: bool) -> void:
	var options: Array = controller.next_options()
	MineStyle.literal(self, _t("下一站 · ", "NEXT · ") + (_t("选择路线", "Choose a route") if options.size()>1 else _t("必经节点", "Required stop")), Vector2(0,174), Vector2(1000,30), 18, MineStyle.CYAN)
	var scroll := ScrollContainer.new()
	scroll.name = "RouteOptions"
	scroll.position = Vector2(0,211)
	scroll.size = Vector2(1008,201)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	scroll.add_child(grid)
	for option: String in options:
		var preview: Dictionary = controller.preview(option)
		var card := Button.new()
		card.name = "Choose_" + option
		card.custom_minimum_size = Vector2(486,190)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.disabled = not (allow_advance and ready)
		card.tooltip_text = str(preview.get("risk", "")) + "\n" + str(preview.get("reward", ""))
		if preview.has("scanned_roster"):
			card.tooltip_text += "\n" + _t("已扫描敌群：", "Scanned enemies: ") + " / ".join(preview.scanned_roster)
		grid.add_child(card)
		MineStyle.literal(card, str(preview.get("name", option)), Vector2(16,10), Vector2(452,29), 21, MineStyle.AMBER)
		var objective := str(preview.get("objective", ""))
		if objective.is_empty():
			objective = _t("安全整备 · 用本局金币购买补给", "Safe stop · buy supplies with carried gold") if next.get("role", "") == "supply" else _t("区域首领 · 三阶段战斗与最终撤离", "Area boss · phase battle and final extraction")
		var goal := MineStyle.literal(card, objective, Vector2(16,46), Vector2(452,46), 16, MineStyle.INK)
		goal.max_lines_visible = 2
		goal.clip_text = true
		var tags: Array[String] = []
		for tag: String in preview.get("enemy_tags", []):
			tags.append(str(ENEMY_ZH.get(tag, tag)) if Words.locale != "en" else tag.capitalize())
		var risk := str(preview.get("risk", ""))
		var threat := _t("敌群：", "ENEMIES: ") + " / ".join(tags.slice(0,4)) if not tags.is_empty() else _t("无普通敌群", "No normal encounters")
		if preview.has("scanned_roster"):
			threat = _t("已扫描 · 悬停查看完整敌群", "SCANNED · Hover for the full enemy roster")
		MineStyle.literal(card, threat, Vector2(16,94), Vector2(452,25), 15, MineStyle.CYAN)
		var risk_label := MineStyle.literal(card, _t("风险：", "RISK: ")+risk, Vector2(16,121), Vector2(452,26), 14, MineStyle.MUTED)
		risk_label.max_lines_visible = 1
		risk_label.clip_text = true
		var reward_label := MineStyle.literal(card, _t("收益：", "REWARD: ")+str(preview.get("reward", _t("整备 / 首领奖励", "Supplies / boss reward"))), Vector2(16,151), Vector2(452,31), 14, MineStyle.GREEN)
		reward_label.max_lines_visible = 1
		reward_label.clip_text = true
		card.pressed.connect(func():
			if submitted:
				return
			submitted = true
			for sibling in grid.get_children():
				if sibling is BaseButton:
					sibling.disabled = true
			choice_requested.emit(option))
