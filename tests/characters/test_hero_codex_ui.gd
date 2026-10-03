extends Node
## Focused read-only regression for the illustrated hero/skill and codex views.
const Codex = preload("res://scripts/presentation/screens/monster_codex.gd")
const SkillInspect = preload("res://scripts/presentation/screens/skill_inspection.gd")
const Dossier = preload("res://scripts/presentation/screens/hero_dossier.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
const Character = preload("res://scripts/presentation/screens/character_panel.gd")
const Sheet = preload("res://scripts/presentation/screens/stat_sheet.gd")
var checks := 0
var failures := 0
var game: Node
var app: Node
var guide: Control

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(90).timeout.connect(func(): push_error("Hero codex UI timeout"); get_tree().quit(1))

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("HERO CODEX UI: "+message)

func frames(count: int = 3) -> void:
	for index: int in count: await get_tree().process_frame

func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/codex-skills")
	check(get_viewport().get_texture().get_image().save_png("res://artifacts/codex-skills/"+id+".png") == OK,"actual capture saved: "+id)

func _run() -> void:
	game = get_tree().root.get_node("Game")
	if not game.profile_path.contains("test_hero_codex_ui"): get_tree().quit(2); return
	check(game.new_profile(),"isolated profile")
	var before: Dictionary = game.profile.duplicate(true)
	var saved := FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path))
	var canvas := Control.new()
	canvas.theme = GameStyle.make_theme()
	get_tree().root.add_child(canvas)
	guide = Codex.new()
	canvas.add_child(guide)
	var closed := {"value":false}
	guide.configure(func(): closed.value = true)
	await frames()
	check(Codex.entry_ids().size() == 58,"54 actual enemy and four actual boss IDs")
	check(guide.filtered_ids().size() == 58,"all entries visible initially")
	for id: String in Codex.entry_ids():
		guide._show_entry(id)
		var profile: Dictionary = guide.detail.get_meta("resolved_profile")
		var expected: Dictionary = Codex.resolved_entry(id,guide.preview_level,guide.difficulty,2)
		check(profile == expected,id+" inspector uses production profile")
		check(guide.find_child("Portrait_"+id,true,false).texture != null,id+" original portrait loads")
		var portrait := guide.detail.find_child("Portrait_"+id,true,false) as TextureRect
		check(portrait != null and portrait.size.x <= 184.1 and portrait.size.y <= 184.1,id+" portrait respects fixed inspector bounds")
		var art_frame: Control = portrait.get_parent()
		check(art_frame.clip_contents,id+" art has a hard clipping boundary")
		check(Rect2(Vector2.ZERO,art_frame.size).grow(0.1).encloses(portrait.get_rect()),id+" texture remains inside illustration box")
		if id.begins_with("BO"):
			var rendered: Dictionary = preload("res://scripts/presentation/monsters/enemy_art.gd").entry_for(id)
			if portrait.get_meta("dedicated_codex_art",false):
				check(portrait.texture.get_width() >= 512 and portrait.texture.get_height() >= 512,id+" dedicated boss portrait has native detail resolution")
			else:
				check(portrait.texture is AtlasTexture and portrait.texture.atlas == rendered.texture and portrait.texture.region == rendered.region,id+" codex uses the actual battle body, not the legacy fallback")
			var skills: Array[Dictionary] = Codex.boss_skill_entries(id,0)
			var locked := 0
			for skill: Dictionary in skills:
				check(not str(skill.description).is_empty() and not skill.command.is_empty(),id+" source-backed skill "+str(skill.id))
				if not bool(skill.unlocked): locked += 1
			check(locked == 4,id+" has four difficulty-gated abilities")
		else:
			check(not str(profile.get("tell","")).is_empty() and not str(profile.get("counter","")).is_empty(),id+" source-backed tell and counterplay")
	for biome: String in ["B01","B02","B03","B04"]:
		guide._set_biome(biome)
		check(guide.filtered_ids().size() == {"B01":10,"B02":13,"B03":16,"B04":19}[biome],biome+" progressive ordinary roster plus one boss")
	guide._set_biome("all")
	guide.kind_filter = "boss"; guide._refresh_grid()
	check(guide.filtered_ids().size() == 4,"boss-only filter")
	guide.kind_filter = "all"; guide.search_query = "m36"; guide._refresh_grid()
	check(guide.filtered_ids() == ["M36"],"case-insensitive ID search")
	guide.search_query = "nothing_matches"; guide._refresh_grid()
	check(guide.filtered_ids().is_empty(),"empty search has an intentional empty state")
	guide.search_query = ""; guide._refresh_grid()
	guide._show_entry("BO04")
	guide.difficulty = 4; guide._show_entry("BO04",false)
	check(guide.detail.get_meta("resolved_profile").difficulty == 4,"difficulty updates actual profile")
	for skill: Dictionary in Codex.boss_skill_entries("BO04",4): check(bool(skill.unlocked),"D4 reveals every boss ability")
	await frames()
	await capture("codex-zh-boss")
	guide._set_biome("B01"); guide._show_entry("M01")
	await frames()
	await capture("codex-zh-enemy")
	Words.set_locale("en")
	guide._show_entry("BO02")
	await frames()
	await capture("codex-en-boss")
	guide.find_child("CloseMonsterCodex",true,false).pressed.emit()
	check(closed.value,"close callback fires")
	canvas.queue_free()
	await frames()
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	await frames()
	for locale: String in ["zh_CN","en"]:
		Words.set_locale(locale)
		app.show_workshop("heroes")
		await frames()
		var workshop: Control = app.screen.find_child("Workshop",true,false)
		check(workshop.find_children("Preview_CH*","Button",true,false).size() == 3,"three real hero choices "+locale)
		var sheet := workshop.find_child("CharacterStatSheet",true,false)
		check(sheet != null and sheet.find_children("HeroAttribute_*","Label",true,false).size() == 27,"complete v2 stat source table "+locale)
		workshop.find_child("Preview_CH03",true,false).pressed.emit()
		await frames()
		check(workshop.find_child("CharacterStatSheet",true,false).get_meta("breakdown").hero_id == "CH03","hero preview switches without changing selection")
		await capture("heroes-"+locale)
		app.show_workshop("skills")
		await frames()
		workshop = app.screen.find_child("Workshop",true,false)
		check(workshop.find_child("InspectSkill_q",true,false) != null,"new skill ledger integrated "+locale)
		for slot: String in ["q","secondary","f","ultimate"]:
			var button := workshop.find_child("InspectSkill_"+slot,true,false)
			if button != null: button.pressed.emit()
			await frames()
			var description := workshop.find_child("InspectedSkillDescription",true,false)
			var expected := SkillInspect.ledger_entry(str(game.profile.selected_hero),game.hero_level(str(game.profile.selected_hero)),game.selected_stats(),slot,game.hero_branches(str(game.profile.selected_hero)))
			check(description != null and description.text == expected.description,"skill ledger uses actual skill/branch values "+slot)
		await capture("skills-"+locale)
	check(game.profile == before,"browsing never mutates profile")
	check(FileAccess.get_file_as_bytes(AssetCatalog.resolve(game.profile_path)) == saved,"browsing never writes save")
	app.queue_free()
	await frames()
	check(game.start_run(),"isolated live character session")
	var character := Character.new()
	character.theme = GameStyle.make_theme()
	get_tree().root.add_child(character)
	character.configure(null,func(): closed.value = true)
	await frames()
	check(character.find_children("Equipment_*","Button",true,false).size() == 8,"combat dossier displays all eight equipment slots")
	check(character.find_children("Attribute_*","Label",true,false).size() == 27,"combat dossier keeps all 27 v2 attributes")
	for slot: String in ["q","secondary","f","ultimate"]:
		character.find_child("DossierSkill_"+slot,true,false).pressed.emit()
		check(not character.detail_body.text.is_empty(),"combat skill description "+slot)
	character.find_child("DossierAllStats",true,false).pressed.emit()
	check(character.find_child("CharacterStatSheet",true,false) != null,"combat dossier returns from skill to complete attributes")
	await frames()
	await capture("character-en")
	character.queue_free()
	await frames()
	print("HERO CODEX UI: %d checks, %d failures; renderer=%s" % [checks,failures,DisplayServer.get_name()])
	get_tree().quit(0 if failures == 0 else 1)
