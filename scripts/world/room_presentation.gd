class_name RoomPresentation
extends RefCounted
## Room-specific scenery is a presentation overlay, never a replacement for
## the blueprint's race, encounters, objectives, counterplays or rewards.
const PATH := "res://data/room_presentations.json"
static var _rooms: Dictionary = {}
static var _loaded := false

static func definition(room_id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _rooms = parsed.get("rooms", {})
	return _rooms.get(room_id, {}).duplicate(true)

static func for_layout(layout: Dictionary) -> Dictionary:
	return definition(str(layout.get("blueprint_room_id", layout.get("room_id", ""))))

static func accent(biome_id: String) -> Color:
	return Color({"B01":"398f96", "B02":"aa752a", "B03":"9272ab", "B04":"645591"}.get(biome_id,"398f96"))

static func apply_scenery(layout: Dictionary) -> void:
	var design: Dictionary = for_layout(layout)
	if design.is_empty(): return
	layout["room_presentation"] = design
	var retained: Array = []
	# Reward scenery is the reward's visible body. Retain its exact instance.
	for item: Dictionary in layout.decoration_instances:
		var keep: bool = "fixed_landmark" in item.get("tags", [])
		for reward: Dictionary in layout.fixed_optional_rewards:
			if str(item.asset)==str(reward.asset) and Vector2(item.position).distance_to(reward.position)<0.5:
				keep = true
		if keep: retained.append(item)
	var arena: Rect2 = layout.arena
	for index: int in design.get("groups", []).size():
		var group: Dictionary = design.groups[index]
		var center := arena.position+Vector2(float(group.at[0]),float(group.at[1]))*arena.size
		for part: int in group.assets.size():
			var offsets := [Vector2(-68,0),Vector2(55,30),Vector2(12,-64)]
			var at: Vector2 = center+offsets[part%offsets.size()]
			var extent := Vector2(136,140) if part!=2 else Vector2(104,110)
			retained.append({"id":str(layout.blueprint_room_id)+":venue:%d:%d" % [index,part],
				"asset":str(layout.biome_id)+"_prop_"+str(group.assets[part]),
				"name":str(group.name), "position":at, "visual_size":extent,
				"visual_rect":Rect2(at-Vector2(extent.x*.5,extent.y),extent),
				"collision_rect":Rect2(at,Vector2.ZERO), "kind":"fixed_decoration",
				"tags":["decoration","non_solid","fixed_prop","venue_group",str(layout.biome_id)],
				"rotation":0.0,"fixed":true})
	layout.decoration_instances = retained

static func local_caption(design: Dictionary, english: bool) -> String:
	return str(design.get("caption_en" if english else "caption", ""))
