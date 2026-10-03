extends Control
## Expedition field journal, built only from committed route state.
signal choice_requested(room_id: String)
signal close_requested()
signal early_extract_requested()

const JourneyArt = preload("res://scripts/presentation/components/route_journey_art.gd")
const ChoiceCard = preload("res://scripts/presentation/components/route_choice_card.gd")
const Layouts = preload("res://scripts/domain/world/fixed_room_layouts.gd")
const ENEMY_ZH := {"melee":"近战", "charger":"冲锋", "ranged":"射手", "swarm":"虫群", "cover_support":"掩体", "displacement":"牵引", "defender":"盾卫", "support":"支援", "artillery":"抛射", "summoner":"召唤", "flanker":"侧袭", "ambusher":"伏击", "controller":"控场", "healer":"治疗"}
var controller: RefCounted
var allow_advance := false
var submitted := false

func configure(source: RefCounted, can_advance: bool) -> void:
	controller = source
	allow_advance = can_advance
	submitted = false
	for child: Node in get_children(): child.free()
	_build()

func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _catalog_name(room_id: String, role: String = "", fallback: String = "") -> String:
	var definition: Dictionary = WorldCatalog.room(room_id)
	if definition.is_empty(): definition = WorldCatalog.bosses().get(room_id,{})
	if definition.is_empty() and (room_id.begins_with("service_") or role in ["entrance","supply"]):
		definition = WorldCatalog.services().get(role if not role.is_empty() else room_id.trim_prefix("service_"),{})
	return GameStyle.content_text(definition,"name",fallback if not fallback.is_empty() else room_id)

func _binding(action: String) -> String:
	var overrides: Dictionary = Game.profile.get("settings",{}).get("controls",{})
	return ControlBindings.label_for(action, overrides, "en" if Words.locale == "en" else "zh_CN")

func _build() -> void:
	var state: Dictionary = controller.snapshot()
	var nodes: Array = state.get("route", {}).get("nodes", [])
	var current: int = int(state.get("node_index", 0))
	var completed: Array = state.get("completed_nodes", [])
	var route_scroll := ScrollContainer.new()
	route_scroll.name = "RouteTimeline"
	route_scroll.position = Vector2.ZERO
	route_scroll.size = Vector2(1008,108)
	route_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	route_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	route_scroll.follow_focus = true
	add_child(route_scroll)
	var timeline := JourneyArt.new()
	timeline.name = "JourneyMap"
	timeline.nodes = nodes
	timeline.current = current
	timeline.completed = completed
	timeline.custom_minimum_size = Vector2(maxf(1008,nodes.size()*JourneyArt.STEP-13),100)
	route_scroll.add_child(timeline)
	route_scroll.set_deferred("scroll_horizontal",maxi(0,int(current*JourneyArt.STEP-440)))
	var current_node: Dictionary = controller.current_node()
	var current_name := _catalog_name(str(current_node.get("room_id","")),str(current_node.get("role","")),str(current_node.get("name","")))
	var progress := GameStyle.literal(self, _t("当前位置  ", "YOU ARE HERE  ")+"%02d / %02d  ·  " % [current+1,nodes.size()]+current_name,Vector2(0,112),Vector2(775,30),20,GameStyle.INK)
	progress.name = "RouteProgress"
	if nodes.size() > 8:
		GameStyle.literal(self,_t("横向滚动查看全程 →", "Scroll for the full journey →"),Vector2(777,115),Vector2(230,25),13,GameStyle.MUTED)
	var ready: bool = controller.current_complete()
	var explanation := _t("完成当前房间目标与敌群后，按 "+_binding("expedition_map")+" 选择下一站。", "Finish the objective and enemies, then press "+_binding("expedition_map")+" to choose the next room.")
	if ready:
		explanation = _t("选择下一站出发 · 生命、资源与剩余技能冷却延续到下一房。", "Choose your next stop. Health, resource and remaining cooldowns carry forward.") if allow_advance else _t("本房已完成 · 前往出口按 "+_binding("interact")+" 选择下一站。", "Room complete · press "+_binding("interact")+" at the exit to choose the next room.")
	GameStyle.literal(self,explanation,Vector2(0,145),Vector2(1008,31),15,GameStyle.MUTED)
	var next: Dictionary = controller.next_node()
	if next.is_empty(): _build_endpoint(current_node)
	else: _build_options(next,ready,state)
	var close := GameStyle.button(self,"BACK",Vector2(790,429),Vector2(214,47),func(): close_requested.emit())
	close.name = "CloseRoute"
	close.grab_focus()
	if allow_advance and controller.can_extract():
		var exit_button := GameStyle.button(self,"",Vector2(0,429),Vector2(286,47),func(): early_extract_requested.emit())
		exit_button.name = "RouteEarlyExtract"
		exit_button.text = _t("带回战利品 · 撤离", "Extract with loot")
		GameStyle.primary(exit_button)
	elif not ready:
		GameStyle.literal(self,_t("主目标未完成，出口尚未开放", "Exit closed until the objective is complete"),Vector2(0,438),Vector2(750,29),15,GameStyle.MUTED)

func _build_endpoint(current_node: Dictionary) -> void:
	var marker := JourneyArt.new()
	marker.position = Vector2(455,188)
	marker.size = Vector2(100,100)
	marker.nodes = [{"role":"boss"}]
	marker.current = 0
	add_child(marker)
	var heading := GameStyle.literal(self,_t("远征终点", "JOURNEY'S END"),Vector2(0,294),Vector2(1008,37),25,GameStyle.AMBER)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := GameStyle.literal(self,_t("击败首领后，从升降台撤离并带回战利品。", "Defeat the boss, then use the extraction lift to keep your loot."),Vector2(100,342),Vector2(808,58),17,GameStyle.INK)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.tooltip_text = _catalog_name(str(current_node.get("room_id","")),"boss")

func _build_options(next: Dictionary, ready: bool, state: Dictionary) -> void:
	var options: Array = controller.next_options()
	var heading := GameStyle.literal(self,_t("下一站  ·  ", "NEXT STOP  ·  ")+(_t("选择路线", "Choose your path") if options.size()>1 else _t("必经节点", "Required stop")),Vector2(0,177),Vector2(1008,23),16,GameStyle.CYAN)
	heading.name = "RouteOptionsHeading"
	var scroll := ScrollContainer.new()
	scroll.name = "RouteOptions"
	scroll.position = Vector2(0,203)
	scroll.size = Vector2(1008,213)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",10)
	scroll.add_child(grid)
	for index: int in options.size():
		var option := str(options[index])
		var preview: Dictionary = controller.preview(option)
		var risk := GameStyle.content_text(preview,"risk","")
		var card := ChoiceCard.new()
		card.name = "Choose_"+option
		card.custom_minimum_size = Vector2(488,203)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.disabled = not (allow_advance and ready)
		card.role = str(next.get("role","branch"))
		card.preview_index = index
		var definition: Dictionary = WorldCatalog.room(option)
		if definition.is_empty(): definition = WorldCatalog.bosses().get(option,{})
		var biome := str(definition.get("biome_id",next.get("biome_id",state.get("route",{}).get("biome_id","B01"))))
		card.scene_texture = WorldArt.environment_texture_for(biome,option)
		# Service stops have no room painting; show their actual ground rather
		# than the empty placeholder used when the old faction art was retired.
		if card.scene_texture == null: card.scene_texture = WorldArt.floor_texture_for(biome)
		var blueprint: Dictionary = Layouts.blueprint(option)
		var landmark: Dictionary = blueprint.get("landmark",{})
		if not landmark.is_empty(): card.landmark_texture = WorldPropArt.texture_for_asset(biome+"_prop_"+str(landmark.get("key","")))
		card.tooltip_text = risk+"\n"+str(preview.get("reward",""))
		if preview.has("scanned_roster"):
			card.tooltip_text += "\n"+_t("已扫描敌群：", "Scanned enemies: ")+" / ".join(preview.scanned_roster)
		grid.add_child(card)
		var title := _option_label(card,"RouteTitle",_catalog_name(option,str(next.get("role","")),str(preview.get("name",option))),11,18,GameStyle.AMBER)
		var cursor_y := title.position.y+title.size.y+5.0
		var objective := GameStyle.content_text(preview,"objective","")
		if objective.is_empty():
			objective = _t("安全整备 · 用本局金币购买补给", "Safe stop · buy supplies with carried gold") if next.get("role","")=="supply" else _t("区域首领 · 三阶段战斗与最终撤离", "Area boss · phase battle and final extraction")
		var goal := _option_label(card,"RouteObjective",objective,cursor_y,14,GameStyle.INK)
		cursor_y = goal.position.y+goal.size.y+4.0
		var tags: Array[String] = []
		for tag: String in preview.get("enemy_tags",[]): tags.append(str(ENEMY_ZH.get(tag,tag)) if Words.locale!="en" else tag.capitalize())
		var threat := _t("敌群  ", "ENEMIES  ")+" / ".join(tags.slice(0,4)) if not tags.is_empty() else _t("无普通敌群", "No normal encounters")
		if preview.has("scanned_roster"): threat = _t("已扫描 · 悬停查看完整敌群", "Scanned · hover for the full roster")
		var enemies := _option_label(card,"RouteEnemies",threat,cursor_y,12,GameStyle.CYAN)
		cursor_y = enemies.position.y+enemies.size.y+7.0
		var reward := str(preview.get("reward",""))
		if reward.is_empty(): reward = _t("补给购买与修复", "Supplies and repairs") if next.get("role","")=="supply" else _t("首领奖励 · 装备需撤离带回", "Boss rewards · extract to keep equipment")
		var reward_label := _option_label(card,"RouteReward",reward,cursor_y,13 if Words.locale=="en" else 14,GameStyle.GREEN)
		cursor_y = reward_label.position.y+reward_label.size.y+6.0
		if not risk.is_empty():
			var risk_label := _option_label(card,"RouteRisk",_t("风险  ", "RISK  ")+risk,cursor_y,12,GameStyle.MUTED)
			cursor_y = risk_label.position.y+risk_label.size.y
		card.custom_minimum_size.y = maxf(203.0,cursor_y+12)
		card.pressed.connect(func():
			if submitted: return
			submitted = true
			for sibling: Node in grid.get_children():
				if sibling is BaseButton: sibling.disabled = true
			choice_requested.emit(option))

func _option_label(card: Control, node_name: String, value: String, at_y: float, font_size: int, color: Color) -> Label:
	var label := GameStyle.literal(card,value,Vector2(144,at_y),Vector2(332,0),font_size,color)
	label.name = node_name
	label.max_lines_visible = -1
	label.clip_text = false
	label.size.y = ceilf(label.get_minimum_size().y)
	return label
