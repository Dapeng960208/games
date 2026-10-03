extends "res://scripts/presentation/hud/hud.gd"
## Existing combat instruments, with only the isolated B09 route readout changed.
const CandidateContent = preload("res://scripts/levels/b09/world/content.gd")
var candidate_route: RefCounted

func _apply_layout() -> void:
	super()
	if is_instance_valid(room_identity_plate): room_identity_plate.hide()
	if is_instance_valid(gold_label): gold_label.hide()
	if is_instance_valid(location_panel): location_panel.size.y=64

func _update_growth() -> void:
	experience_label.hide()
	experience_bar.hide()
	progression_button.hide()

func _update_quest_and_route() -> void:
	if not is_instance_valid(room) or candidate_route==null: return
	var definition: Dictionary=CandidateContent.room(room.layout_id)
	region_label.text=str(definition.get("name",room.layout_id))
	var current: int=candidate_route.node_index+1
	var count: int=CandidateContent.room_ids().size()
	expedition_label.text="B09 · D%d · %d/%d" % [candidate_route.difficulty,current,count]
	expedition_beads.current=current
	expedition_beads.count=count
	expedition_beads.queue_redraw()
	var living: int=room._living_enemy_count()
	if candidate_route.finished:
		quest_full_action="霜晶王庭已完成"
	elif Game.run.hp<=0:
		quest_full_action="角色倒下 · 返回职业选择重新开始"
	elif room.objective_complete:
		quest_full_action="清房完成 · %s 前往出口" % Bindings.label_for("interact",Game.profile.get("settings",{}).get("controls",{}),Words.locale)
	elif room.layout_id=="BO09":
		quest_full_action="击败霜晶女王及其召唤物"
	elif living>0:
		quest_full_action="清理当前遭遇区域"
	else:
		quest_full_action="进入下一遭遇区域"
	objective_label.text=quest_full_action
	objective_label.tooltip_text=quest_full_action
	objective_label.size.y=48
	objective_label.max_lines_visible=2
	objective_label.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	quest_progress.text="场内敌人 %d" % living
	if room.layout_id!="BO09":
		quest_progress.text+=" · 已触发 %d/%d" % [room.activated_encounters.size(),room.encounter_zones.size()]
	quest_progress.position.y=94
	quest_reward.text="清房装备自动存入行囊"
	quest_reward.tooltip_text="击杀与清房装备自动保存到 B09 隔离行囊。"
	quest_reward.position.y=119
	quest_panel.size.y=146
	quest_panel.position=Vector2(screen_size.x-quest_panel.size.x-12,maxf(164,minf(screen_size.y*.45,equipment_actions.position.y-quest_panel.size.y-16)))
	quest_button.size.y=quest_panel.size.y-36
	quest_panel.set("reward_bullet_y",quest_reward.position.y+11)
	quest_panel.queue_redraw()

func _update_navigation() -> void:
	if is_instance_valid(navigation): navigation.hide()

func _update_tooltip() -> void:
	super()
	if active_detail_slot!="quest" or not tooltip_panel.visible: return
	tooltip_body.text=quest_full_action+"\n"+quest_progress.text+"\n\n击杀与清房装备自动保存到 B09 隔离行囊。\nLv45 候选试玩，正式主线进度保持隔离。"
	var line_height: float=tooltip_body.get_theme_font("font").get_height(16)+tooltip_body.get_theme_constant("line_spacing")
	tooltip_panel.size.y=minf(screen_size.y-32,maxf(164,ceilf(tooltip_body.get_line_count()*line_height)+64))
	tooltip_body.size.y=tooltip_panel.size.y-54
	tooltip_body.max_lines_visible=maxi(1,floori(tooltip_body.size.y/line_height))
	tooltip_panel.position.y=clampf(tooltip_panel.position.y,16,screen_size.y-tooltip_panel.size.y-16)
