extends RefCounted
## Playable gear and clear rewards in the explicitly isolated B09 profile.
## This uses the existing instance generator, resolver and atomic profile store.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Details = preload("res://scripts/presentation/equipment/equipment_details.gd")
var room: Node2D
var last_error := ""
var receipts: Dictionary = {}
var panel: PanelContainer
var list: ItemList
var details: VBoxContainer
var message: Label
var ids: Array[String] = []
var selected := ""
var equip_button: Button
var unequip_button: Button
var _blocked_before := false
var _pending_items: Dictionary = {}
var _kill_counts: Dictionary = {}
var _cleared: Dictionary = {}

func configure() -> bool:
	if not Rules.b09_candidate_enabled() or not Game.profile_path.begins_with("user://test_b09_candidate/") or Game.run == null:
		last_error="B09 装备只允许在隔离候选中使用。"
		return false
	Game.run.loadout_snapshot={}
	Game.run.equipment_snapshot=Game.profile.equipment.duplicate(true)
	var stats := Resolver.resolve(Game.run.hero_id,45,{},Game.run.equipment_snapshot,2)
	if stats.is_empty(): last_error="Lv45 装备属性解析失败。"; return false
	Game.run.stats=stats
	Game.run.level=45
	Game.run.max_hp=float(stats.max_hp)
	Game.run.hp=Game.run.max_hp
	Game.run.resource=float(stats.starting_resource)
	return true

func grant_catalog() -> bool:
	if not Rules.b09_candidate_enabled() or Game.run==null: return false
	var candidate := Game.profile.duplicate(true)
	for entries: Array in Acquisition.natural_pool("B09",Game.run.hero_id,5).values():
		for template: String in entries:
			var id := "b09_catalog:%s:%s" % [Game.run.hero_id,template]
			if candidate.equipment.has(id): continue
			var item := Acquisition.roll_item({"instance_id":id,"source_event_id":id,"template_id":template,"rarity":"purple","power_type":"magic" if Game.run.hero_id=="CH03" else "physical","item_level":45,"source":"drop","location":"inventory","hero_id":Game.run.hero_id},309)
			if item.is_empty(): last_error="测试装备生成失败："+template; return false
			candidate.equipment[id]=item
	return _commit(candidate)

func clear_reward(id: String, difficulty: int, seed_value: int) -> bool:
	if not Rules.b09_candidate_enabled() or Game.run==null or id not in Content.room_ids(): return false
	var event := "b09_clear:%s:%s" % [Game.run.id,id]
	var context := {"event_id":event,"seed":seed_value,"source":"boss" if id=="BO09" else "room","race_id":"B09","difficulty":difficulty,"challenge_level":int(Content.room(id).enemy_level),"power_type":"magic" if Game.run.hero_id=="CH03" else "physical","hero_id":Game.run.hero_id,"room_id":id,"force_gold":id=="BO09" and difficulty==4 and int(Game.profile.get("gold_pity",{}).get("B09",0))>=3}
	if receipts.has(event): context.force_gold=bool(receipts[event].context.force_gold)
	var result := Acquisition.roll_event(context,receipts.get(event,{}))
	if not bool(result.get("ok",false)): last_error="B09 掉落失败："+str(result.get("error","")); return false
	if _cleared.has(event): return true
	# Freeze before the write, so a failed commit can retry without rerolling.
	receipts[event]=result.duplicate(true)
	for item: Dictionary in result.items:
		_pending_items[item.instance_id]=item.duplicate(true)
	var candidate := _with_pending()
	if candidate.is_empty(): return false
	if id=="BO09" and difficulty==4:
		var gold := false
		for item: Dictionary in result.items: gold=gold or item.rarity=="gold"
		candidate.gold_pity["B09"]=0 if gold else mini(3,int(candidate.gold_pity.get("B09",0))+1)
	if not _commit(candidate): return false
	_pending_items.clear()
	_cleared[event]=true
	if is_instance_valid(message): message.text="%s 清场：获得 %d 件装备，已保存到隔离行囊。" % [Content.room(id).name,result.items.size()]
	return true

func kill_reward(actor: Node2D) -> bool:
	if Game.run==null or not str(actor.enemy_id).begins_with("B09-M") or actor.owner_enemy!=null or bool(actor.get_meta("b09_no_rewards",false)) or actor.reward_spawn_id.is_empty(): return true
	var source := "elite" if actor.rank=="elite" else "normal"
	var event := "b09_kill:%s:%s:%s" % [Game.run.id,room.layout_id,actor.reward_spawn_id]
	if receipts.has(event): return true
	var context := {"event_id":event,"seed":room.layout_seed,"source":source,"race_id":"B09","difficulty":room.difficulty,"challenge_level":int(Content.room(room.layout_id).enemy_level),"power_type":"magic" if Game.run.hero_id=="CH03" else "physical","hero_id":Game.run.hero_id,"room_id":room.layout_id,"monster_id":actor.enemy_id}
	var result := Acquisition.roll_event(context)
	if not bool(result.get("ok",false)): last_error="击杀装备生成失败："+str(result.get("error","")); return false
	receipts[event]=result.duplicate(true)
	var key: String=room.layout_id+":"+source
	if int(_kill_counts.get(key,0))>=(1 if source=="elite" else 2): return true
	_kill_counts[key]=int(_kill_counts.get(key,0))+result.items.size()
	for item: Dictionary in result.items: _pending_items[item.instance_id]=item.duplicate(true)
	if _pending_items.is_empty(): return true
	var candidate := _with_pending()
	if candidate.is_empty() or not _commit(candidate): return false
	_pending_items.clear()
	return true

func _with_pending() -> Dictionary:
	var candidate := Game.profile.duplicate(true)
	for item: Dictionary in _pending_items.values():
		var record := item.duplicate(true)
		record.location="inventory"
		if candidate.equipment.has(record.instance_id) and candidate.equipment[record.instance_id]!=record:
			last_error="装备实例来源冲突。"
			return {}
		candidate.equipment[record.instance_id]=record
	return candidate

func _commit(candidate: Dictionary) -> bool:
	if not Rules.b09_candidate_enabled() or Game.run==null or not Game.profile_path.begins_with("user://test_b09_candidate/"): return false
	if not Game.call("_save",candidate,null): last_error=Game.last_error; return false
	Game.profile=candidate
	Game.run.equipment_snapshot=candidate.equipment.duplicate(true)
	Game.changed.emit()
	return true

func equip(id: String, slot: String = "") -> bool:
	if not is_instance_valid(room) or Game.run==null or Game.run.hp<=0: return false
	var owned: Dictionary=Game.run.equipment_snapshot
	if not id.is_empty():
		if not owned.has(id) or not Instances.can_equip(owned[id],Game.run.hero_id,45): return false
		slot=str(ContentRegistry.equipment(owned[id].template_id,2).slot)
	if slot not in ContentRegistry.slots(2): return false
	var old: Dictionary=Game.run.loadout_snapshot.duplicate(true)
	var next := old.duplicate(true)
	if id.is_empty(): next.erase(slot)
	else: next[slot]=id
	var stats := Resolver.resolve(Game.run.hero_id,45,next,owned,2)
	if stats.is_empty(): last_error="装备属性解析失败。"; return false
	var runtime := Snapshot.capture(room)
	var adjusted := Snapshot.for_loadout(runtime,old,next,stats,Game.run.hero_id,Game.run.stats)
	if adjusted.is_empty(): last_error="换装状态校验失败，请等待当前效果结束。"; return false
	var position_before: Vector2=room.player.position
	var history: Dictionary={}
	var effects: RefCounted=room.player.loadout.effects
	for key: String in ["roots","deaths","first_full_targets","cooldowns"]: history[key]=effects.get(key).duplicate(true)
	Game.run.loadout_snapshot=next
	Game.run.stats=stats
	Game.run.max_hp=float(stats.max_hp)
	if not Snapshot.restore(room,adjusted):
		last_error="装备状态恢复失败。"
		return false
	room.player.position=position_before
	for key: String in history: effects.set(key,history[key])
	for root: Dictionary in effects.roots.values():
		root.erase("pending_context")
		root.erase("pending_stage")
	room.player.loadout.refresh_modifiers()
	Game.changed.emit()
	return true

func attach_room(host: Node2D) -> void:
	room=host
	room.set_meta("b09_inventory",self)
	room.room_completed.connect(func():
		if not clear_reward(room.layout_id,room.difficulty,room.layout_seed): message.text=last_error)
	var canvas := CanvasLayer.new()
	canvas.layer=5
	room.add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=GameStyle.make_theme()
	canvas.add_child(ui)
	var open := Button.new()
	open.name="B09EquipmentOpen"
	open.text="装备与战利品"
	open.position=Vector2(12,132)
	open.pressed.connect(_open)
	ui.add_child(open)
	panel=PanelContainer.new()
	panel.name="B09EquipmentPanel"
	panel.custom_minimum_size=Vector2(1000,584)
	ui.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left=-500
	panel.offset_top=-292
	panel.offset_right=500
	panel.offset_bottom=292
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	panel.add_child(box)
	var title := Label.new()
	title.text="B09 装备 · 换装保持生命、资源与冷却消耗"
	title.add_theme_font_size_override("font_size",22)
	box.add_child(title)
	message=Label.new()
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.text="清房自动拾取并保存到隔离行囊；测试装备按钮提供本职业完整19件。正式库存不受影响。"
	box.add_child(message)
	var row := HBoxContainer.new()
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(row)
	list=ItemList.new()
	list.name="B09InventoryList"
	list.custom_minimum_size=Vector2(340,390)
	list.add_theme_color_override("font_color",Color("48374b"))
	list.add_theme_color_override("font_selected_color",Color("fff8ee"))
	var list_background := StyleBoxFlat.new()
	list_background.bg_color=Color("f4eadc")
	list.add_theme_stylebox_override("panel",list_background)
	var selection := StyleBoxFlat.new()
	selection.bg_color=Color("397d80")
	list.add_theme_stylebox_override("selected",selection)
	list.add_theme_stylebox_override("selected_focus",selection)
	list.item_selected.connect(func(index: int): selected=ids[index]; _detail())
	row.add_child(list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(630,390)
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	details=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(details)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	equip_button=_button(actions,"穿戴选中装备",func():
		if equip(selected): message.text="换装已生效；当前配装仅本局使用。"; _refresh()
		else: message.text=last_error)
	unequip_button=_button(actions,"卸下同槽装备",func():
		if not selected.is_empty() and equip("",str(ContentRegistry.equipment(Game.run.equipment_snapshot[selected].template_id,2).slot)): _refresh())
	_button(actions,"领取19件测试装备",func():
		if grant_catalog(): message.text="已领取本职业8件＋共有8件＋散件3件；紫装iLv45，记录标注为测试来源。"; _refresh()
		else: message.text=last_error)
	_button(actions,"关闭并继续",_close)
	panel.hide()

func _button(host: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text=caption
	button.pressed.connect(action)
	host.add_child(button)
	return button

func _open() -> void:
	if not is_instance_valid(room): return
	_blocked_before=room.input_blocked
	room.set_input_blocked(true)
	_refresh()
	panel.show()

func _close() -> void:
	panel.hide()
	room.set_input_blocked(_blocked_before or Game.run.hp<=0)

func _refresh() -> void:
	list.clear()
	ids.clear()
	for id: String in Game.run.equipment_snapshot:
		var record: Dictionary=Game.run.equipment_snapshot[id]
		if not str(record.template_id).begins_with("B09-"): continue
		if Game.run.hero_id not in ContentRegistry.equipment(record.template_id,2).get("allowed_heroes",[]): continue
		ids.append(id)
	ids.sort()
	for id: String in ids:
		var record: Dictionary=Game.run.equipment_snapshot[id]
		var item := ContentRegistry.equipment(record.template_id,2)
		list.add_item(("✓ " if id in Game.run.loadout_snapshot.values() else "")+str(item.name)+" · "+("物理" if record.power_type=="physical" else "法术")+" · "+str(record.item_level))
	if not ids.has(selected): selected=ids[0] if not ids.is_empty() else ""
	if not selected.is_empty(): list.select(ids.find(selected))
	_detail()

func _detail() -> void:
	for child: Node in details.get_children(): child.free()
	equip_button.disabled=selected.is_empty()
	unequip_button.disabled=selected.is_empty()
	if selected.is_empty(): return
	var record: Dictionary=Game.run.equipment_snapshot[selected]
	var item := ContentRegistry.equipment(record.template_id,2)
	item["instance_record"]=record
	item["instance_id"]=selected
	var next: Dictionary=Game.run.loadout_snapshot.duplicate(true)
	next[item.slot]=selected
	var stats := Resolver.resolve(Game.run.hero_id,45,next,Game.run.equipment_snapshot,2)
	var title := Label.new()
	title.text=str(item.name)
	title.add_theme_font_size_override("font_size",22)
	details.add_child(title)
	var detail := Details.new()
	details.add_child(detail)
	detail.configure(item,int(record.enhancement_rank),600,Game.run.hero_id,Game.run.stats,stats)
	var compare := Details.new()
	details.add_child(compare)
	compare.configure(item,int(record.enhancement_rank),600,Game.run.hero_id,Game.run.stats,stats,"compare")
	var sets := Details.new()
	details.add_child(sets)
	sets.configure(item,int(record.enhancement_rank),600,Game.run.hero_id,Game.run.stats,stats,"set")
	var source := Label.new()
	source.text="来源："+str(record.source_event_id)
	source.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	details.add_child(source)
