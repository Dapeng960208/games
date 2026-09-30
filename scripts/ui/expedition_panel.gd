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

func _catalog_name(room_id: String, role: String = "", fallback: String = "") -> String:
	var definition: Dictionary = WorldCatalog.room(room_id)
	if definition.is_empty():
		definition = WorldCatalog.bosses().get(room_id,{})
	if definition.is_empty() and (room_id.begins_with("service_") or role in ["entrance","supply"]):
		definition = WorldCatalog.services().get(role if not role.is_empty() else room_id.trim_prefix("service_"),{})
	return MineStyle.content_text(definition,"name",fallback if not fallback.is_empty() else room_id)

func _build() -> void:
	var state: Dictionary = controller.snapshot()
	var nodes: Array = state.get("route", {}).get("nodes", [])
	var current: int = int(state.get("node_index", 0))
	var completed: Array = state.get("completed_nodes", [])
	var route_scroll := ScrollContainer.new()
	route_scroll.name = "RouteTimeline"
	route_scroll.position = Vector2.ZERO
	route_scroll.size = Vector2(1008,82)
	route_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	route_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	route_scroll.follow_focus = true
	add_child(route_scroll)
	var timeline := Control.new()
	timeline.custom_minimum_size = Vector2(maxf(1008,nodes.size()*127-10),70)
	route_scroll.add_child(timeline)
	for index in nodes.size():
		var node: Dictionary = nodes[index]
		var at := Vector2(index * 127, 0)
		var tile := MineStyle.panel(timeline, at, Vector2(117, 70))
		tile.name = "RouteNode" + str(index)
		var accent := MineStyle.GREEN if completed.has(index) else (MineStyle.AMBER if index == current else MineStyle.MUTED)
		if index == current:
			tile.add_theme_stylebox_override("panel",MineStyle.box(MineStyle.PANEL.lerp(MineStyle.AMBER,0.10),MineStyle.AMBER,2))
		elif completed.has(index):
			tile.add_theme_stylebox_override("panel",MineStyle.box(MineStyle.PANEL.lerp(MineStyle.GREEN,0.07),MineStyle.GREEN,1))
		MineStyle.literal(tile, "%02d" % (index+1), Vector2(10,6), Vector2(31,26), 21, MineStyle.INK)
		var role := str(node.get("role", ""))
		var role_name: String = (ROLE_EN if Words.locale == "en" else ROLE_ZH).get(role, role)
		MineStyle.literal(tile, role_name, Vector2(10,35), Vector2(99,27), 15, accent)
		var marker := "✓" if completed.has(index) else ("●" if index == current else "·")
		MineStyle.literal(tile, marker, Vector2(85,7), Vector2(24,26), 18, accent)
	var current_node: Dictionary = controller.current_node()
	route_scroll.set_deferred("scroll_horizontal",maxi(0,current*127-440))
	var current_name := _catalog_name(str(current_node.get("room_id","")),str(current_node.get("role","")),str(current_node.get("name","")))
	var progress := MineStyle.literal(self, _t("当前 ", "CURRENT ") + str(current+1) + "/"+str(nodes.size())+" · " + current_name, Vector2(0,88), Vector2(796,34), 23, MineStyle.INK)
	progress.name = "RouteProgress"
	if nodes.size() > 8:
		MineStyle.literal(self,_t("拖动上方横条查看全程", "Scroll the timeline for all stops"),Vector2(782,91),Vector2(226,29),14,MineStyle.MUTED)
	var ready: bool = controller.current_complete()
	var explanation := _t("完成当前房间主目标与敌群后，按 M 选择下一站。", "Finish the objective and enemies, then press M to choose the next room.")
	if ready:
		explanation = _t("点击下一站即可出发。生命、资源与剩余技能冷却延续到下一房。", "Choose a room to depart. Health, resource and cooldowns carry forward.") if allow_advance else _t("本房已完成 · 前往出口按 E 选择下一站。", "Room complete · interact with the exit to choose the next room.")
	MineStyle.literal(self, explanation, Vector2(0,123), Vector2(1000,32), 17, MineStyle.MUTED)
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
	var heading := MineStyle.literal(self, _t("下一站 · ", "NEXT · ") + (_t("选择路线", "Choose a route") if options.size()>1 else _t("必经节点", "Required stop")), Vector2(0,157), Vector2(1000,27), 18, MineStyle.CYAN)
	heading.name = "RouteOptionsHeading"
	var scroll := ScrollContainer.new()
	scroll.name = "RouteOptions"
	scroll.position = Vector2(0,190)
	scroll.size = Vector2(1008,226)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	scroll.add_child(grid)
	for option: String in options:
		var preview: Dictionary = controller.preview(option)
		var risk := MineStyle.content_text(preview,"risk","")
		var card := Button.new()
		card.name = "Choose_" + option
		card.custom_minimum_size = Vector2(486,190)
		card.set_script(load("res://scripts/ui/mine_button.gd"))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.disabled = not (allow_advance and ready)
		card.tooltip_text = risk + "\n" + str(preview.get("reward", ""))
		if preview.has("scanned_roster"):
			card.tooltip_text += "\n" + _t("已扫描敌群：", "Scanned enemies: ") + " / ".join(preview.scanned_roster)
		grid.add_child(card)
		var title := _option_label(card, "RouteTitle", _catalog_name(option,str(next.get("role","")),str(preview.get("name",option))), 14.0, 20, MineStyle.AMBER)
		var cursor_y := title.position.y + title.size.y + 3.0
		var objective := MineStyle.content_text(preview,"objective","")
		if objective.is_empty():
			objective = _t("安全整备 · 用本局金币购买补给", "Safe stop · buy supplies with carried gold") if next.get("role", "") == "supply" else _t("区域首领 · 三阶段战斗与最终撤离", "Area boss · phase battle and final extraction")
		var goal := _option_label(card, "RouteObjective", objective, cursor_y, 15, MineStyle.INK)
		cursor_y = goal.position.y + goal.size.y + 3.0
		var tags: Array[String] = []
		for tag: String in preview.get("enemy_tags", []):
			tags.append(str(ENEMY_ZH.get(tag, tag)) if Words.locale != "en" else tag.capitalize())
		var threat := _t("敌群：", "ENEMIES: ") + " / ".join(tags.slice(0,4)) if not tags.is_empty() else _t("无普通敌群", "No normal encounters")
		if preview.has("scanned_roster"):
			threat = _t("已扫描 · 悬停查看完整敌群", "SCANNED · Hover for the full enemy roster")
		var enemies := _option_label(card, "RouteEnemies", threat, cursor_y, 13, MineStyle.CYAN)
		cursor_y = enemies.position.y + enemies.size.y + 5.0
		var reward := str(preview.get("reward", ""))
		if reward.is_empty():
			reward = _t("补给购买与修复", "Supplies and repairs") if next.get("role", "") == "supply" else _t("首领奖励 · 装备需撤离带回", "Boss rewards · extract to keep equipment")
		# Preserve every condition and amount, including the extraction rule. The
		# policy has explicit lines; English may wrap further at the actual font.
		var reward_label := _option_label(card, "RouteReward", reward, cursor_y, 15, MineStyle.GREEN)
		cursor_y = reward_label.position.y + reward_label.size.y + 5.0
		if not risk.is_empty():
			var risk_label := _option_label(card, "RouteRisk", _t("风险：", "RISK: ")+risk, cursor_y, 13, MineStyle.MUTED)
			cursor_y = risk_label.position.y + risk_label.size.y
		card.custom_minimum_size.y = maxf(190.0, cursor_y + 10.0)
		card.pressed.connect(func():
			if submitted:
				return
			submitted = true
			for sibling in grid.get_children():
				if sibling is BaseButton:
					sibling.disabled = true
			choice_requested.emit(option))

func _option_label(card: Control, node_name: String, value: String, at_y: float, font_size: int, color: Color) -> Label:
	var label := MineStyle.literal(card, value, Vector2(16,at_y), Vector2(452,0), font_size, color)
	label.name = node_name
	label.max_lines_visible = -1
	label.clip_text = false
	# Measure with the inherited game font after parenting. Unlike a fixed one-
	# line rectangle, this remains legible for both Chinese and English rewards.
	label.size.y = ceilf(label.get_minimum_size().y)
	return label
