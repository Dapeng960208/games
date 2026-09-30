extends Node2D
## Read-only danger presentation above bodies (2), contacts (3) and released
## skills (4). Brains own every coordinate and clock; this layer owns no timers.

const TRACKING := Color("eab064")
const LOCKED := Color("ff7255")
const INK := Color(0.035, 0.045, 0.055, 0.86)
var room: Node2D
var redraw_revision: int = 0
var _entries: Array[Dictionary] = []
var _reduced: bool = false
var _canvas_transform := Transform2D.IDENTITY

func configure(host: Node2D) -> void:
	room = host
	name = "EnemyTelegraphs"
	z_index = 5
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 100
	clear()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> bool:
	if not is_instance_valid(room) or (is_inside_tree() and get_tree().paused):
		return false
	var next: Array[Dictionary] = []
	# The room enforces MAX_ENEMIES on every ordinary/summon/anchor spawn;
	# bosses also share this container. Current layouts add at most 23 inert
	# objectives (L11); collection is bounded by that room population plus
	# transient queued corpses. Do not truncate it: a queued corpse or
	# objective before a living caster must never hide a real danger warning.
	for actor: Node in room.enemies.get_children():
		if not _visible_caster(actor):
			continue
		# MineBoss installs boss_brain into the same inherited brain property.
		var brain: RefCounted = actor.brain
		if brain == null:
			continue
		var data: Dictionary = brain.current_telegraph()
		if not data.is_empty():
			next.append({"actor_id": actor.get_instance_id(), "data": presentation_data(data)})
	var reduced: bool = bool(Game.profile.get("settings", {}).get("reduced_fx", false))
	var transform_to_room: Transform2D = room.telegraph_canvas_transform(self)
	if next == _entries and reduced == _reduced and transform_to_room.is_equal_approx(_canvas_transform):
		return false
	_entries = next
	_reduced = reduced
	_canvas_transform = transform_to_room
	redraw_revision += 1
	queue_redraw()
	return true

func clear() -> void:
	_entries.clear()
	redraw_revision += 1
	queue_redraw()

func snapshot() -> Array[Dictionary]:
	return _entries.duplicate(true)

static func presentation_data(source: Dictionary) -> Dictionary:
	var data: Dictionary = source.duplicate(true)
	# Bosses publish tell/lock; ordinary enemies publish the final effective
	# telegraph_seconds/locked_seconds (including their scan-mark modifier).
	var tell: float = maxf(0.001, float(data.get("telegraph_seconds", maxf(0.55, float(data.get("tell", 0.8))))))
	var lock: float = maxf(0.001, float(data.get("locked_seconds", maxf(0.24, float(data.get("lock", 0.32))))))
	var progress: float = clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	data["lock_fraction"] = tell / (tell + lock)
	data["release_progress"] = (tell + progress * lock if bool(data.get("locked", false)) else progress * tell) / (tell + lock)
	return data

static func palette(locked: bool, reduced: bool) -> Dictionary:
	return {"edge": LOCKED if locked else TRACKING, "ink": INK,
		"width": 2.25 if locked else 1.5,
		"fill_alpha": 0.025 if reduced else (0.055 if locked else 0.035),
		"path_alpha": 0.045 if reduced else (0.10 if locked else 0.065)}

func _visible_caster(actor: Object) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.is_inside_tree() and actor.is_alive() and actor.state in [&"telegraph", &"locked"]

func _draw() -> void:
	if not is_instance_valid(room):
		return
	for entry: Dictionary in _entries:
		var actor: Object = instance_from_id(int(entry.actor_id))
		# Deletion can happen after the last process pass; never retain a freed
		# caster's drawn commands until another AI tick.
		if _visible_caster(actor):
			room.draw_enemy_telegraph(self, entry.data)
