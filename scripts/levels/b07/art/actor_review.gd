extends RefCounted
## L37-only review of discrete key poses, never a complete animation bank.
## Ground roots and anatomy scales affect drawing only. Commands stay read-only.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Props = preload("res://scripts/domain/combat/combat_properties.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const MANIFEST := "asset://levels/b07/registration/l37_review_actors.json"
const IDS := ["B07-M01", "B07-M02", "B07-M03"]
const FLAGS := ["--b07-art-trial", "--b07-midground-trial", "--b07-convergence-review"]
static var _manifest: Dictionary = {}

static func enabled_for(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not Rules.b07_candidate_enabled(): return false
	for flag: String in FLAGS:
		if flag not in OS.get_cmdline_user_args(): return false
	if str(Props.read(actor,"enemy_id","")) not in IDS or bool(Props.read(actor,"static_actor",false)): return false
	var room: Variant = Props.read(actor,"room")
	var layout: Dictionary = Props.read(room,"layout",{})
	return str(Props.read(room,"layout_id","")) == "L37" and bool(layout.get("b07_candidate",false)) and str(layout.get("blueprint_room_id","")) == "L37"

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var path: String = AssetCatalog.resolve(MANIFEST)
		if not FileAccess.file_exists(path): return {}
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw is Dictionary and raw.get("version") == 1 and raw.get("asset_family") == "storybook_2_5d_v1" and raw.get("room_id") == "L37":
			_manifest = raw
	return _manifest

static func entry(actor: Node2D) -> Dictionary:
	if not enabled_for(actor): return {}
	var identity: String = str(Props.read(actor,"enemy_id",""))
	var idle: Dictionary = _frame(identity,"idle")
	if idle.is_empty(): return {}
	return {"texture":idle.texture,"texture_path":idle.texture_path,"region":idle.region,"foot":idle.foot,
		"source_height":idle.reference_height,"source_family":"storybook_2_5d_v1","biome_id":"B07","visual_clan":"lizard",
		"individual_body":true,"b07_native_bank":true,"b07_review_bank":true,
		"animation_complete":false,"runtime_quality_gate_passed":false}

static func bank(actor: Node2D) -> Dictionary:
	if not enabled_for(actor): return {}
	var identity: String = str(Props.read(actor,"enemy_id",""))
	var record: Dictionary = manifest().get("identities",{}).get(identity,{})
	var clips: Dictionary = {}
	for pose: String in record.get("frames",{}):
		var frame: Dictionary = _frame(identity,pose)
		if not frame.is_empty(): clips[pose] = [frame]
	if not clips.has("idle"): return {}
	# No walk/attack aliases: one still per semantic state is not animation.
	return {"clips":clips,"texture":clips.idle[0].texture,"body_height":clips.idle[0].reference_height,
		"source_family":"storybook_2_5d_v1","facing":"right","b07_native_bank":true,"b07_review_bank":true,
		"animation_complete":false,"continuous_animation_sets_complete":0,"runtime_quality_gate_passed":false}

static func _frame(identity: String, pose: String) -> Dictionary:
	if identity not in IDS: return {}
	var record: Dictionary = manifest().get("identities",{}).get(identity,{})
	var source: Dictionary = record.get("frames",{}).get(pose,{})
	if not source.has_all(["texture","region","ground_root","core_anchor","source_pose_scale"]): return {}
	var filename: String = str(source.texture)
	if not filename.begins_with("asset://levels/b07/enemies/"+identity.trim_prefix("B07-").to_lower()+"/") or not filename.ends_with(".png"): return {}
	for key: String in ["ground_root","core_anchor"]:
		if not _numbers(source.get(key),2): return {}
	if not _numbers(source.region,4): return {}
	var reference: float = float(record.get("reference_body_height_px",0))
	var pose_scale: float = float(source.source_pose_scale)
	if not is_finite(reference) or reference <= 0 or not is_finite(pose_scale) or pose_scale < .5 or pose_scale > 1.5: return {}
	var texture: Texture2D = Sampler.sampled(filename)
	if texture == null: return {}
	var region := Rect2(float(source.region[0]),float(source.region[1]),float(source.region[2]),float(source.region[3]))
	var root := Vector2(source.ground_root[0],source.ground_root[1])
	var canvas := Rect2(Vector2.ZERO,texture.get_size())
	if not region.has_area() or not canvas.encloses(region) or not canvas.has_point(root): return {}
	return {"name":pose,"texture":texture,"texture_path":filename,"region":region,"foot":root,
		"core":Vector2(source.core_anchor[0],source.core_anchor[1]),"source_pose_scale":pose_scale,
		"reference_height":reference,"ground_root_kind":str(source.get("ground_root_kind","foot_contact_midpoint")),
		"animation_complete":false,"runtime_quality_gate_passed":false}

static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number: Variant in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

static func select_frame(actor: Node2D, source_bank: Dictionary) -> Dictionary:
	if not enabled_for(actor) or not bool(source_bank.get("b07_review_bank",false)): return {}
	var clips: Dictionary = source_bank.get("clips",{})
	var brain: Variant = Props.read(actor,"brain")
	var command: Dictionary = brain.current_skill() if brain is Object and brain.has_method("current_skill") else {}
	var phase: String = str(command.get("phase","idle"))
	var key: String = "idle"
	# The actual follow-up queue/flash owns tail presentation; no synthetic clock.
	# Keep the spear's own release visible before its delayed tail warning.
	if phase not in ["telegraph","locked","execute"]:
		key = _tail_pose(actor)
	if key == "idle" and bool(command.get("active",false)):
		var action: String = str(command.get("ability_id","")).get_slice(":",1)
		if action in ["sun_spear","camouflage_leap","returning_disc"] and phase in ["telegraph","locked","execute","recovery"]:
			key = action+":"+("telegraph" if phase == "locked" else phase)
	if key == "idle" and _disc_in_flight(actor):
		# Recovery is empty-handed. Never restore a held disc while the actual
		# outgoing/returning object or its queued return is still present.
		key = "returning_disc:recovery"
	var frames: Array = clips.get(key,clips.get("idle",[]))
	return frames[0] if not frames.is_empty() else {}

static func _tail_pose(actor: Node2D) -> String:
	if str(Props.read(actor,"enemy_id","")) != "B07-M01": return "idle"
	var runtime: Variant = Props.read(Props.read(actor,"room"),"enemy_skills")
	for source: String in ["visuals","jobs"]:
		var commands: Array = Props.read(runtime,source,[])
		for command: Dictionary in commands:
			if int(command.get("owner_id",0)) != actor.get_instance_id() or not bool(command.get("b07_command",false)): continue
			if str(command.get("ability_id","")) != "B07-M01:sun_spear:follow" or str(command.get("shape","")) != "cone" or not bool(command.get("body_bound",false)): continue
			if float(command.get("remaining",0)) <= 0: continue
			return "tail_sweep:execute" if source == "visuals" else "tail_sweep:telegraph"
	return "idle"

static func _disc_in_flight(actor: Node2D) -> bool:
	if str(Props.read(actor,"enemy_id","")) != "B07-M03": return false
	var runtime: Variant = Props.read(Props.read(actor,"room"),"enemy_skills")
	for source: String in ["jobs","projectiles"]:
		var commands: Array = Props.read(runtime,source,[])
		for command: Dictionary in commands:
			if int(command.get("owner_id",0)) != actor.get_instance_id() or not bool(command.get("b07_command",false)): continue
			var ability: String = str(command.get("ability_id",""))
			if ability in ["B07-M03:returning_disc","B07-M03:returning_disc:follow"] and str(command.get("kind","")) == "projectile": return true
	return false
