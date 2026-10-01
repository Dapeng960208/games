extends Node
## GPU-only visual comparison, not a physics or combat acceptance test.
## Example (after --):
## --test-profile=res://tools/godot/test-runs/walk_review/test_hero_walk_review.json
## --walk-review-metadata=res://artifacts/CH01_walk_candidate.json
## Omit metadata to use CH01_walk_v1.json. Manifest hero_id selects CH01/02/03;
## an absent hero_id retains CH01 compatibility.
## Optional: --walk-review-seconds=5; --walk-review-hold keeps the preview open.
## MovieWriter flags belong before --; this scene never edits or composites PNGs.

const Visual = preload("res://scripts/combat/hero_visual.gd")
const WalkAtlas = preload("res://scripts/combat/hero_walk_atlas.gd")
const WorldCamera = preload("res://scripts/combat/world_camera.gd")
const DEFAULT_HERO := "CH01"
const DEFAULT_METADATA := "res://assets/generated/heroes/CH01_walk_v1.json"
const WINDOW_SIZE := Vector2i(1280,720)
const VIEW_SIZE := Vector2i(1192,112)
const OUTPUT_ROOT := "res://artifacts/hero_walk_review"

class ReviewActor extends Node2D:
	const BodyVisual = preload("res://scripts/combat/hero_visual.gd")
	var frame: Dictionary = {}
	var hero := "CH01"
	var bank := "front"
	var distance := 0.0
	var speed := 0.0

	func _draw() -> void:
		if frame.is_empty():
			return
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var aim := Vector2(1,1 if bank == "front" else -1).normalized()
		# Exact production idle motion at this shared distance and velocity.
		# _draw_action_frame suppresses this offset for authored walk frames.
		var bob: float = absf(sin(distance*BodyVisual.STRIDE_PER_WORLD_UNIT))*(1.5 if hero == "CH01" else 2.4)
		var lean := Vector2(speed*.007,-bob)
		BodyVisual._draw_action_frame(self,frame,hero,aim,lean,{"phase":"idle","progress":0.0},0.0)

class ReviewStage extends Node2D:
	var camera: Camera2D
	var old_actor: ReviewActor
	var new_actor: ReviewActor
	var bank := "front"
	var view_zoom := 1.0
	var travel := 0.0

	func _draw() -> void:
		# The actors and camera move together; the world grid reveals actual
		# scripted world displacement without changing the review framing.
		var half_width: float = 596.0/view_zoom
		var left: float = travel-half_width
		var right: float = travel+half_width
		draw_line(Vector2(left,8),Vector2(right,8),Color("4a6063"),1.0)
		var first: int = floori(left/40.0)
		var last: int = ceili(right/40.0)
		for tick: int in range(first,last+1):
			var x: float = tick*40.0
			draw_line(Vector2(x,-5),Vector2(x,17),Color("283b40"),1.0)
		for actor: ReviewActor in [old_actor,new_actor]:
			var origin := Vector2(actor.position.x,8)
			draw_line(origin-Vector2(6,0),origin+Vector2(6,0),Color("90b8ae"),1.0)
			draw_line(origin-Vector2(0,3),origin+Vector2(0,3),Color("90b8ae"),1.0)

	func advance_view(distance: float, speed: float, selected_frame: Dictionary) -> void:
		travel = distance
		camera.position = Vector2(distance,-38)
		old_actor.position = Vector2(distance-298.0/view_zoom,0)
		new_actor.position = Vector2(distance+298.0/view_zoom,0)
		new_actor.frame = selected_frame
		for actor: ReviewActor in [old_actor,new_actor]:
			actor.distance = distance
			actor.speed = speed
			actor.queue_redraw()
		camera.force_update_scroll()
		queue_redraw()

var _hero := DEFAULT_HERO
var _source_path := DEFAULT_METADATA
var _source_text := ""
var _manifest_copy := ""
var _output_directory := ""
var _clip: Dictionary = {}
var _stages: Array[ReviewStage] = []
var _frame_labels: Array[Label] = []
var _metrics: Label
var _elapsed := 0.0
var _distance := 0.0
var _speed := 0.0
var _duration := 5.0
var _hold := false
var _running := false
var _finishing := false
var _capture_pending := false
var _captured_keys: Dictionary = {}
var _captures: Array[Dictionary] = []
var _failures: Array[String] = []
var _contact_sheet_path := ""

func _ready() -> void:
	set_process(false)
	call_deferred("_begin")

func _begin() -> void:
	var requested_profile := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="):
			requested_profile = argument.trim_prefix("--test-profile=")
		elif argument.begins_with("--walk-review-metadata="):
			_source_path = argument.trim_prefix("--walk-review-metadata=").replace("\\","/")
		elif argument.begins_with("--walk-review-seconds="):
			_duration = argument.trim_prefix("--walk-review-seconds=").to_float()
		elif argument == "--walk-review-hold":
			_hold = true
	if requested_profile.is_empty() or not requested_profile.contains("test_hero_walk_review") or Game.profile_path != requested_profile:
		_abort("Require an isolated --test-profile path containing test_hero_walk_review; Game must use that exact path.")
		return
	if DisplayServer.get_name() == "headless":
		print("HERO_WALK_REVIEW SKIP: visual-only scene requires GPU rendering; headless does not load candidates, create a run, or capture images. No physics/animation quality assertion was performed.")
		get_tree().quit(0)
		return
	if not is_finite(_duration) or _duration <= 0.0:
		_abort("--walk-review-seconds must be a finite positive number.")
		return
	if _source_path.is_empty() or not (_source_path.begins_with("res://") or _source_path.is_absolute_path()) or not FileAccess.file_exists(_source_path):
		_abort("Provide --walk-review-metadata=<existing res:// or absolute JSON path>.")
		return
	_source_text = FileAccess.get_file_as_string(_source_path)
	var parsed: Variant = JSON.parse_string(_source_text)
	if not parsed is Dictionary:
		_abort("Candidate metadata must be a JSON object.")
		return
	var requested_hero: Variant = parsed.get("hero_id",DEFAULT_HERO)
	if typeof(requested_hero) != TYPE_STRING or str(requested_hero) not in ["CH01","CH02","CH03"]:
		_abort("Candidate hero_id must be CH01, CH02 or CH03; only an absent hero_id defaults to CH01.")
		return
	_hero = str(requested_hero)
	var run_id: String = Time.get_datetime_string_from_system().replace(":","").replace("-","")+"_"+str(Time.get_ticks_usec())
	var isolated_directory: String = requested_profile.get_base_dir().path_join("walk_review_"+run_id)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated_directory)) != OK:
		_abort("Cannot create isolated metadata directory: "+isolated_directory)
		return
	_manifest_copy = isolated_directory.path_join("candidate_enabled_for_review.json")
	# Only this isolated JSON copy is enabled. All source paths, frame lists,
	# regions and anchors are preserved; no PNG is copied, edited or assembled.
	var candidate: Dictionary = parsed.duplicate(true)
	candidate["enabled"] = true
	var file: FileAccess = FileAccess.open(_manifest_copy,FileAccess.WRITE)
	if file == null:
		_abort("Cannot write isolated candidate manifest.")
		return
	file.store_string(JSON.stringify(candidate,"\t"))
	file.close()
	_clip = WalkAtlas.load_clip(_manifest_copy)
	if _clip.is_empty():
		_abort("Production HeroWalkAtlas rejected the candidate copy; both banks must be valid. Relative texture paths are not rebased.")
		return
	for bank: String in ["front","back"]:
		if Visual.action_frame_info(_hero,bank,"idle").is_empty():
			_abort("Production "+_hero+" "+bank+" idle action frame is unavailable.")
			return
	if not Game.new_profile() or not Game.select_hero(_hero) or not Game.start_run():
		_abort("Cannot create the isolated default "+_hero+" run for its real move_speed stat.")
		return
	_speed = float(Game.run.stats.get("move_speed",0.0))
	if not is_finite(_speed) or _speed <= 0.0:
		_abort("Isolated "+_hero+" run did not expose a positive move_speed stat.")
		return
	_output_directory = OUTPUT_ROOT.path_join(_hero+"_"+run_id)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_directory)) != OK:
		_abort("Cannot create screenshot directory.")
		return
	_build_display()
	_advance_views()
	await _capture_contact_sheet()
	_running = true
	set_process(true)
	_capture_current_frames()
	print("HERO_WALK_REVIEW START: hero=",_hero," speed=",_speed," world_px/s cycle=",_clip.cycle_distance," front=",_clip.banks.front.size()," back=",_clip.banks.back.size()," output=",ProjectSettings.globalize_path(_output_directory))

func _label(text_value: String, at: Vector2, width: float, font_size: int = 16, tint: Color = Color("dce8e5"), target: Node = null) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = Vector2(width,25)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	if target == null:
		add_child(label)
	else:
		target.add_child(label)
	return label

func _build_display() -> void:
	var window: Window = get_window()
	window.size = WINDOW_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.unresizable = true
	window.title = _hero+" walk candidate / actual Godot GPU rendering"
	var background := ColorRect.new()
	background.color = Color("0c171c")
	background.size = Vector2(WINDOW_SIZE)
	add_child(background)
	_label(_hero+"  /  WALK CANDIDATE REVIEW",Vector2(44,14),1150,23)
	_label("LEFT: production static idle + old bob     RIGHT: candidate registered walk frames",Vector2(44,44),1150,17)
	_metrics = _label("",Vector2(44,70),1150,15,Color("a6c4be"))
	for zoom_value: float in [1.0,WorldCamera.WORLD_ZOOM.x]:
		for bank: String in ["front","back"]:
			var row: int = _stages.size()
			var y: float = 98.0+float(row)*138.0
			_label("%s | zoom %.2f | 88 world px = %.1f render px" % [bank.to_upper(),zoom_value,88.0*zoom_value],Vector2(44,y),600,15)
			var frame_label: Label = _label("",Vector2(663,y),580,15,Color("edcf94"))
			_frame_labels.append(frame_label)
			var container := SubViewportContainer.new()
			container.position = Vector2(44,y+23)
			container.size = Vector2(VIEW_SIZE)
			container.stretch = false
			add_child(container)
			var viewport := SubViewport.new()
			viewport.size = VIEW_SIZE
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			viewport.disable_3d = true
			container.add_child(viewport)
			var stage := ReviewStage.new()
			stage.bank = bank
			stage.view_zoom = zoom_value
			viewport.add_child(stage)
			stage.camera = Camera2D.new()
			stage.camera.zoom = Vector2.ONE*zoom_value
			stage.camera.position_smoothing_enabled = false
			stage.add_child(stage.camera)
			stage.camera.make_current()
			stage.old_actor = ReviewActor.new()
			stage.old_actor.hero = _hero
			stage.old_actor.bank = bank
			stage.old_actor.frame = Visual.action_frame_info(_hero,bank,"idle")
			stage.add_child(stage.old_actor)
			stage.new_actor = ReviewActor.new()
			stage.new_actor.hero = _hero
			stage.new_actor.bank = bank
			stage.add_child(stage.new_actor)
			_stages.append(stage)
	_label("Visual fixture: scripted horizontal travel + tracking camera; front/back aim. No collision, input, skill or combat validation.",Vector2(44,652),1200,15,Color("b0bdbb"))
	_label("Production sampler / region / foot / mipmaps / draw function. Each unique sampled frame is saved from the GPU. ESC exits.",Vector2(44,678),1200,15,Color("b0bdbb"))

func _capture_contact_sheet() -> void:
	# This sheet is a separate Godot render target. It draws the original PNG
	# regions with production code, without image editing or screenshot stitching.
	var sheet := SubViewport.new()
	sheet.size = Vector2i(1280,840)
	sheet.disable_3d = true
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sheet)
	var background := ColorRect.new()
	background.color = Color("0c171c")
	background.size = Vector2(sheet.size)
	sheet.add_child(background)
	_label(_hero+"  /  AUTHORED FRAME CONTACT SHEET",Vector2(44,14),1192,23,Color("dce8e5"),sheet)
	_label("First column: production idle reference. Remaining columns: every actual candidate sequence entry, in order.",Vector2(44,48),1192,16,Color("b0bdbb"),sheet)
	_label("Source pixels are sampled directly; frame counts and source indices are literal. Contact / lifted-foot quality requires visual review.",Vector2(44,75),1192,15,Color("b0bdbb"),sheet)
	var row := 0
	for zoom_value: float in [1.0,WorldCamera.WORLD_ZOOM.x]:
		for bank: String in ["front","back"]:
			var y: float = 108.0+float(row)*168.0
			var count: int = _clip.banks[bank].size()
			var columns: int = count+1
			var column_width: float = float(VIEW_SIZE.x)/float(columns)
			_label("%s | zoom %.2f | 88 world px = %.1f render px | %d sequence entries / %d unique source regions" % [bank.to_upper(),zoom_value,88.0*zoom_value,count,_unique_source_frames(bank)],Vector2(44,y),1192,15,Color("a6c4be"),sheet)
			var container := SubViewportContainer.new()
			container.position = Vector2(44,y+45)
			container.size = Vector2(VIEW_SIZE)
			container.stretch = false
			sheet.add_child(container)
			var viewport := SubViewport.new()
			viewport.size = VIEW_SIZE
			viewport.disable_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			container.add_child(viewport)
			var camera := Camera2D.new()
			camera.zoom = Vector2.ONE*zoom_value
			camera.position = Vector2(0,-38)
			viewport.add_child(camera)
			camera.make_current()
			camera.force_update_scroll()
			var ground := Line2D.new()
			ground.points = PackedVector2Array([Vector2(-596.0/zoom_value,8),Vector2(596.0/zoom_value,8)])
			ground.width = 1.0
			ground.default_color = Color("4a6063")
			viewport.add_child(ground)
			for column: int in columns:
				var screen_x: float = (float(column)+.5)*column_width
				var actor := ReviewActor.new()
				actor.hero = _hero
				actor.bank = bank
				actor.position = Vector2((screen_x-596.0)/zoom_value,0)
				var label_text := "Production idle"
				if column == 0:
					actor.frame = Visual.action_frame_info(_hero,bank,"idle")
				else:
					var sample_distance: float = (float(column)-.5)*float(_clip.cycle_distance)/float(count)
					actor.frame = WalkAtlas.sample_clip(_clip,bank,sample_distance)
					label_text = "%02d/%02d | source %d" % [column,count,int(actor.frame.frame_index)]
				viewport.add_child(actor)
				_label(label_text,Vector2(44+screen_x-column_width*.5+12,y+22),column_width-12,14,Color("edcf94"),sheet)
			row += 1
	_label("GPU-rendered review sheet. No PNG editing, pose interpolation, frame invention, physics or combat assertions.",Vector2(44,793),1192,15,Color("b0bdbb"),sheet)
	# One full draw initializes child render targets; the second confirms the
	# parent viewport has sampled their populated textures on every backend.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_contact_sheet_path = _output_directory.path_join("contact_sheet.png")
	var image: Image = sheet.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(_contact_sheet_path) != OK:
		_failures.append("Failed GPU contact sheet: "+_contact_sheet_path)
		_contact_sheet_path = ""
	else:
		print("HERO_WALK_REVIEW CONTACT_SHEET: ",_contact_sheet_path)
	sheet.queue_free()

func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_distance += _speed*delta
	_advance_views()
	_capture_current_frames()
	if _elapsed >= _duration and not _hold:
		_finish()

func _advance_views() -> void:
	_metrics.text = "Fresh %s move_speed %.2f world px/s | cycle %.2f world px / %.3f s | distance %.2f | t %.2f s" % [_hero,_speed,float(_clip.cycle_distance),float(_clip.cycle_distance)/_speed,_distance,_elapsed]
	for row: int in _stages.size():
		var stage: ReviewStage = _stages[row]
		var selected: Dictionary = WalkAtlas.sample_clip(_clip,stage.bank,_distance)
		stage.advance_view(_distance,_speed,selected)
		_frame_labels[row].text = "Candidate %02d/%02d | source index %d | %d unique source regions" % [int(selected.clip_frame)+1,int(selected.frame_count),int(selected.frame_index),_unique_source_frames(stage.bank)]

func _unique_source_frames(bank: String) -> int:
	var unique: Dictionary = {}
	for frame: Dictionary in _clip.banks[bank]:
		unique[str(frame.path)+"|"+str(frame.region)] = true
	return unique.size()

func _frame_snapshot() -> Dictionary:
	var snapshot: Dictionary = {"hero":_hero,"elapsed_seconds":_elapsed,"distance_world_px":_distance,"banks":{}}
	for bank: String in ["front","back"]:
		var frame: Dictionary = WalkAtlas.sample_clip(_clip,bank,_distance)
		snapshot.banks[bank] = {"clip_frame":frame.clip_frame,"frame_count":frame.frame_count,"source_index":frame.frame_index,"source_texture":frame.path,"source_region":[frame.region.position.x,frame.region.position.y,frame.region.size.x,frame.region.size.y],"foot_local":[frame.anchors.foot.x,frame.anchors.foot.y],"source_body_height":frame.source_body_height}
	return snapshot

func _capture_current_frames() -> void:
	if _capture_pending:
		return
	var snapshot: Dictionary = _frame_snapshot()
	var key: String = "front_%02d_back_%02d" % [int(snapshot.banks.front.clip_frame),int(snapshot.banks.back.clip_frame)]
	if _captured_keys.has(key):
		return
	_captured_keys[key] = true
	_capture_pending = true
	_capture_frame(key,snapshot)

func _capture_frame(key: String, snapshot: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var path: String = _output_directory.path_join(key+".png")
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		_failures.append("Failed GPU screenshot: "+path)
	else:
		snapshot["screenshot"] = path
		_captures.append(snapshot)
		print("HERO_WALK_REVIEW CAPTURE: ",path)
	_capture_pending = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _running:
		_finish()

func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	_running = false
	# Flush the last queued rendering/capture before writing its audit manifest.
	await RenderingServer.frame_post_draw
	var report: Dictionary = {
		"kind":"GPU visual comparison only; no physics or combat acceptance",
		"hero":_hero,"profile_path":Game.profile_path,"source_manifest":_source_path,
		"source_manifest_unchanged":FileAccess.get_file_as_string(_source_path) == _source_text,
		"isolated_enabled_manifest":_manifest_copy,"production_discovery_cache_changed":false,
		"move_speed_world_px_per_second":_speed,"speed_source":"fresh isolated "+_hero+" Game.run.stats.move_speed",
		"cycle_distance_world_px":_clip.cycle_distance,"elapsed_seconds":_elapsed,
		"body_height_world_px":Visual.GENERATED_HEIGHT,"view_zooms":[1.0,WorldCamera.WORLD_ZOOM.x],
		"render_size":[WINDOW_SIZE.x,WINDOW_SIZE.y],"front_unique_source_regions":_unique_source_frames("front"),
		"back_unique_source_regions":_unique_source_frames("back"),"contact_sheet":_contact_sheet_path,"captures":_captures,"failures":_failures,
		"limitations":["Scripted displacement; no player physics, wall blocking, input, skill priority or gameplay exercised.","Captures identify actual source indices; contact/lift quality requires visual inspection, not inferred pose labels.","No source PNG editing, source atlas assembly, interpolation or invented frames."]
	}
	var file: FileAccess = FileAccess.open(_output_directory.path_join("review.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	else:
		_failures.append("Could not write review.json")
	print("HERO_WALK_REVIEW COMPLETE: captures=",_captures.size()," failures=",_failures.size()," output=",ProjectSettings.globalize_path(_output_directory))
	WalkAtlas._clips.erase(_manifest_copy)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _abort(message: String) -> void:
	push_error("HERO_WALK_REVIEW: "+message)
	get_tree().quit(2)
