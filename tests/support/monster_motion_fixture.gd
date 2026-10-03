extends RefCounted
## Synthetic pose registration for contact/presentation tests only.

static func parse_motion_manifest(raw: Dictionary, texture_size: Vector2) -> Dictionary:
	# Validate metadata without loading a renderer; never guess a sprite grid.
	var source_height: Variant = raw.get("body_height", 0.0)
	if not raw.get("frames", []) is Array or not _numbers([source_height]) or float(source_height) <= 0.0:
		return {}
	var named: Dictionary = {}
	var clips: Dictionary = {}
	for item: Variant in raw.get("frames", []):
		if not item is Dictionary:
			continue
		var rect: Variant = item.get("region", [])
		var foot: Variant = item.get("foot", [])
		if not rect is Array or rect.size() != 4 or not foot is Array or foot.size() != 2:
			continue
		if not _numbers(rect) or not _numbers(foot):
			continue
		var region := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		var anchor := Vector2(float(foot[0]), float(foot[1]))
		if not region.has_area() or not Rect2(Vector2.ZERO, texture_size).encloses(region) or anchor.x < region.position.x or anchor.x > region.end.x or anchor.y < region.position.y or anchor.y > region.end.y:
			continue
		var label: String = str(item.get("name", item.get("index", "")))
		if label.is_empty():
			continue
		var frame: Dictionary = {"name":label,"region":region,"foot":anchor}
		named[label] = frame
		var action: String = str(item.get("action", label.get_slice("_", 0)))
		if not clips.has(action):
			clips[action] = []
		clips[action].append(frame)
	var animations: Variant = raw.get("animations", raw.get("clips", {}))
	if animations is Dictionary:
		for action: String in animations:
			if not animations[action] is Array:
				continue
			var frames: Array = []
			for label: Variant in animations[action]:
				if named.has(str(label)):
					frames.append(named[str(label)])
			if not frames.is_empty():
				clips[action] = frames
	# Synthetic pose fixtures use compact numeric clip labels.
	for alias: String in {"windup":"telegraph", "release":"execute", "hurt":"recoil"}:
		var action: String = {"windup":"telegraph", "release":"execute", "hurt":"recoil"}[alias]
		if clips.has(alias) and not clips.has(action):
			clips[action] = clips[alias]
	if not clips.has("locked") and clips.has("telegraph"):
		clips["locked"] = [clips.telegraph.back()]
	# A manifest without a dedicated idle keeps a stable authored contact pose,
	# rather than changing back to a differently framed portrait on every stop.
	if not clips.has("idle"):
		if clips.has("walk"):
			clips["idle"] = [clips.walk.front()]
		elif clips.has("recovery"):
			clips["idle"] = [clips.recovery.back()]
	if named.is_empty():
		return {}
	var result: Dictionary = {"clips":clips,"body_height":float(source_height),"facing":str(raw.get("facing", "right"))}
	var cycle_distance: Variant = raw.get("cycle_distance", 0.0)
	if _numbers([cycle_distance]) and float(cycle_distance) > 1.0:
		result["cycle_distance"] = float(cycle_distance)
	return result

static func _numbers(values: Array) -> bool:
	for value: Variant in values:
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	return true
