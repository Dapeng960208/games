extends "res://scripts/presentation/hud/hud.gd"
## Existing combat instruments with B08's finite-wave, non-settling readout.
const SkyContent = preload("res://scripts/levels/b08/content.gd")
const SkyGeometry = preload("res://scripts/levels/b08/geometry.gd")
var last_live_state: Dictionary = {}
var finished_result: Dictionary = {}

func _ready() -> void:
	super._ready()
	# Lethal damage emits changed while the real run still contains HP=0,
	# before finish_run restores the demo profile and clears Game.run.
	Game.changed.connect(refresh)

func refresh() -> void:
	if Game.run == null or not finished_result.is_empty(): return
	last_live_state = {"run_id":Game.run.id,"hp":Game.run.hp,"max_hp":Game.run.max_hp,
		"shield":Game.run.shield,"resource":Game.run.resource}
	super.refresh()

func show_finished(result: Dictionary) -> void:
	if str(result.get("run_id","")) != str(last_live_state.get("run_id","")): return
	finished_result = {"run_id":result.run_id,"outcome":result.get("outcome","")}
	# These are read-only scalar observations, never a replacement RunSession.
	var lethal: Dictionary = result.get("death_review",{}).get("lethal_event",{})
	var hp: float = lethal.get("hp_after",last_live_state.get("hp",0.0))
	var shield: float = lethal.get("shield_after",last_live_state.get("shield",0.0))
	health_label.text = Words.text("HUD_HP_COMPACT",{"hp":ceili(hp),"max":ceili(float(last_live_state.get("max_hp",0.0)))})
	health_bar.value = hp
	shield_label.text = "+"+str(ceili(shield)) if shield > 0 else ""
	shield_bar.value = shield
	shield_bar.visible = shield > 0
	guard_icon.visible = shield > 0
	quest_full_action = ("Defeated · Esc to close" if Words.locale == "en" else "已倒下 · Esc 关闭试玩") if str(result.get("outcome","")) == "death" else ("Trial ended · Esc to close" if Words.locale == "en" else "试玩已结束 · Esc 关闭")
	objective_label.text = quest_full_action
	objective_label.tooltip_text = quest_full_action
	quest_progress.text = "Candidate ended" if Words.locale == "en" else "候选试玩已结束"
	quest_reward.text = _reward_caption("")
	for control: Control in [buff_row,hit_chain_readout,navigation,boss_cast_plate,hint_label,toast,tooltip_panel]:
		control.hide()
	set_interaction_enabled(false)
	for button: BaseButton in find_children("*","BaseButton",true,false): button.disabled = true
	set_process(false)

func wave_status() -> Dictionary:
	var total: int = room._authored_waves.size()
	var spawned := clampi(int(room._next_wave),0,total)
	var alive: int = room._living_combatants()
	return {"total":total,"spawned":spawned,"alive":alive,
		"completed":maxi(0,spawned-(1 if alive > 0 else 0)),"exit_ready":room.exit_ready()}

func _reward_caption(_quality: String) -> String:
	return "No rewards · no saves" if Words.locale == "en" else "无奖励 · 不保存"

func _update_quest_and_route() -> void:
	# Retain the shared layout, player avoidance, tooltip and route controls.
	super._update_quest_and_route()
	var state := wave_status()
	var english := Words.locale == "en"
	var defeated: bool = Game.run.hp <= 0
	quest_full_action = ("Defeated · Esc to close" if english else "已倒下 · Esc 关闭试玩") if defeated else (("Clear · go to the exit" if english else "已清场 · 前往出口") if state.exit_ready else ("Clear the bridge defenders" if english else "清理守桥敌群，开放出口"))
	objective_label.text = quest_full_action
	objective_label.tooltip_text = quest_full_action
	objective_bar.max_value = maxi(1,int(state.total))
	objective_bar.value = state.completed
	quest_progress.text = ("Waves %d/%d · Enemies %d" if english else "波次 %d/%d · 剩余敌人 %d") % [state.completed,state.total,state.alive]
	quest_reward.text = _reward_caption("")
	quest_reward.tooltip_text = quest_reward.text
	expedition_label.text = ("Candidate · %s" if english else "候选试玩 · %s") % room.layout_id
	expedition_beads.count = maxi(1,int(state.total))
	expedition_beads.current = state.spawned
	expedition_beads.queue_redraw()
	# Reflow the same quest ribbon after replacing its production-only copy.
	var line_height := objective_label.get_theme_font("font").get_height(17)+objective_label.get_theme_constant("line_spacing")
	objective_label.size.y = maxf(23,ceilf(mini(objective_label.max_lines_visible,objective_label.get_line_count())*line_height)+2)
	quest_progress.show()
	quest_progress.position.y = objective_label.position.y+objective_label.size.y+2
	quest_reward.position.y = quest_progress.position.y+25
	quest_panel.size.y = maxf(110,quest_reward.position.y+26)
	quest_panel.set("reward_bullet_y",quest_reward.position.y+11)
	quest_button.size.y = quest_panel.size.y-36
	quest_panel.queue_redraw()

func _update_room_identity() -> void:
	region_label.text = str(SkyContent.room(room.layout_id).get("name",room.layout_id))
	var display_layout: Dictionary = room.layout.duplicate(true)
	display_layout["room_id"] = room.layout_id
	display_layout["blueprint_room_id"] = room.layout_id
	display_layout["objective_points"] = []
	for lane: Dictionary in SkyGeometry.lanes(room.layout_id):
		display_layout.objective_points.append(lane.vane)
	room_identity_plate.configure(display_layout,region_label.text)
	room_purpose = "B08 · isolated combat candidate" if Words.locale == "en" else "B08 浮羽空港 · 独立战斗候选"
	room_identity_plate.design = {"chapter":8,"emblem":"wing"}
	room_identity_plate.room_caption.text = room_purpose
	# B08 has no shared WorldCatalog terrain. Never show its fallback rectangle
	# as legal ground; the existing sketch still maps real entry/vane/exit/player.
	room_identity_plate.ground_polygon = PackedVector2Array()
	room_identity_plate.map_bounds = room.ARENA
	room_identity_plate.update_player(room.player.global_position if is_instance_valid(room.player) else Vector2.ZERO,is_instance_valid(room.player))
	room_identity_plate.queue_redraw()
	quest_panel.set("room_emblem","wing")
	quest_panel.set("room_accent",room_identity_plate.accent)
	quest_panel.set("room_chapter",8)

func _update_tooltip() -> void:
	if not finished_result.is_empty(): return
	super._update_tooltip()
	if tooltip_panel == null or not tooltip_panel.visible: return
	match active_detail_slot:
		"quest":
			tooltip_body.text = room_purpose+"\n\n"+quest_full_action+"\n"+quest_progress.text+"\n"+quest_reward.text+"\n\n"+("Sketch: entrance, wind vane, exit and live player position." if Words.locale == "en" else "小图标示入口、风标、出口与角色实时位置。")
		"progression":
			tooltip_body.text = hero_label.text+"\n"+class_label.text+"\n\n"+_reward_caption("")
		"wallet":
			tooltip_body.text = _reward_caption("")
		"inventory":
			tooltip_body.text = "Press B to inspect trial equipment and live attributes. Combat pauses; this candidate has no equipment changes or saves." if Words.locale == "en" else "按 B 查看试玩装备与实时属性。打开时暂停战斗；本候选不换装、不保存。"
