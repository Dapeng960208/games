extends Node
## Headless-only node geometry and actual controller/UI actions, isolated save root.
var checks := 0
var failures: Array[String] = []
var app: Node
var viewport: SubViewport

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("SAVE RECYCLE UI: "+label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not Game.profile_path.contains("test_save_recycle_ui"):
		push_error("Save recycle UI requires its explicit disposable test path")
		get_tree().quit(2)
		return
	Game.run = null
	check(Game.new_profile(),"fresh isolated production ruleset profile")
	var original: Dictionary = Game.profile.duplicate(true)
	check(Game.new_profile(),"real new-profile overwrite automatically archives original")
	check(Game.recycle_entries().size()==1,"overwrite produces one entry")
	check(not Game.restore_recycled_profile(Game.recycle_entries()[0].entry_id),"controller refuses restore over current valid profile")
	check(Game.last_error=="STORAGE_RECYCLE_CONFLICT","controller reports specific conflict")
	viewport=SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	app=load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	viewport.add_child(app)
	await get_tree().process_frame
	for size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		viewport.size=size
		for locale: String in ["zh_CN","en"]:
			Words.set_locale(locale)
			app.show_menu()
			app.show_profile()
			await get_tree().process_frame
			await get_tree().process_frame
			var panel: Control = app.modals[-1].node.find_child("ProfileOverview",true,false)
			check(panel!=null,"profile screen exists "+locale+str(size))
			check(panel.find_child("OpenSaveRecycleBin",true,false)!=null,"recycle bin is discoverable from profile")
			check(not panel.find_child("DeleteSaveToRecycleBin",true,false).disabled,"valid camp save can be deleted")
			check_layout(panel,size)
			app.show_recycle_bin()
			await get_tree().process_frame
			await get_tree().process_frame
			panel=app.modals[-1].node.find_child("SaveRecycleBin",true,false)
			check_layout(panel,size)
			var restores := panel.find_children("Restore_*","Button",true,false)
			check(restores.size()==1 and restores[0].disabled,"valid current profile visibly disables restore")
			check(not Game.restore_recycled_profile(str(Game.recycle_entries()[0].entry_id)),"actual restore conflict remains rejected")
			app._show_save_error()
			await get_tree().process_frame
			panel=app.modals[-1].node.find_child("RestoreConflictError",true,false)
			check(panel!=null,"restore conflict has a dedicated dialog")
			check_layout(panel,size)
			var conflict_text := all_text(panel)
			check(conflict_text.contains(Words.text("RESTORE_CONFLICT_TITLE")) and conflict_text.contains(Words.text("STORAGE_RECYCLE_CONFLICT")),"conflict explains current save and safe next step")
			check(not conflict_text.contains(Words.text("ERROR_TITLE")) and not conflict_text.to_lower().contains("disk space") and not conflict_text.contains("磁盘"),"conflict never implies disk or permission failure")
			app._pop_modal()
			app._pop_modal()
			app._request_delete_profile()
			await get_tree().process_frame
			panel=app.modals[-1].node.find_child("DeleteSaveConfirmation",true,false)
			check_layout(panel,size)
			var texts := all_text(panel)
			check(texts.contains("7") and (texts.contains("后台") if locale=="zh_CN" else texts.contains("game is closed")),"delete confirmation explains 7-day retention and offline cleanup")
			app._pop_modal()
			app._request_new_profile()
			await get_tree().process_frame
			texts=all_text(app.modals[-1].node)
			check(texts.contains("7") and not texts.contains("cannot be undone"),"new-profile confirmation explains recoverability")
			app._clear_modals()
	# Exercise the same callbacks as real user clicks, including interrupted confirmation.
	app.show_profile()
	app._request_delete_profile()
	app._pop_modal()
	check(Game.has_profile,"cancel leaves current save intact")
	app._request_delete_profile()
	var confirm: Button = app.modals[-1].node.find_child("ConfirmRecycleSave",true,false)
	confirm.pressed.emit()
	await get_tree().process_frame
	check(not Game.has_profile and Game.recycle_entries().size()==2,"actual delete button commits archive and blank slot")
	var entry_id: String = Game.recycle_entries()[0].entry_id
	app._request_restore_profile(entry_id)
	var restore: Button = app.modals[-1].node.find_child("ConfirmRestoreSave",true,false)
	restore.pressed.emit()
	await get_tree().process_frame
	check(Game.has_profile,"actual restore button restores save")
	check(ProfileStore._serialize(Game.profile)==ProfileStore._serialize(original),"production v2 inventory and economy survive replacement/delete/restore")
	check(Game.recycle_entries().size()==1,"restoration consumes selected archive only")
	app.set_process(false)
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("SAVE RECYCLE UI: ",checks," checks; failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func all_text(node: Node) -> String:
	var text := ""
	for label: Node in node.find_children("*","Label",true,false): text += label.text+"\n"
	return text

func check_layout(panel: Control, size: Vector2i) -> void:
	var bounds := Rect2(Vector2.ZERO,Vector2(size))
	check(bounds.encloses(panel.get_global_rect()),"modal fits virtual viewport "+str(size))
	for button: Node in panel.find_children("*","Button",true,false):
		check(panel.get_global_rect().encloses(button.get_global_rect()),"button fits modal: "+str(button.name))
	for label: Node in panel.get_children():
		if not label is Label: continue
		check(label.position.x>=0 and label.position.y>=0 and label.position.x+label.size.x<=panel.size.x+1 and label.position.y+label.size.y<=panel.size.y+1,"label bounds fit modal")
		check(label.get_minimum_size().y<=label.size.y+1,"wrapped label height fits")
