extends SceneTree
## Real skill/projectile/deployment events and exact production PCM. No import,
## audio device output, substituted abilities or altered gameplay timelines.
const Audio = preload("res://scripts/presentation/combat/combat_audio.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
var checks: int = 0
var failures: int = 0
var game: Node
var room: Node2D
var room_scene: PackedScene
var events: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SKILL AUDIO FAIL: " + label)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_skill_audio_timing"):
		push_error("Refusing non-test skill audio profile")
		quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated real game starts")
	if game.run == null:
		quit(1)
		return
	# Standalone --script loads before autoload globals exist; load scenes only
	# after the real Game autoload has entered the tree.
	room_scene = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn"))
	_test_pcm()
	_test_base_timelines()
	_test_branches()
	_test_cancellation()
	_test_settings_and_rejected_casts()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(), "final audio shutdown observes actual playback cleanup")
		room.free()
	print("SKILL AUDIO TIMING: %d checks, %d failures (actual skills/branches/cancellation and PCM; no listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func fixture(hero: String, level: int = 8, branches: Dictionary = {}) -> void:
	if is_instance_valid(room): room.free()
	game.run.hero_id = hero
	game.run.level = level
	game.run.stats = Resolver.resolve(hero, level, {}, {})
	game.run.stats["branches"] = branches.duplicate(true)
	game.run.stats["crit_chance"] = 0.0
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	game.run.relics.clear()
	game.profile.settings.merge({"muted":false, "sfx_muted":false, "master_volume":1.0, "sfx_volume":1.0, "reduced_fx":false}, true)
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.combat_audio.audible = false
	room.combat_audio.set_process(false)
	room.player.position = Vector2(430, 350)
	room.player.aim_direction = Vector2.RIGHT
	events.clear()
	room.combat_audio.cue_played.connect(_observe)

func _observe(cue: String) -> void:
	var at: float = float(room.player.abilities.active.get("elapsed", -1.0))
	var deployments: int = 0
	for child: Node in room.get_children():
		if child.has_method("charge_node"): deployments += 1
	events.append({"cue":cue, "time":at, "projectiles":room.projectiles.get_child_count(), "deployments":deployments})

func _advance(delta: float) -> void:
	room.combat_audio.advance(delta)
	room.player.abilities.tick(delta)

func _cues(cue: String) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.cue == cue: matching.append(event)
	return matching

func _cast(slot: String) -> bool:
	return room.player.cast_skill(slot, room.player.position + Vector2(100, 0))

func _assert_timeline(hero: String, slot: String, times: Array, level: int = 8, branches: Dictionary = {}) -> void:
	fixture(hero, level, branches)
	var label: String = "%s/%s/L%d/%s" % [hero, slot, level, str(branches)]
	check(_cast(slot), label + " accepts real ability")
	check(events.size() == 1 and events[0].cue == "prepare_" + slot and is_zero_approx(events[0].time), label + " commitment emits only short preparation")
	check(room.projectiles.get_child_count() == 0 and _cues(slot).is_empty(), label + " preparation invents no projectile/release")
	var clock: float = 0.0
	for index: int in times.size():
		var time: float = float(times[index])
		_advance(time - clock - 0.0001)
		check(_cues(slot).size() == index, label + " has no release before boundary " + str(time))
		_advance(0.0001)
		clock = time
		var observed: Array[Dictionary] = _cues(slot)
		check(observed.size() == index + 1, label + " emits exactly one release at boundary " + str(time))
		if observed.size() > index:
			check(absf(observed[index].time - time) < 0.00001, label + " event timestamp matches actual skill timeline")
			if (hero == "CH02" and slot != "f") or (hero == "CH03" and slot == "q"):
				check(observed[index].projectiles == index + 1, label + " audio observes the actual newly spawned projectile")
			if (hero == "CH02" and slot == "f") or (hero == "CH03" and slot in ["secondary", "ultimate"]):
				check(observed[index].deployments == 1, label + " deployment exists when its release sound plays")
	_advance(2.0)
	check(not room.player.abilities.busy() and _cues(slot).size() == times.size(), label + " recovery creates no additional shots")
	check(_cues("impact").is_empty() and _cues("heavy").is_empty(), label + " empty-space release never fakes hit confirmation")
	check(room.combat_audio.active_voice_count() <= 8, label + " uses the existing bounded pool")

func _test_base_timelines() -> void:
	for row: Array in [
		["CH01", "q", [0.28]], ["CH01", "secondary", [0.18]], ["CH01", "f", [0.12]], ["CH01", "ultimate", [0.45]],
		["CH02", "q", [0.22, 0.28, 0.34]], ["CH02", "secondary", [0.45]], ["CH02", "f", [0.15]], ["CH02", "ultimate", [0.25, 0.49, 0.73, 0.97]],
		["CH03", "q", [0.18]], ["CH03", "secondary", [0.20]], ["CH03", "f", [0.14]], ["CH03", "ultimate", [0.40]]
	]:
		_assert_timeline(row[0], row[1], row[2])
	# Audio and physics clocks can differ: three real Q events still require
	# three release sounds, with no arbitrary second 60ms scheduler gate.
	fixture("CH02")
	check(_cast("q"), "clock-skew fixture casts real Q")
	room.player.abilities.tick(0.40)
	check(_cues("q").size() == 3 and room.projectiles.get_child_count() == 3, "one catch-up physics tick releases all three real Q shots at one audio clock")

func _test_branches() -> void:
	_assert_timeline("CH02", "q", [0.06, 0.19, 0.32], 20, {"q":"B"})
	_assert_timeline("CH02", "q", [0.22, 0.28, 0.34], 20, {"q":"A"})
	_assert_timeline("CH02", "ultimate", [0.25, 0.61, 0.97], 20, {"ultimate":"B"})
	_assert_timeline("CH02", "ultimate", [0.25, 0.49, 0.73, 0.97], 20, {"ultimate":"A"})
	_assert_timeline("CH01", "q", [0.10], 20, {"q":"B"})
	_assert_timeline("CH01", "ultimate", [0.65], 20, {"ultimate":"A"})
	_assert_timeline("CH01", "ultimate", [0.45, 0.65], 20, {"ultimate":"B"})

func _test_cancellation() -> void:
	for hero: String in Audio.HEROES:
		for slot: String in ["q", "secondary", "f", "ultimate"]:
			fixture(hero)
			check(_cast(slot), hero + "/" + slot + " cancellation fixture commits ability")
			_advance(0.025)
			check(room.player.start_dash(Vector2.UP), hero + "/" + slot + " real defensive dash interrupts preparation")
			_advance(2.0)
			check(_cues(slot).is_empty() and room.projectiles.get_child_count() == 0, hero + "/" + slot + " cancelled future releases neither fire nor sound")
			check(_cues("prepare_" + slot).size() == 1, hero + "/" + slot + " cancellation never replays preparation")
	fixture("CH02")
	check(_cast("ultimate"), "partial R cancellation starts real burst")
	_advance(0.25)
	_advance(0.05)
	check(_cues("ultimate").size() == 1 and room.projectiles.get_child_count() == 1, "partial R has actually emitted one round")
	var playing_before: int = room.combat_audio.active_voice_count()
	check(playing_before > 0 and room.player.start_dash(Vector2.UP), "dash interrupts after one real release")
	check(room.combat_audio.active_voice_count() == playing_before, "cancellation preserves already released audio tails")
	_advance(2.0)
	check(_cues("ultimate").size() == 1 and room.projectiles.get_child_count() == 1, "cancelled remaining R rounds never sound or spawn")
	fixture("CH03")
	check(_cast("ultimate"), "death cancellation starts real spell")
	game.run.hp = 0.0
	_advance(1.0)
	check(_cues("ultimate").is_empty() and not room.player.abilities.busy(), "death during preparation produces no future spell audio")

func _test_settings_and_rejected_casts() -> void:
	fixture("CH02")
	game.run.resource = 0.0
	check(not _cast("secondary") and events.is_empty(), "resource rejection emits no preparation or release")
	game.run.resource = 100.0
	game.profile.settings.sfx_muted = true
	check(_cast("secondary"), "muted fixture still casts real ability")
	_advance(0.45)
	check(room.projectiles.get_child_count() == 1 and events.is_empty(), "muting preserves gameplay but emits no accepted audio event")
	fixture("CH03")
	game.profile.settings.reduced_fx = true
	check(_cast("q"), "reduced-effects fixture casts actual Q")
	_advance(0.18)
	check(_cues("prepare_q").size() == 1 and _cues("q").size() == 1, "reduced visuals retain both correct audio phases")
	fixture("CH02")
	check(_cast("secondary"), "pause fixture begins real charge")
	paused = true
	room.combat_audio.advance(0.1)
	check(room.combat_audio.active_voice_count() == 0 and not room.combat_audio.prepare("CH02", "q") and not room.combat_audio.cast("CH02", "q"), "paused mixer rejects new preparation and release")
	paused = false
	check(not room.combat_audio.prepare("CH02", "unknown") and Audio.stream_for("CH02", "prepare_unknown") == null, "preparation accepts only finite authored slots")

func _energy(stream: AudioStreamWAV, begin: float, end: float) -> float:
	var total: float = 0.0
	for index: int in range(roundi(begin * stream.mix_rate), mini(stream.data.size() / 2, roundi(end * stream.mix_rate))):
		var value: float = float(stream.data.decode_s16(index * 2)) / 32768.0
		total += value * value / stream.mix_rate
	return total

func _test_pcm() -> void:
	Audio.prewarm()
	check(Audio._streams.size() == 252, "complete cue domain is exactly bounded at 252 production samples including twenty-four shield streams")
	for hero: String in Audio.HEROES:
		for slot: String in ["q", "secondary", "f", "ultimate"]:
			var preparation_signatures: Dictionary = {}
			for variant: int in 4:
				var release: AudioStreamWAV = Audio.stream_for(hero, slot, variant)
				var preparation: AudioStreamWAV = Audio.stream_for(hero, "prepare_" + slot, variant)
				var label: String = hero + "/" + slot + "/v" + str(variant)
				check(release != null and preparation != null and release.data != preparation.data, label + " owns separate actual commitment and release PCM")
				check(_energy(release, 0.0, 0.012) > 0.000003, label + " main release transient begins within 12ms")
				check(_energy(preparation, 0.0, 0.2) < _energy(release, 0.0, 0.5) * 0.6, label + " preparation yields to actual release energy")
				check(preparation.get_length() >= 0.10 and preparation.get_length() <= 0.17, label + " preparation ends shortly without a baked delayed shot")
				check(release.get_length() >= 0.15 and release.get_length() <= 0.43, label + " release is one short action")
				check(preparation.format == AudioStreamWAV.FORMAT_16_BITS and preparation.mix_rate == 24000 and not preparation.stereo, label + " preparation retains authored PCM format")
				var peak: float = 0.0
				var total: float = 0.0
				for index: int in preparation.data.size() / 2:
					var value: float = float(preparation.data.decode_s16(index * 2)) / 32768.0
					peak = maxf(peak, absf(value))
					total += value
				check(peak > 0.025 and peak <= Audio.SAMPLE_PEAK and absf(total / (preparation.data.size() / 2)) < 0.003, label + " preparation is audible with bounded peak and negligible DC")
				check(preparation.data.decode_s16(0) == 0 and preparation.data.decode_s16(preparation.data.size() - 2) == 0 and preparation.loop_mode == AudioStreamWAV.LOOP_DISABLED, label + " preparation has zero endpoints and cannot loop")
				preparation_signatures[hash(preparation.data)] = true
			check(preparation_signatures.size() == 4, hero + "/" + slot + " has four authored preparation takes")
	for hero: String in ["CH02", "CH03"]:
		check(_energy(Audio.stream_for(hero, "attack"), 0.0, 0.012) > 0.000003, hero + " basic projectile has an immediate attack transient")
	for variant: int in 4:
		check(Audio.stream_for("CH02", "ultimate", variant).get_length() < 0.24, "one R report cannot contain the next actual 240ms shot")
		check(_energy(Audio.stream_for("CH02", "q", variant), 0.09, 0.16) < _energy(Audio.stream_for("CH02", "q", variant), 0.0, 0.03) * 0.03, "Q tail contains no prerecorded second gun report")
