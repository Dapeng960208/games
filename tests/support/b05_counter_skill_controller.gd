extends "res://tests/support/b05_balance_controller.gd"
## Explicit separate sensitivity policies. Frozen baseline controller is untouched.
var counter_policy := "all_skills"
func attack_target(time: float, target: Node2D, threats: Array[Dictionary], counter: bool) -> void:
	if not counter or Game.run.hero_id!="CH01":
		super.attack_target(time,target,threats,counter)
		return
	if counter_policy=="all_skills":
		# Same E/R/W/Q eligibility/priority, now also allowed against real roots.
		super.attack_target(time,target,threats,false)
		return
	# A second, predeclared reasonable policy: use legal Q for the root approach,
	# otherwise retain baseline basic-counter handling; do not spend R on roots.
	super.attack_target(time,target,threats,true)
	var player: HeroActor=room.player
	if player.abilities.busy() or not player.combo_queue.is_empty() or player.dash_remaining>0:return
	var distance:=player.position.distance_to(target.position)
	var spec:Dictionary=player.skill_definition("q")
	if distance<=player.auto_attack_range()-5 or not skill_reaches("CH01","q",spec,distance,target):return
	if player.cooldowns.q>0 or float(Game.run.resource)<float(spec.cost) or not safe_cast_window(threats,float(spec.duration)):return
	var direction:=player.position.direction_to(target.position)
	if not room.has_line_of_sight(player.position,target.position) or absf(player.aim_direction.angle_to(direction))>.04:return
	if player.request_skill("q",target.position):decisions.append({"t":time,"mode":"legal_root_q_approach","distance":distance,"target":[target.position.x,target.position.y]})
