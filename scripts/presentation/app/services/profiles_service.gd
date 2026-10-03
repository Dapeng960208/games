extends RefCounted
## Profiles behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func show_profile() -> void:
	var panel = host._push_modal("",Vector2(800,640))
	panel.name = "ProfileOverview"
	GameStyle.literal(panel,host._ex_text("存档与英雄档案","SAVE & HERO PROFILE"),Vector2(32,22),Vector2(736,44),28)
	GameStyle.literal(panel,host._ex_text("当前永久档案 · 自动保存","CURRENT PERMANENT PROFILE · AUTOSAVED") if Game.has_profile else host._ex_text("暂无有效存档 · 可从回收站恢复","NO ACTIVE SAVE · RESTORE FROM THE RECYCLE BIN"),Vector2(32,80),Vector2(736,28),14,GameStyle.CYAN)
	GameStyle.divider(panel,Vector2(32,120),736)
	for index: int in 3:
		var id: String = ["CH01","CH02","CH03"][index]
		var card = GameStyle.panel(panel,Vector2(32+index*252,142),Vector2(232,258))
		GameStyle.hero_portrait(card,id,Vector2(34,14),Vector2(164,160))
		GameStyle.literal(card,GameStyle.content_text(ContentRegistry.hero(id),"name"),Vector2(18,184),Vector2(196,32),22)
		GameStyle.literal(card,"Lv."+str(Game.hero_level(id)),Vector2(18,222),Vector2(196,24),17,GameStyle.CYAN)
	GameStyle.literal(panel,host._ex_text("金币 %d · 装备 %d 件 · %s","GOLD %d · %d ITEMS · %s") % [int(Game.profile.get("permanent_gold",0)),Game.profile.get("equipment",{}).size(),host._ex_text("远征进行中","EXPEDITION ACTIVE") if Game.run != null else host._ex_text("营地存档","CAMP SAVE")],Vector2(32,418),Vector2(736,32),17,GameStyle.MUTED)
	var recycle = GameStyle.button(panel,"",Vector2(32,470),Vector2(360,48),host.show_recycle_bin)
	recycle.name = "OpenSaveRecycleBin"
	recycle.text = host._ex_text("存档回收站 · 保留7天","RECYCLE BIN · 7 DAYS")
	var remove = GameStyle.button(panel,"",Vector2(408,470),Vector2(360,48),host._request_delete_profile)
	remove.name = "DeleteSaveToRecycleBin"
	remove.text = host._ex_text("删除当前存档","DELETE CURRENT SAVE")
	remove.disabled = not Game.has_profile or Game.run != null
	remove.tooltip_text = host._ex_text("远征进行中请先返回营地；删除后7天内可在回收站恢复。","Return to camp before deleting an active expedition. Deleted saves can be restored for 7 days.")
	var actions = GameStyle.action_pair(panel,"CONTINUE","BACK",556,func(): host._pop_modal(); host._continue_game(),host._pop_modal)
	actions[0].text = host._continue_button_text()
	actions[0].disabled = not Game.has_profile
	actions[1].grab_focus()

func _request_delete_profile() -> void:
	var panel = host._push_modal("",Vector2(760,390))
	panel.name = "DeleteSaveConfirmation"
	GameStyle.literal(panel,host._ex_text("将当前存档移入回收站？","MOVE THIS SAVE TO THE RECYCLE BIN?"),Vector2(28,22),Vector2(704,44),24)
	GameStyle.literal(panel,host._ex_text("完整存档会保留7天，期间可从「存档回收站」恢复。
7天后，在下次启动或存档管理操作时永久清理。
游戏关闭时不会运行后台清理。", "The complete save is kept for 7 days and can be restored from the Recycle Bin.
After 7 days it is permanently removed on the next launch or save-management action. No cleanup runs while the game is closed."),Vector2(28,88),Vector2(704,192),18)
	var pair = GameStyle.action_pair(panel,"","CANCEL",302,func():
		if Game.delete_profile_to_recycle():
			host.show_menu()
			host.show_recycle_bin()
		else: host._show_save_error(),host._pop_modal)
	pair[0].name = "ConfirmRecycleSave"
	pair[0].text = host._ex_text("移入回收站","MOVE TO RECYCLE BIN")
	pair[1].grab_focus()

func show_recycle_bin() -> void:
	var entries = Game.recycle_entries()
	var read_error = Game.last_error
	var panel = host._push_modal("",Vector2(960,650))
	panel.name = "SaveRecycleBin"
	GameStyle.literal(panel,host._ex_text("存档回收站 · 保留7天","SAVE RECYCLE BIN · 7-DAY RETENTION"),Vector2(28,22),Vector2(904,44),26)
	GameStyle.literal(panel,host._ex_text("到期后在下次启动或存档管理操作时清理；游戏关闭时不会后台清理。
恢复前请先将当前存档移入回收站，避免覆盖任何进度。", "Expired saves are removed on the next launch or save-management action, never in the background while closed.
Move your current save to the Recycle Bin before restoring another save."),Vector2(28,84),Vector2(904,75),16,GameStyle.MUTED)
	var scroll = ScrollContainer.new()
	scroll.name = "RecycleEntries"
	scroll.position = Vector2(28,172)
	scroll.size = Vector2(904,372)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",12)
	scroll.add_child(rows)
	for entry: Dictionary in entries:
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(860,146)
		rows.add_child(card)
		var content = Control.new()
		content.custom_minimum_size = Vector2(860,146)
		card.add_child(content)
		var deleted = Time.get_datetime_string_from_unix_time(int(entry.deleted_at),true)+" UTC"
		var expires = Time.get_datetime_string_from_unix_time(int(entry.expires_at),true)+" UTC"
		var status = host._recycle_remaining(entry)
		var summary = host._ex_text("删除时间：%s
保留至：%s
%s", "Deleted: %s
Keep until: %s
%s") % [deleted,expires,status]
		var identity = host._ex_text("无法验证的存档","Unverified save")
		if bool(entry.valid):
			identity = GameStyle.content_text(ContentRegistry.hero(str(entry.hero)),"name")+host._ex_text(" · 金币 %d · 档案 %s", " · Gold %d · Profile %s") % [int(entry.gold),str(entry.profile_id).substr(0,8)]
		GameStyle.literal(content,identity,Vector2(16,9),Vector2(622,28),17,GameStyle.INK)
		GameStyle.literal(content,summary,Vector2(16,44),Vector2(622,92),15)
		var restore = GameStyle.button(content,"",Vector2(658,46),Vector2(182,48),func(): host._request_restore_profile(str(entry.entry_id)))
		restore.name = "Restore_"+str(entry.entry_id)
		restore.text = host._ex_text("恢复此存档","RESTORE SAVE")
		restore.disabled = Game.has_profile or Game.run != null or not bool(entry.valid) or bool(entry.expired)
		restore.tooltip_text = host._ex_text("先将当前存档移入回收站，再恢复此档。", "Move the current save to the Recycle Bin first.") if Game.has_profile else status
	if entries.is_empty():
		GameStyle.literal(rows,host._ex_text("回收站为空。删除或新建覆盖的存档会在这里保留7天。", "The Recycle Bin is empty. Deleted and replaced saves will be kept here for 7 days."),Vector2.ZERO,Vector2(870,100),19,GameStyle.MUTED)
	if not read_error.is_empty():
		GameStyle.literal(panel,Words.text(read_error),Vector2(28,551),Vector2(620,60),14,GameStyle.RED)
	GameStyle.button(panel,"BACK",Vector2(690,574),Vector2(242,48),host._pop_modal).grab_focus()

func _recycle_remaining(entry: Dictionary) -> String:
	if not bool(entry.valid): return host._ex_text("归档校验失败，文件已保留；无法恢复或自动清理。","Archive validation failed. Files are preserved; restore and automatic cleanup are blocked.")
	if bool(entry.clock_rollback): return host._ex_text("系统时间回退：暂停清理，存档仍可恢复。","System clock moved back. Cleanup is paused; this save can still be restored.")
	if bool(entry.expired): return host._ex_text("已满7天，等待下次安全清理。","7-day retention ended; awaiting safe cleanup.")
	var hours = ceili(float(entry.remaining_seconds)/3600.0)
	return host._ex_text("剩余 %d 天 %d 小时", "%d days %d hours remaining") % [hours / 24, hours % 24]

func _request_restore_profile(entry_id: String) -> void:
	var panel = host._push_modal("",Vector2(680,326))
	GameStyle.literal(panel,host._ex_text("恢复完整存档？","RESTORE THE COMPLETE SAVE?"),Vector2(28,22),Vector2(624,44),26)
	GameStyle.literal(panel,host._ex_text("恢复原有金币、装备、英雄成长与远征记录。不会合并或重复发放奖励。", "Restore the original gold, equipment, hero progress, and expedition record. Rewards are neither merged nor granted again."),Vector2(28,86),Vector2(624,118),18)
	var pair = GameStyle.action_pair(panel,"","CANCEL",238,func():
		if Game.restore_recycled_profile(entry_id):
			Words.set_locale(Game.profile.settings.get("language","zh_CN"))
			host.show_menu()
		else: host._show_save_error(),host._pop_modal)
	pair[0].text = host._ex_text("确认恢复","RESTORE SAVE")
	pair[0].name = "ConfirmRestoreSave"
	pair[1].grab_focus()
