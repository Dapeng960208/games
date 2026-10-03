extends Node2D
## Brief world-space input acknowledgements, independent of damage and targeting.
## One notice at a time; rejected input never creates an impact or spends resource.

const INK := Color("fff0cf")
const WARNING := Color("ffad88")
const QUEUED := Color("87e0d0")
var room: Node2D
var notice := ""
var reason := ""
var details: Dictionary = {}
var remaining := 0.0
var duration := 0.9
var _clock := 0.0
var _last_key := ""
var _next_repeat := 0.0
var _font: Font

func configure(owner_room: Node2D) -> void:
	room = owner_room
	z_index = 7
	_font = load(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf"))
	room.player.skill_input_feedback.connect(observe)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		clear_feedback()

func clear_feedback() -> void:
	notice = ""
	details.clear()
	remaining = 0.0
	queue_redraw()

func observe(slot: String, next_reason: String, data: Dictionary) -> void:
	if next_reason == "accepted":
		clear_feedback()
		return
	if not is_instance_valid(room) or not room.controls_enabled():
		return
	var next_key: String = slot + ":" + next_reason + ":" + str(data.get("cause", ""))
	if _last_key == next_key and _clock < _next_repeat:
		return
	_last_key = next_key
	_next_repeat = _clock + 0.45
	reason = next_reason
	details = data.duplicate(true)
	notice = describe(slot, next_reason, details)
	duration = 0.3 if next_reason == "queued" else 0.9
	remaining = duration
	queue_redraw()

static func describe(slot: String, failure: String, data: Dictionary) -> String:
	var english: bool = Words.locale == "en"
	var action: String = {"attack":"attack", "q":"skill_q", "secondary":"skill_secondary", "f":"skill_f", "ultimate":"skill_ultimate", "reload":"reload", "dash":"dash"}.get(slot, "")
	var key: String = str(data.get("key",ControlBindings.label_for(action, Game.profile.get("settings",{}).get("controls",{}), Words.locale) if not action.is_empty() else slot))
	var message := ""
	match failure:
		"queued":
			var queue_position: int = int(data.get("queue_position", 1))
			message = ("Queued · %d" % queue_position if english else "连招已准备 · 第 %d 步" % queue_position) if queue_position > 1 else ("Queued" if english else "接招已准备")
		"locked": message = str(data.get("lock_reason","Skill not learned" if english else "尚未学会该技能"))
		"reloading": message = "Reloading; skills remain available" if english else "装填中，主动技能仍可释放"
		"ammo_empty", "empty_magazine": message = "Empty magazine; reloading" if english else "弹匣已空，正在装填"
		"precision_missed", "reload_missed": message = "Precision missed; reload continues" if english else "精准判定未命中，继续装填"
		"precision_used", "reload_attempt_used": message = "Precision attempt already used" if english else "本次精准判定已使用"
		"reload_precision": message = "Precision reload · 3 enhanced rounds" if english else "精准装填 · 三发强化弹"
		"reload_full": message = "Magazine is full" if english else "弹匣已满"
		"invalid_skill": message = "Skill configuration unavailable" if english else "技能配置暂不可用"
		"resource":
			var missing: int = ceili(maxf(0.0, float(data.get("cost", 0)) - float(data.get("resource", 0))))
			message = "Need %d more resource" % missing if english else "资源还差 %d" % missing
		"cooldown": message = "Ready in %.1fs" % float(data.get("remaining", 0)) if english else "还需 %.1f 秒" % float(data.get("remaining", 0))
		"invalid_ground":
			message = ("Out of range" if english else "超出施法范围") if str(data.get("cause", "")) == "out_of_range" else ("Target blocked" if english else "落点被阻挡")
		"dashing": message = "Finish the dodge first" if english else "闪避结束后施放"
		"busy":
			match str(data.get("cause", "")):
				"queue_full": message = "Combo queue full" if english else "连招队列已满"
				"buffer_expired": message = "Follow-up expired" if english else "接招输入已过期"
				"already_queued": message = "Already queued" if english else "该技能已准备接招"
				_: message = "Action in progress" if english else "当前动作未结束"
		"invalid_direction": message = "Aim at a target" if english else "请瞄准目标"
		_: message = "Cannot cast now" if english else "暂时无法施放"
	return key + " · " + message

func _process(delta: float) -> void:
	_clock += maxf(0.0, delta)
	if not is_instance_valid(room) or not room.controls_enabled():
		if remaining > 0.0: clear_feedback()
		return
	if remaining <= 0.0: return
	remaining = maxf(0.0, remaining - delta)
	queue_redraw()

func _draw() -> void:
	if remaining <= 0.0 or notice.is_empty() or not is_instance_valid(room) or not is_instance_valid(room.player) or _font == null:
		return
	var alpha: float = minf(1.0, remaining / 0.16)
	var tint: Color = QUEUED if reason in ["queued", "reload_precision"] else WARNING
	var origin: Vector2 = room.player.position
	if reason == "invalid_ground":
		var reach: float = maxf(0.0, float(details.get("range", 0.0)))
		if reach > 0.0:
			# Deliberately brief: this is an explanation of the rejected quick cast,
			# never a persistent targeting mode or a second gameplay radius.
			draw_arc(origin, reach, 0, TAU, 80, Color(tint, alpha * 0.45), 1.7, true)
		var target: Variant = details.get("target", origin)
		if target is Vector2 and target.is_finite():
			draw_line(target - Vector2(7, 7), target + Vector2(7, 7), Color(tint, alpha), 2.5, true)
			draw_line(target - Vector2(7, -7), target + Vector2(7, -7), Color(tint, alpha), 2.5, true)
	var text_size := 18
	var width: float = _font.get_string_size(notice, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var at: Vector2 = origin + Vector2(-width * 0.5, -87)
	draw_circle(at + Vector2(-9, -6), 3.0, Color(tint, alpha))
	draw_string_outline(_font, at, notice, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, 3, Color(0.025, 0.04, 0.05, alpha))
	draw_string(_font, at, notice, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(INK, alpha))
