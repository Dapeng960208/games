extends SceneTree
## Isolated test: copy this file and its preload under the same res:// paths in
## a temporary project with no Game autoload; run --headless --script this file.
## No disk save, production registration or graphic validation is performed.
const Network = preload("res://scripts/world/b05_root_network.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var net = _fresh()
	_check(net.snapshot().wells.a.hp == 600.0, "well uses 60% F HP")
	_check(net.well_reaches("a", Vector2(220, 0)), "inclusive radius")
	_check(not net.well_reaches("a", Vector2(220.01, 0)), "outside radius")
	_check(not net.well_reaches("missing", Vector2.ZERO), "unknown well disconnected")
	_check(not net.well_reaches("a", Vector2(NAN, 0)), "invalid position")
	_check(net.connect_actor("a", "plant", Vector2.ZERO, 1000, 0).shield == 120.0, "12% shield")
	_check(net.connect_actor("b", "plant", Vector2.ZERO, 1000, 0).is_empty(), "cross-well actor CD")
	_check(net.connect_actor("a", "other", Vector2.ZERO, 1000, 200).shield == 200.0, "higher shield preserved without stacking")
	_check(net.connect_actor("a", "bad", Vector2.ZERO, INF, 0).is_empty(), "invalid actor hp")
	var before: Dictionary = net.snapshot()
	for delta in [-1.0, NAN, INF]:
		_check(not net.advance(delta), "invalid delta rejected")
		_check(net.snapshot() == before, "invalid delta unchanged")
	_check(not net.damage_well("missing", 1), "unknown damage rejected")
	_check(not net.damage_well("a", NAN), "invalid damage rejected")
	net.advance(11.99)
	_check(net.connect_actor("a", "plant", Vector2.ZERO, 1000, 0).is_empty(), "CD before boundary")
	net.advance(0.02)
	_check(net.connect_actor("a", "plant", Vector2.ZERO, 1000, 20).shield == 120.0, "refresh takes max not sum")
	net.damage_well("a", 599)
	_check(net.well_reaches("a", Vector2.ZERO), "partial damage retains network")
	net.damage_well("a", 1)
	_check(not net.well_reaches("b", Vector2.ZERO), "destroyed well locks shared network")
	_check(not net.damage_well("a", 1), "dead well cannot restart lock")
	_check(net.well_reaches("c", Vector2.ZERO), "unrelated network survives")
	net.advance(3)
	_check(net.begin_gate("gate", "hero"), "start channel")
	net.advance(0.3)
	_check(not net.interrupt_actor("stranger"), "other hit does not cancel")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(net.snapshot()))
	var restored = _fresh()
	_check(restored.restore(saved), "JSON snapshot accepted")
	_check(is_equal_approx(restored.snapshot().cooldowns.plant, 8.7), "actor CD preserved")
	_check(is_equal_approx(restored.snapshot().locks.shared, 8.7), "network lock preserved")
	_check(restored.snapshot().wells.a.hp == 0.0, "destroyed HP preserved")
	_check(is_equal_approx(restored.snapshot().channel.remaining, 0.3), "partial gate channel preserved")
	_check(restored.interrupt_actor("hero"), "real actor hit cancels")
	restored.advance(1)
	_check(not restored.bridge_is_open("bridge"), "cancelled gate does not complete")
	_check(restored.begin_gate("gate", "hero"), "cancel consumes no use")
	restored.advance(0.59)
	_check(not restored.bridge_is_open("bridge"), "channel not early")
	restored.advance(0.02)
	_check(restored.bridge_is_open("bridge"), "bridge completes after 0.6")
	_check(not restored.begin_gate("gate", "hero"), "no repeat gate")
	restored.advance(30)
	_check(not restored.well_reaches("b", Vector2.ZERO), "gate closure permanent")
	_check(not restored.well_reaches("a", Vector2.ZERO), "well destruction permanent")
	var unlocked = _fresh()
	_check(unlocked.restore(saved), "second restore")
	unlocked.interrupt_actor("hero")
	unlocked.advance(8.69)
	_check(not unlocked.well_reaches("b", Vector2.ZERO), "lock before twelve seconds")
	unlocked.advance(0.02)
	_check(unlocked.well_reaches("b", Vector2.ZERO), "restored lock expires without resetting")
	_check(unlocked.well_reaches("c", Vector2.ZERO), "independent well stays active")
	var timer = _fresh()
	timer.damage_well("a", 600)
	timer.advance(12)
	_check(timer.well_reaches("b", Vector2.ZERO), "surviving network reconnects at twelve seconds")
	_check(not timer.well_reaches("a", Vector2.ZERO), "dead well does not respawn")
	var finished = _fresh()
	_check(finished.restore(JSON.parse_string(JSON.stringify(restored.snapshot()))), "completed gate roundtrip")
	_check(finished.bridge_is_open("bridge") and not finished.well_reaches("b", Vector2.ZERO), "bridge and closed well restored")
	before = finished.snapshot()
	var bad: Dictionary = before.duplicate(true)
	bad.wells.a.hp = -1
	_reject(finished, bad, before, "negative HP")
	bad = before.duplicate(true)
	bad.cooldowns = {"plant":13.0}
	_reject(finished, bad, before, "invalid CD")
	bad = before.duplicate(true)
	bad.wells.b.closed = false
	_reject(finished, bad, before, "gate/well inconsistency")
	bad = before.duplicate(true)
	bad.wells.a.x = 999
	_reject(finished, bad, before, "authored geometry change")
	bad = before.duplicate(true)
	bad.locks = {"unknown":1.0}
	_reject(finished, bad, before, "unknown network")
	bad = before.duplicate(true)
	bad.channel = {"gate_id":"missing", "actor_id":"hero", "remaining":0.1}
	_reject(finished, bad, before, "unknown gate")
	print("B05 root network: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _fresh():
	var net = Network.new()
	_check(net.configure({"a":{"x":0,"y":0,"frontline_hp":1000,"network_id":"shared"}, "b":{"x":0,"y":0,"frontline_hp":1000,"network_id":"shared"}, "c":{"x":0,"y":0,"frontline_hp":1000,"network_id":"separate"}}, {"gate":{"well_ids":["b"],"bridge_id":"bridge"}}), "valid configuration")
	return net

func _reject(net, bad: Dictionary, before: Dictionary, label: String) -> void:
	_check(not net.restore(bad), label + " rejected")
	_check(net.snapshot() == before, label + " leaves state unchanged")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
