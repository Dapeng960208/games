extends Node

const Routes = preload("res://scripts/world/route_generator.gd")
const Coordinator = preload("res://scripts/world/expedition_controller.gd")
const Chart = preload("res://scripts/ui/expedition_panel.gd")
const Rewards = preload("res://scripts/world/room_rewards.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")

class PreviewGame extends Node:
	var run := RunState.new()
	var state: Dictionary = {}
	func expedition_snapshot() -> Dictionary:
		return state.duplicate(true)

var checks := 0
var failures := 0
var longest_reward_lines := 0
var tallest_card := 0.0
var laid_out_rooms: Dictionary = {}
var viewport: SubViewport
var host: Control

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func frames(count: int = 2) -> void:
	for frame in count:
		await get_tree().process_frame

func run_checks() -> void:
	if not Game.profile_path.contains("test_reward_route_preview"):
		get_tree().quit(2)
		return
	var original_locale: String = Words.locale
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	host = Control.new()
	host.size = Vector2(1280,720)
	host.theme = MineStyle.make_theme()
	viewport.add_child(host)
	var game := PreviewGame.new()
	add_child(game)
	var controller := Coordinator.new(game)
	for locale: String in ["zh_CN","en"]:
		Words.locale = locale
		for hero: String in ["CH01","CH02","CH03"]:
			game.run.hero_id = hero
			for id: String in Catalog.room_ids():
				var preview: Dictionary = controller.preview(id)
				check(preview.reward == Rewards.preview(id,hero,locale == "en"), "controller uses the actual reward policy for %s %s %s" % [locale,hero,id])
				check(not str(preview.reward).contains("Coins, hero XP, mastery and carried equipment") and not str(preview.reward).contains("金币、角色经验、历练与待带回装备"), "uniform placeholder removed for "+id)
			for boss_id: String in Catalog.bosses():
				check(controller.preview(boss_id).reward == Rewards.preview(boss_id,hero,locale == "en"), "boss route preview also uses committed reward policy")
		game.run.hero_id = "CH03"
		for level: int in [1,15]:
			for biome: String in ["B01","B02","B03","B04"]:
				var route: Dictionary = Routes.generate(biome,41827,[],level)
				check(bool(route.get("valid",false)), "real route builds "+biome+" "+str(level))
				# Inspect both branch choices and the denser objective alternatives.
				for current: int in ([0,1] if level == 1 else [0,2]):
					game.state = {"route":route,"node_index":current,"phase":"cleared","completed_nodes":range(current+1),"difficulty":0}
					var chart := Chart.new()
					chart.position = Vector2(132,148)
					chart.size = Vector2(1016,480)
					host.add_child(chart)
					chart.configure(controller,true)
					await frames()
					check(chart.find_children("RouteNode*","Panel",true,false).size() == (6 if level == 1 else 12), "full real timeline preserved "+str(level))
					var scroll: ScrollContainer = chart.find_child("RouteOptions",true,false)
					var heading: Label = chart.find_child("RouteOptionsHeading",true,false)
					var close: Button = chart.find_child("CloseRoute",true,false)
					check(scroll.clip_contents, "route alternatives clip only at scroll viewport")
					check(heading.get_global_rect().end.y <= scroll.get_global_rect().position.y, "heading stays above choices")
					check(scroll.get_global_rect().end.y < close.get_global_rect().position.y, "choices stay above close button")
					check(Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(chart.get_global_rect()), "route chart remains inside the game viewport")
					var cards: Array[Node] = chart.find_children("Choose_*","Button",true,false)
					check(cards.size() == controller.next_options().size(), "every real route option is shown")
					for card: Button in cards:
						tallest_card = maxf(tallest_card,card.size.y)
						var previous_bottom := 0.0
						for label: Label in card.get_children():
							check(not label.clip_text and label.max_lines_visible == -1, "no text hidden in "+card.name+"/"+label.name)
							check(label.position.y >= previous_bottom, "label order avoids overlap in "+card.name+"/"+label.name)
							check(Rect2(Vector2.ZERO,card.size).encloses(label.get_rect()), "label geometry fits real button in "+card.name+"/"+label.name)
							var required_height := label.get_line_count()*label.get_line_height()+maxi(0,label.get_line_count()-1)*label.get_theme_constant("line_spacing")
							check(label.size.y+1.0 >= required_height, "all shaped lines fit label height in "+card.name+"/"+label.name+" lines="+str(label.get_line_count()))
							previous_bottom = label.get_rect().end.y
							if label.name == "RouteReward":
								longest_reward_lines = maxi(longest_reward_lines,label.get_line_count())
								var room_id := String(card.name).trim_prefix("Choose_")
								laid_out_rooms[locale+":"+room_id] = true
								check(label.text == Rewards.preview(room_id,"CH03",locale == "en"), "full visible reward equals policy")
					# Scrolling must expose the last reward and risk, even in long English.
					scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
					await frames()
					if not cards.is_empty():
						var last: Button = cards[-1]
						var reward: Label = last.find_child("RouteReward",true,false)
						check(scroll.get_global_rect().encloses(reward.get_global_rect()), "last option reward reachable in scroll viewport")
					if locale == "en" and level == 15 and biome == "B01" and current == 0 and DisplayServer.get_name() != "headless":
						await RenderingServer.frame_post_draw
						DirAccess.make_dir_recursive_absolute("res://artifacts")
						viewport.get_texture().get_image().save_png("res://artifacts/reward_route_12_en.png")
					chart.free()
					await frames(1)
	for locale: String in ["zh_CN","en"]:
		for room_id: String in Catalog.room_ids():
			check(laid_out_rooms.has(locale+":"+room_id), "all template rewards receive actual shaped layout checks "+locale+" "+room_id)
	game.free()
	Words.locale = original_locale
	host.free()
	viewport.free()
	await frames()
	print("REWARD ROUTE PREVIEW: %d checks, %d failures; longest reward %d lines; tallest card %.0fpx" % [checks,failures,longest_reward_lines,tallest_card])
	get_tree().quit(1 if failures else 0)
