extends RefCounted
## Expedition behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
const Finale = preload("res://scripts/presentation/components/finale_artwork.gd")
var host

func _init(context: Node) -> void:
	host = context

func _build_expedition_status() -> void:
	if is_instance_valid(host.expedition_status):
		host.expedition_status.get_parent().queue_free()
	if host.expedition == null or not host.expedition.active() or not is_instance_valid(host.screen):
		return
	var map_button = GameStyle.button(host.screen,"",Vector2(988,16),Vector2(134,44),func():
		if host.modals.is_empty():
			host.show_expedition(false))
	map_button.name = "ExpeditionMapButton"
	host.expedition_status = GameStyle.literal(map_button,"",Vector2(10,7),Vector2(114,30),17,GameStyle.INK)
	host.expedition_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_instance_valid(host.hud): host.hud.place_route_button(map_button)
	host._update_expedition_status()

func _update_expedition_status() -> void:
	if not is_instance_valid(host.expedition_status) or host.expedition == null or not host.expedition.active():
		return
	var key: String = host.Controls.label_for("expedition_map",Game.profile.get("settings",{}).get("controls",{}),Words.locale)
	host.expedition_status.text = host._ex_text("路线  [", "Route  [") + key + "]"
	if is_instance_valid(host.hud): host.hud.place_route_button(host.expedition_status.get_parent())

func _expedition_node_count() -> int:
	if host.expedition == null: return 0
	return host.expedition.snapshot().get("route",{}).get("nodes",[]).size()

func _on_expedition_room_completed() -> void:
	host._update_expedition_status()
	if host.expedition != null and host.expedition.active() and not Game.pending_field_equipment().is_empty():
		if is_instance_valid(host.hud): host.hud._queue_notification(host._ex_text("发现战利品 · 在地面标记处交互查看", "Loot found · Interact at the ground marker to inspect"),3.5)

func _show_loot_pickup() -> void:
	if Game.run == null or host.expedition == null or not host.expedition.active() or not host.modals.is_empty(): return
	host.loot_flow_active = true
	for offer: Dictionary in host.expedition.snapshot().get("relic_offers", []):
		if str(offer.get("decision", "")).is_empty():
			host._show_pending_expedition_offer()
			return
	var offers: Array = Game.pending_field_equipment()
	if offers.is_empty():
		host.loot_flow_active = false
		host._show_pending_expedition_offer()
		return
	host.loot_flow_active = true
	var panel = host._push_modal("", Vector2(840,574))
	panel.name = "LootPickupModal"
	var pickup = host.LootPickupPanel.new()
	pickup.size = panel.size
	panel.add_child(pickup)
	pickup.configure(offers)
	pickup.close_requested.connect(host._pop_modal)
	pickup.inspect_requested.connect(func(drop_id: String):
		host._pop_modal()
		host._show_field_equipment({"drop_id":drop_id}))
	pickup.pack_requested.connect(func(drop_id: String):
		host._choose_field_equipment(drop_id, "keep", str(host.expedition.snapshot().get("checkpoint_id", ""))))

func show_expedition(at_exit: bool = false) -> void:
	if host.expedition == null or not host.expedition.active() or Game.run == null:
		return
	var panel = host._push_modal("",Vector2(1072,580))
	panel.name = "ExpeditionRouteModal"
	var state: Dictionary = host.expedition.snapshot()
	var finale: bool = str(state.get("biome_id",state.get("route",{}).get("biome_id",""))) == "B10"
	if finale: Finale.panel_style(panel)
	var title: String = host._ex_text("10 · 星辉龙庭行图 · %d 站","10 · DRAGON COURT ATLAS · %d STOPS") if finale else host._ex_text("远征行图 · 本次 %d 站", "EXPEDITION ATLAS · %d STOPS")
	GameStyle.literal(panel,title % host._expedition_node_count(),Vector2(28,20),Vector2(1016,45),28,Finale.DEEP if finale else GameStyle.AMBER)
	var chart = host.ExpeditionPanel.new()
	chart.name = "ExpeditionRouteChart"
	chart.position = Vector2(28,78)
	chart.size = Vector2(1016,480)
	panel.add_child(chart)
	# M and the route button must honor their "choose the next room" prompt.
	# Completion is still the gate; an uncleared room remains preview-only.
	chart.configure(host.expedition, at_exit or host.expedition.current_complete())
	chart.close_requested.connect(host._pop_modal)
	chart.choice_requested.connect(host._advance_expedition)
	chart.early_extract_requested.connect(func():
		host._pop_modal()
		host.show_extraction())

func _advance_expedition(room_id: String) -> void:
	if host.expedition_action_pending or host.expedition == null or not host.expedition.active() or not is_instance_valid(host.room):
		return
	var context: Dictionary = host.expedition.candidate(room_id)
	if context.is_empty():
		return
	var checkpoint_id: String = str(host.expedition.snapshot().get("checkpoint_id",""))
	host.expedition_action_pending = true
	# Preflight has no mutations. The scene is applied only after both committed
	# choice and next-entry receipt succeed, so a disk failure leaves this room.
	var prepared: Dictionary = host.room.prepare_expedition_node(context)
	if prepared.is_empty() or not bool(prepared.get("valid",false)):
		host.room.discard_prepared_expedition_node(prepared)
		host.expedition_action_pending = false
		host._show_expedition_error(host._ex_text("下一房未能载入，当前房间已保留。", "The next room could not be loaded. Your current room is intact."),func(): host._advance_expedition(room_id))
		return
	if not Game.choose_expedition_node(int(context.node_index), room_id):
		host.room.discard_prepared_expedition_node(prepared)
		host.expedition_action_pending = false
		host._show_expedition_error(Words.text(Game.last_error),func(): host._advance_expedition(room_id))
		return
	var runtime: Dictionary = prepared.get("runtime",host.room.expedition_runtime_snapshot())
	if not Game.advance_expedition_node(runtime,checkpoint_id):
		host.room.discard_prepared_expedition_node(prepared)
		host.expedition_action_pending = false
		host._show_expedition_error(Words.text(Game.last_error),func(): host._advance_expedition(room_id))
		return
	# Entry transactions may materialize a paid next-room shield. Restore the
	# committed result, not the pre-purchase/pre-advance copy from preflight.
	prepared["runtime"] = Game.expedition_snapshot().get("runtime",runtime).duplicate(true)
	host.room.apply_prepared_expedition_node(prepared)
	host.expedition_action_pending = false
	host._clear_modals()
	host._update_expedition_status()
	host.room.set_input_blocked(false)
	call_deferred("_show_pending_expedition_offer")

func _show_expedition_error(message: String, retry: Callable, preserve_action: bool = false) -> void:
	var panel = host._push_modal("ERROR_TITLE",Vector2(700,318))
	if message.is_empty():
		message = host._ex_text("当前操作未能完成，进度与金币已保留。请重试。", "This action could not complete. Your progress and gold are unchanged. Please retry.")
	GameStyle.literal(panel,message,Vector2(28,85),Vector2(644,108),19,GameStyle.RED)
	var actions = GameStyle.action_pair(panel,"RETRY","BACK",226,func():
		host._pop_modal()
		retry.call(),func():
		if preserve_action:
			host._pop_modal()
			return
		host._clear_modals()
		host._show_pending_expedition_offer()
		if host.modals.is_empty():
			host.show_expedition(true))
	actions[0].grab_focus()

func _show_pending_expedition_offer() -> void:
	if Game.run == null or host.expedition == null or not host.expedition.active() or not host.modals.is_empty():
		return
	for offer: Dictionary in host.expedition.snapshot().get("relic_offers", []):
		if str(offer.get("decision", "")).is_empty():
			host._show_expedition_relic(offer)
			return
	for offer: Dictionary in Game.pending_field_equipment():
		host._show_field_equipment(offer)
		return

func _show_field_equipment(offer: Dictionary) -> void:
	var drop_id = str(offer.get("drop_id", ""))
	var preview: Dictionary = Game.preview_field_equipment(drop_id)
	if preview.is_empty():
		return
	# Bind the displayed comparison to this checkpoint, including every retry.
	var checkpoint_id = str(host.expedition.snapshot().get("checkpoint_id", ""))
	var panel = host._push_modal("", Vector2(980,620))
	panel.name = "FieldEquipmentModal"
	host.modals[-1]["required"] = true
	var comparison = host.FieldEquipmentPanel.new()
	comparison.name = "FieldEquipmentComparison"
	comparison.size = panel.size
	panel.add_child(comparison)
	comparison.configure(preview)
	comparison.choice_requested.connect(func(decision: String): host._choose_field_equipment(drop_id, decision, checkpoint_id))

func _choose_field_equipment(drop_id: String, decision: String, checkpoint_id: String) -> void:
	if host.expedition_action_pending or host.expedition == null or not host.expedition.active() or not is_instance_valid(host.room):
		return
	var comparison: Control = null
	for modal: Dictionary in host.modals:
		var candidate: Control = modal.node.find_child("FieldEquipmentComparison", true, false)
		if is_instance_valid(candidate): comparison = candidate
	if is_instance_valid(comparison):
		comparison.set_busy(true)
	host.expedition_action_pending = true
	var success: bool = Game.choose_field_equipment(drop_id, decision, host.room.expedition_runtime_snapshot(), checkpoint_id)
	host.expedition_action_pending = false
	if not success:
		if is_instance_valid(comparison): comparison.set_busy(false)
		host._show_expedition_error(Words.text(Game.last_error), func(): host._choose_field_equipment(drop_id, decision, checkpoint_id), true)
		return
	if not host.room.restore_expedition_runtime(host.expedition.snapshot().get("runtime", {})):
		if is_instance_valid(comparison): comparison.set_busy(false)
		host._show_expedition_error(host._ex_text("试装选择已保存，但角色状态恢复失败。重试会恢复同一选择，不会重复发放装备。", "Your fitting decision is saved, but character state could not be restored. Retry restores that choice without granting gear again."), func(): host._choose_field_equipment(drop_id, decision, checkpoint_id), true)
		return
	host._clear_modals()
	if is_instance_valid(host.hud):
		var item: Dictionary = Game.equipment_definition(str(Game.run.expedition.claimed_drop_ids.get(drop_id,{}).get("equipment_id","")),true)
		host.hud._queue_notification(host._ex_text("已装备：", "Equipped: ")+GameStyle.content_text(item,"name") if decision == "equip" else host._ex_text("已收进行囊：", "Packed: ")+GameStyle.content_text(item,"name"),3.5)
	if host.loot_flow_active: host._show_loot_pickup()
	else: host._show_pending_expedition_offer()

func show_expedition_service() -> void:
	if host.expedition == null or not host.expedition.active() or Game.run == null:
		return
	if host.expedition.current_node().get("role", "") == "supply":
		host._show_expedition_supply()
	else:
		host._show_pending_expedition_offer()
		if host.modals.is_empty():
			host.show_expedition(false)

func _show_expedition_relic(offer: Dictionary) -> void:
	var panel = host._push_modal("",Vector2(1048,660))
	panel.name = "ExpeditionRelicModal"
	host.modals[-1]["required"] = true
	GameStyle.literal(panel,host._ex_text("选一件遗物 · 塑造本局打法", "CHOOSE A RELIC · SHAPE THIS RUN"),Vector2(28,20),Vector2(992,47),28,GameStyle.AMBER)
	GameStyle.literal(panel,host._ex_text("选择立即生效，只保留到本局结束。跳过会放弃这次遗物机会，最多恢复 6% 最大生命。", "Choose an effect for this run. Skipping gives up this relic opportunity and heals up to 6% max health."),Vector2(28,80),Vector2(992,44),17,GameStyle.MUTED)
	var candidates: Array = offer.get("candidates",[])
	var cards: Array[Button] = []
	var card_height = 234.0
	var scroll = ScrollContainer.new()
	scroll.name = "RelicChoicesScroll"
	scroll.position = Vector2(28,140)
	scroll.size = Vector2(992,414)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	scroll.add_child(row)
	for index in candidates.size():
		var id = str(candidates[index])
		var current_rank: int = int(host.expedition.snapshot().get("relic_levels",{}).get(id,0))
		var info = host._relic_display(id,mini(2,current_rank+1))
		var card = GameStyle.button(row,"",Vector2.ZERO,Vector2(314,234),func(): host._choose_expedition_relic(str(offer.offer_id),id))
		card.custom_minimum_size = Vector2(314,234)
		card.name = "RelicChoice_"+id
		cards.append(card)
		host._relic_artwork(card,info,Vector2(116,12),Vector2(88,88),id)
		var title = GameStyle.literal(card,str(info.name)+(host._ex_text(" · 升级"," · UPGRADE") if current_rank==1 else ""),Vector2(40,104),Vector2(258,0),22,GameStyle.CYAN)
		title.name = "RelicTitle"
		title.size.y = ceilf(title.get_minimum_size().y)
		var description = GameStyle.literal(card,str(info.description),Vector2(40,title.position.y+title.size.y+6),Vector2(258,0),16,GameStyle.INK)
		description.name = "RelicDescription"
		description.max_lines_visible = -1
		description.clip_text = false
		description.size.y = ceilf(description.get_minimum_size().y)
		card_height = maxf(card_height,description.position.y+description.size.y+16)
	for card: Button in cards: card.custom_minimum_size.y = card_height
	var skip = GameStyle.button(panel,"",Vector2(678,584),Vector2(342,52),func(): host._request_relic_skip(str(offer.offer_id)))
	skip.name = "SkipExpeditionRelic"
	var gain = minf(maxf(0.0,Game.run.max_hp-Game.run.hp),Game.run.max_hp*0.06)
	skip.text = host._ex_text("跳过 · 本次不恢复生命", "Skip · no health recovered") if gain <= 0.0 else host._ex_text("跳过 · 回复 %s 生命", "Skip · recover %s HP") % host._amount(gain)
	skip.tooltip_text = host._ex_text("放弃本次遗物机会；此选择不可撤销。", "Give up this relic opportunity; this choice cannot be undone.")
	if not cards.is_empty(): cards[0].grab_focus()
	else:
		# No candidates: keep deliberate skip reachable, but require its own confirmation.
		var review = GameStyle.button(panel,"",Vector2(28,584),Vector2(600,52),func(): host._request_relic_skip(str(offer.offer_id),true))
		review.name = "ReviewEmptyRelicOffer"
		review.text = host._ex_text("没有可选遗物 · 查看跳过说明", "No relics available · review skip")
		review.grab_focus()

func _choose_expedition_relic(offer_id: String, choice_id: String) -> void:
	if host.expedition_action_pending or not is_instance_valid(host.room):
		return
	host.expedition_action_pending = true
	var success: bool = Game.choose_run_relic(offer_id,choice_id,"",host.room.expedition_runtime_snapshot())
	host.expedition_action_pending = false
	if not success:
		host._show_expedition_error(Words.text(Game.last_error),func(): host._choose_expedition_relic(offer_id,choice_id))
		return
	if not host.room.restore_expedition_runtime(host.expedition.snapshot().get("runtime",{})):
		host._show_expedition_error(host._ex_text("遗物已保存，但角色状态恢复失败。重试不会重复发放。", "The relic decision is saved, but character state could not be restored. Retrying does not grant it again."),func(): host._choose_expedition_relic(offer_id,choice_id))
		return
	host._clear_modals()
	if host.loot_flow_active: host._show_loot_pickup()
	else: host._show_pending_expedition_offer()

func _show_expedition_supply() -> void:
	var panel = host._push_modal("",Vector2(920,640))
	panel.name = "ExpeditionSupplyModal"
	GameStyle.literal(panel,host._ex_text("矿下补给站", "UNDERGROUND SUPPLY"),Vector2(28,20),Vector2(864,45),30,GameStyle.AMBER)
	GameStyle.literal(panel,host._ex_text("本局金币 ", "CARRIED GOLD ")+str(Game.run.gold),Vector2(28,75),Vector2(864,32),20,GameStyle.CYAN)
	var deficit = maxf(0.0,Game.run.max_hp-Game.run.hp)
	var healing_rule = GameStyle.literal(panel,host._ex_text("本次休整治疗二选一 · 购买一项后另一项关闭\n当前缺血 %s；以下显示实际恢复量（不会超出最大生命）。", "ONE HEAL PER REST · Buying either closes the other\nMissing %s HP; previews show actual healing, capped by max health.") % host._amount(deficit),Vector2(28,117),Vector2(864,54),17,GameStyle.AMBER)
	healing_rule.name = "HealingChoiceRule"
	var products = {"heal_small":["应急药剂 · 15%", "Field dressing · 15%"], "heal_large":["维修包 · 35%", "Repair kit · 35%"], "shield":["预备护盾 · 15%生命", "Reserve shield · 15% HP"], "amplify":["超频剂 · 后两战斗房攻击 +8%", "Overclock · +8% for 2 rooms"], "scan":["勘测信标 · 显示具体敌群", "Survey beacon · reveal enemies"]}
	var entries: Array = host.expedition.snapshot().get("supply_offers",[])
	var healing_purchased = false
	for entry: Dictionary in entries:
		if str(entry.get("product_id","")) in ["heal_small","heal_large"] and str(entry.get("decision","")) == "purchased": healing_purchased = true
	var other_index = 0
	for offer: Dictionary in entries:
		var product = str(offer.get("product_id",""))
		# Resource recovery is an explicit free preparation step, including old offers.
		if product in ["mana","energy"]: continue
		var healing = product in ["heal_small","heal_large"]
		var index = (0 if product == "heal_small" else 1) if healing else other_index
		var at = Vector2(28+(index%2)*442,180 if healing else 282+floori(index/2.0)*83)
		var button = GameStyle.button(panel,"",at,Vector2(422,82 if healing else 72),func(): host._buy_expedition_supply(str(offer.offer_id)))
		button.name = "Supply_"+product
		button.add_theme_font_size_override("font_size",15)
		var texts: Array = products.get(product,[product,product])
		var reason = host._supply_disabled_reason(offer,healing_purchased)
		var price = str(offer.get("price",0))+host._ex_text(" 金币", " gold")
		button.text = str(texts[1] if Words.locale == "en" else texts[0])
		if healing:
			var gain = minf(deficit,Game.run.max_hp*(0.15 if product == "heal_small" else 0.35))
			button.text += host._ex_text(" · 实际 +%s 生命", " · +%s HP now") % host._amount(gain)
		button.text += "\n"+(price if reason.is_empty() else reason)
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else (host._ex_text("购买会关闭另一治疗选项。", "Buying this closes the other healing option.") if healing else host._ex_text("每项限购一次。", "Each item can be bought once."))
		if product == "shield":
			button.tooltip_text += host._ex_text("\n下一战斗房生效，首次吸收后持续4秒。多个护盾共享最大容量，吸收会同时消耗所有来源。", "\nNext combat room; lasts 4 seconds after its first absorption. Overlapping shields share the largest capacity; absorbed damage reduces every source.")
		if not healing: other_index += 1
	var resource_type = str(Game.run.stats.get("resource_type",""))
	var resource_missing = maxf(0.0,float(Game.run.stats.get("resource_max",0.0))-Game.run.resource)
	var preparation = GameStyle.button(panel,"",Vector2(28,459),Vector2(864,70),host._prepare_safe_resources)
	preparation.name = "PrepareSafeResources"
	preparation.add_theme_font_size_override("font_size",17)
	preparation.text = host._ex_text("免费快速整备 · 补满法力 / 能量", "FREE PREPARATION · REFILL MANA / ENERGY")+"\n"
	if resource_type not in ["mana","energy"]:
		preparation.text += host._ex_text("怒气通过战斗积累，无需购买回能补给", "Rage builds through combat; no resource purchase needed")
	elif resource_missing <= 0.0:
		preparation.text += host._ex_text("资源已满", "Resource already full")
	else:
		preparation.text += host._ex_text("恢复 %s 资源 · 不花金币 · 不改变技能冷却", "Restore %s resource · no gold cost · cooldowns unchanged") % host._amount(resource_missing)
	preparation.disabled = resource_type not in ["mana","energy"] or resource_missing <= 0.0
	GameStyle.literal(panel,host._ex_text("无需付费替代安全等待；整备不会治疗生命或重置冷却。", "No need to pay instead of waiting safely. Preparation does not heal HP or reset cooldowns."),Vector2(28,538),Vector2(864,40),15,GameStyle.MUTED)
	GameStyle.button(panel,"BACK",Vector2(650,579),Vector2(242, 40),host._pop_modal).grab_focus()

func _buy_expedition_supply(offer_id: String) -> void:
	if host.expedition_action_pending or not is_instance_valid(host.room):
		return
	host.expedition_action_pending = true
	var success: bool = Game.purchase_run_supply(offer_id,host.room.expedition_runtime_snapshot())
	host.expedition_action_pending = false
	if not success:
		host._show_expedition_error(Words.text(Game.last_error),func(): host._buy_expedition_supply(offer_id))
		return
	if not host.room.restore_expedition_runtime(host.expedition.snapshot().get("runtime",{})):
		host._show_expedition_error(host._ex_text("补给交易已保存，但角色状态恢复失败。重试不会重复扣款。", "The purchase is saved, but character state could not be restored. Retrying will not charge again."),func(): host._buy_expedition_supply(offer_id))
		return
	host._clear_modals()
	host._show_expedition_supply()

func show_expedition_exit() -> void:
	if host.expedition == null or not host.expedition.active():
		return
	var panel = host._push_modal("",Vector2(720,360))
	panel.name = "SaveExpeditionModal"
	host._camp_ui_icon(panel,"route",Vector2(28,21),Vector2(72,72))
	GameStyle.literal(panel,host._ex_text("封存这段旅程", "SEAL YOUR JOURNEY"),Vector2(122,28),Vector2(568,38),28,GameStyle.INK)
	GameStyle.literal(panel,host._ex_text("保存远征并退出", "SAVE EXPEDITION AND EXIT"),Vector2(124,72),Vector2(550,26),14,GameStyle.CYAN)
	var note = host._ex_text("当前位置是安全阶段。保存当前生命、资源与冷却，下次从这一站继续。", "This is a safe phase. Save health, resource and cooldowns and continue from this stop next time.")
	if not host.expedition.current_complete():
		note = host._ex_text("当前房间尚未完成。下次从本房入口重打；本房未提交的金币与战利品不会保留。已完成房间的进度不受影响。", "This room is unfinished. Next time you restart at this room's entrance; uncommitted loot from this room is discarded. Earlier completed rooms are retained.")
	GameStyle.literal(panel,note,Vector2(36,118),Vector2(648,112),18,GameStyle.INK)
	var actions = GameStyle.action_pair(panel,"","CANCEL",267,host._save_expedition_and_quit,host._pop_modal)
	var save = actions[0]
	save.name = "SaveExpeditionAndQuit"
	save.text = host._ex_text("保存旅程 · 退出", "Save journey · Exit")
	GameStyle.primary(save)
	actions[1].grab_focus()
