extends RefCounted
## Playable gear and clear rewards in the explicitly isolated B09 profile.
## This uses the existing instance generator, resolver and atomic profile store.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
const Art = preload("res://scripts/infrastructure/assets/equipment_art.gd")
const INK := Color("403449")
const MUTED := Color("7d7682")
const ACCENT := Color("346e7b")
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

var backdrop: ColorRect
var loadout_panel: Panel
var bag_count: Label
var empty_bag: Label
var item_title: Label
var item_meta: Label
var preview_icon: TextureRect
var detail_scroll: ScrollContainer
var filter_key := "all"
var detail_page := "stats"
var filter_buttons: Dictionary = {}
var page_buttons: Dictionary = {}
var _process_before: int = Node.PROCESS_MODE_INHERIT


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

func attach_room(host: Node2D, show_open_button: bool = true) -> void:
	room=host
	room.set_meta("b09_inventory",self)
	room.room_completed.connect(func():
		if not clear_reward(room.layout_id,room.difficulty,room.layout_seed): message.text=last_error)
	var canvas := CanvasLayer.new()
	canvas.layer=5
	canvas.process_mode=Node.PROCESS_MODE_ALWAYS
	room.add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=GameStyle.make_theme()
	canvas.add_child(ui)
	if show_open_button:
		var open := _action(ui,"装备与战利品",Vector2(12,132),Vector2(164,42),_open)
		open.name="B09EquipmentOpen"
	backdrop=ColorRect.new()
	backdrop.color=Color("13283bcc")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(backdrop)
	panel=PanelContainer.new()
	panel.name="B09EquipmentPanel"
	panel.custom_minimum_size=Vector2(1160,660)
	panel.add_theme_stylebox_override("panel",_skin(Color("f5f1e7"),Color("b5a078"),2,16))
	ui.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left=-580
	panel.offset_top=-330
	panel.offset_right=580
	panel.offset_bottom=330
	var body := Control.new()
	body.custom_minimum_size=Vector2(1128,628)
	panel.add_child(body)
	_text(body,"霜晶行囊",Vector2(16,2),Vector2(280,42),28,INK)
	_text(body,"B09  /  霜晶王庭",Vector2(18,44),Vector2(330,22),12,MUTED)
	_text(body,"远征配装",Vector2(850,13),Vector2(190,24),13,ACCENT).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var close := _action(body,"×",Vector2(1060,4),Vector2(48,44),_close)
	close.tooltip_text="关闭行囊 · Esc"
	close.add_theme_font_size_override("font_size",24)
	var escape := InputEventKey.new()
	escape.keycode=KEY_ESCAPE
	close.shortcut=Shortcut.new()
	close.shortcut.events=[escape]
	GameStyle.divider(body,Vector2(16,70),1096)
	loadout_panel=_column(body,Vector2(14,84),Vector2(224,480),Color("e6edf0"))
	var bag := _column(body,Vector2(250,84),Vector2(334,480),Color("eee9df"))
	_text(bag,"行囊",Vector2(16,12),Vector2(140,28),18,INK)
	bag_count=_text(bag,"0 件装备",Vector2(190,17),Vector2(126,20),12,MUTED)
	bag_count.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	for index: int in 4:
		var key: String=["all","weapon","armor","accessory"][index]
		var button := _action(bag,["全部","武器","防具","饰品"][index],Vector2(16+index*76,52),Vector2(72,32),func(): filter_key=key; _refresh())
		button.name="B09Filter_"+key
		filter_buttons[key]=button
	list=ItemList.new()
	list.name="B09InventoryList"
	list.position=Vector2(16,100)
	list.size=Vector2(302,342)
	list.max_columns=3
	list.fixed_column_width=86
	list.fixed_icon_size=Vector2i(50,50)
	list.icon_mode=ItemList.ICON_MODE_TOP
	list.max_text_lines=2
	list.add_theme_font_size_override("font_size",12)
	list.add_theme_color_override("font_color",INK)
	list.add_theme_color_override("font_selected_color",INK)
	list.add_theme_constant_override("h_separation",8)
	list.add_theme_constant_override("v_separation",10)
	list.add_theme_constant_override("icon_margin",6)
	list.add_theme_stylebox_override("panel",_skin(Color("eee9df"),Color.TRANSPARENT,0,4))
	list.add_theme_stylebox_override("selected",_skin(Color("dcebed"),ACCENT,2,4))
	list.add_theme_stylebox_override("selected_focus",_skin(Color("dcebed"),ACCENT,2,4))
	list.add_theme_stylebox_override("cursor",_skin(Color.TRANSPARENT,ACCENT,2,4))
	list.add_theme_stylebox_override("focus",_skin(Color.TRANSPARENT,Color.TRANSPARENT,0,0))
	list.item_selected.connect(func(index: int): selected=ids[index]; _detail())
	bag.add_child(list)
	empty_bag=_text(bag,"行囊还是空的\n清场后，战利品会自动收入这里。",Vector2(32,200),Vector2(270,90),15,MUTED)
	empty_bag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_text(bag,"点击装备查看详情 · 滚轮翻页",Vector2(16,452),Vector2(302,18),11,MUTED)
	var right := _column(body,Vector2(596,84),Vector2(518,480),Color("fffdf6"))
	preview_icon=_icon(right,null,Vector2(20,16),Vector2(70,70))
	item_title=_text(right,"选择一件装备",Vector2(106,18),Vector2(388,32),22,INK)
	item_meta=_text(right,"属性、换装收益与套装效果",Vector2(108,56),Vector2(386,24),12,MUTED)
	for index: int in 3:
		var key: String=["stats","compare","set"][index]
		var tab := _action(right,["装备属性","换装对比","套装效果"][index],Vector2(20+index*160,102),Vector2(150,32),func(): detail_page=key; _detail())
		tab.name="B09DetailTab_"+key
		page_buttons[key]=tab
	detail_scroll=ScrollContainer.new()
	detail_scroll.name="B09DetailScroll"
	detail_scroll.position=Vector2(20,146)
	detail_scroll.size=Vector2(478,270)
	detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(detail_scroll)
	details=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",8)
	detail_scroll.add_child(details)
	equip_button=_action(right,"穿戴选中装备",Vector2(20,430),Vector2(266,38),func():
		if equip(selected): message.text="换装已生效。"; _refresh()
		else: message.text=last_error)
	_primary(equip_button)
	unequip_button=_action(right,"卸下同槽装备",Vector2(298,430),Vector2(200,38),func():
		if not selected.is_empty() and equip("",str(ContentRegistry.equipment(Game.run.equipment_snapshot[selected].template_id,2).slot)):
			message.text="装备已卸下。"; _refresh())
	message=_text(body,"清场自动拾取并保存",Vector2(18,580),Vector2(500,20),12,ACCENT)
	_text(body,"换装保留当前生命、资源与冷却",Vector2(18,602),Vector2(500,18),11,MUTED)
	var grant := _action(body,"领取19件测试装备",Vector2(730,580),Vector2(190,38),func():
		if grant_catalog(): message.text="已领取 19 件测试装备，来源已标记。"; _refresh()
		else: message.text=last_error)
	grant.tooltip_text="仅候选试玩：本职业 8 件、共有 8 件、散件 3 件。"
	_action(body,"关闭并继续",Vector2(932,580),Vector2(180,38),_close)
	panel.hide()
	backdrop.hide()

func _skin(fill: Color, border: Color, width: int = 1, padding: int = 8) -> StyleBoxFlat:
	var box := GameStyle.box(fill,border,width)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(padding)
	box.shadow_size=0
	return box

func _column(parent: Control, at: Vector2, extent: Vector2, fill: Color) -> Panel:
	var node := Panel.new()
	node.position=at
	node.size=extent
	node.add_theme_stylebox_override("panel",_skin(fill,Color("d8cbb4"),1,0))
	parent.add_child(node)
	return node

func _text(parent: Node, caption: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	return GameStyle.literal(parent,caption,at,extent,font_size,color)

func _action(parent: Node, caption: String, at: Vector2, extent: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text=caption
	button.position=at
	button.size=extent
	button.add_theme_font_size_override("font_size",13)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state,_skin(Color("ddebed") if state in ["hover","pressed"] else Color("fffaf0"),ACCENT if state=="focus" else Color("c9b894"),1,6))
		button.add_theme_color_override("font_"+state+"_color",INK)
	button.add_theme_color_override("font_color",INK)
	button.add_theme_color_override("font_disabled_color",MUTED)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _primary(button: Button) -> void:
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		button.add_theme_stylebox_override(state,_skin(Color("7d9397") if state=="disabled" else ACCENT.lightened(0.10) if state=="hover" else ACCENT,Color("a6bbbe"),1,6))
		button.add_theme_color_override("font_"+state+"_color",Color("fffaf0"))
	button.add_theme_color_override("font_color",Color("fffaf0"))

func _icon(parent: Control, texture: Texture2D, at: Vector2, extent: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	icon.texture=texture
	icon.position=at
	icon.size=extent
	return icon

func _slot_texture(slot: String) -> Texture2D:
	var id: String={"weapon":"EQ01","head":"EQ11","chest":"EQ21","hands":"EQ31","feet":"EQ41","charm":"EQ51"}.get(slot,"")
	return Art.slot_texture(slot) if id.is_empty() else Art.texture(id)

func _open() -> void:
	if not is_instance_valid(room) or panel.visible: return
	_blocked_before=room.input_blocked
	_process_before=room.process_mode
	room.set_input_blocked(true)
	room.process_mode=Node.PROCESS_MODE_DISABLED
	_refresh()
	backdrop.show()
	panel.show()
	list.grab_focus()

func _close() -> void:
	panel.hide()
	backdrop.hide()
	if not is_instance_valid(room): return
	room.process_mode=_process_before
	room.set_input_blocked(_blocked_before or Game.run.hp<=0)

func _refresh() -> void:
	list.clear()
	ids.clear()
	var total := 0
	for id: String in Game.run.equipment_snapshot:
		var record: Dictionary=Game.run.equipment_snapshot[id]
		if not str(record.template_id).begins_with("B09-"): continue
		var item := ContentRegistry.equipment(record.template_id,2)
		if Game.run.hero_id not in item.get("allowed_heroes",[]): continue
		total+=1
		var group := "weapon" if item.slot=="weapon" else "accessory" if item.slot in ["ring","charm"] else "armor"
		if filter_key=="all" or filter_key==group: ids.append(id)
	ids.sort()
	bag_count.text="%d / %d 件" % [ids.size(),total]
	for key: String in filter_buttons: _tab_style(filter_buttons[key],filter_key==key)
	for id: String in ids:
		var record: Dictionary=Game.run.equipment_snapshot[id]
		var item := ContentRegistry.equipment(record.template_id,2)
		item["instance_record"]=record
		var equipped: bool=id in Game.run.loadout_snapshot.values()
		var index := list.add_item(str(item.name)+"\n"+("已装备" if equipped else "iLv %d" % int(record.item_level)),_slot_texture(str(item.slot)))
		list.set_item_tooltip(index,Inspect.tooltip(item,int(record.enhancement_rank),Game.run.hero_id))
	empty_bag.visible=ids.is_empty()
	if not ids.has(selected): selected=ids[0] if not ids.is_empty() else ""
	if not selected.is_empty(): list.select(ids.find(selected))
	_loadout()
	_detail()

func _loadout() -> void:
	for child: Node in loadout_panel.get_children(): child.free()
	_text(loadout_panel,"当前配装",Vector2(16,12),Vector2(170,28),18,INK)
	var fitted := Game.run.loadout_snapshot.size()
	_text(loadout_panel,"%d / 8" % fitted,Vector2(170,19),Vector2(40,18),11,ACCENT)
	GameStyle.hero_portrait(loadout_panel,Game.run.hero_id,Vector2(18,54),Vector2(88,102))
	_text(loadout_panel,GameStyle.content_text(ContentRegistry.hero(Game.run.hero_id),"name"),Vector2(114,64),Vector2(96,26),17,INK)
	_text(loadout_panel,"Lv.45  远征者",Vector2(114,96),Vector2(96,22),12,MUTED)
	_text(loadout_panel,"霜晶王庭",Vector2(114,124),Vector2(96,20),12,ACCENT)
	for index: int in 8:
		var slot: String=ContentRegistry.slots(2)[index]
		var id: String=str(Game.run.loadout_snapshot.get(slot,""))
		var at := Vector2(16+(index%2)*100,178+(index/2)*65)
		var button := _action(loadout_panel,"",at,Vector2(92,57),func():
			filter_key="all"
			if not id.is_empty(): selected=id
			_refresh())
		button.name="B09Loadout_"+slot
		_text(button,Words.text("SLOT_"+slot.to_upper()),Vector2(8,3),Vector2(78,17),11,MUTED)
		_icon(button,_slot_texture(slot),Vector2(6,23),Vector2(28,28)).modulate=Color(1,1,1,0.35 if id.is_empty() else 1.0)
		var caption := "空槽" if id.is_empty() else str(ContentRegistry.equipment(Game.run.equipment_snapshot[id].template_id,2).name)
		var label := _text(button,caption,Vector2(37,23),Vector2(49,25),11,MUTED if id.is_empty() else INK)
		label.autowrap_mode=TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text=Words.text("SLOT_"+slot.to_upper())+" · "+caption
	var power: String="ability_power" if Game.run.hero_id=="CH03" else "attack"
	_text(loadout_panel,"生命上限",Vector2(16,437),Vector2(90,18),11,MUTED)
	_text(loadout_panel,str(int(Game.run.stats.max_hp)),Vector2(16,454),Vector2(90,18),14,INK)
	_text(loadout_panel,Inspect.caption(power),Vector2(116,437),Vector2(96,18),11,MUTED)
	_text(loadout_panel,str(int(Game.run.stats.get(power,0))),Vector2(116,454),Vector2(96,18),14,INK)

func _tab_style(button: Button, active: bool) -> void:
	button.add_theme_stylebox_override("normal",_skin(Color("dcebed") if active else Color("f4efe5"),ACCENT if active else Color("d8cbb4"),1,6))
	button.add_theme_color_override("font_color",ACCENT if active else MUTED)

func _detail() -> void:
	for index: int in ids.size():
		var rarity: String=str(Game.run.equipment_snapshot[ids[index]].rarity)
		list.set_item_custom_bg_color(index,Color.TRANSPARENT if ids[index]==selected else Color("e2e5ec") if rarity=="purple" else Color("eee1bd") if rarity=="gold" else Color("e4ebdc") if rarity=="green" else Color("f7f2e8"))
	for child: Node in details.get_children(): child.free()
	detail_scroll.scroll_vertical=0
	for key: String in page_buttons: _tab_style(page_buttons[key],detail_page==key)
	equip_button.disabled=selected.is_empty()
	unequip_button.disabled=selected.is_empty()
	if selected.is_empty():
		item_title.text="选择一件装备"
		item_meta.text="在行囊中选择，查看属性和换装收益。"
		preview_icon.texture=null
		Details.flow(details,"每次清场都会获得装备。\n\n也可以从下方领取测试装备，体验本职业套装。",458,15,MUTED)
		return
	var record: Dictionary=Game.run.equipment_snapshot[selected]
	var item := ContentRegistry.equipment(record.template_id,2)
	item["instance_record"]=record
	item["instance_id"]=selected
	var next: Dictionary=Game.run.loadout_snapshot.duplicate(true)
	next[item.slot]=selected
	var stats := Resolver.resolve(Game.run.hero_id,45,next,Game.run.equipment_snapshot,2)
	item_title.text=str(item.name)
	item_title.add_theme_color_override("font_color",Inspect.rarity_color(item))
	item_meta.text="%s · %s · %s · iLv %d · 强化 +%d" % [Words.text("SLOT_"+str(item.slot).to_upper()),Inspect.rarity_name(str(record.rarity)),Inspect.type_name(str(record.power_type)),int(record.item_level),int(record.enhancement_rank)]
	preview_icon.texture=_slot_texture(str(item.slot))
	unequip_button.disabled=not Game.run.loadout_snapshot.has(item.slot)
	var detail := Details.new()
	details.add_child(detail)
	detail.configure(item,int(record.enhancement_rank),458,Game.run.hero_id,Game.run.stats,stats,detail_page)
	var source := Details.flow(details,"获取来源："+("候选测试装备" if str(record.source_event_id).begins_with("b09_catalog:") else "战斗掉落"),458,12,MUTED)
	source.tooltip_text=str(record.source_event_id)
