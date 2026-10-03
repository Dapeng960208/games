class_name Balance
extends RefCounted
## M1 test values. Combat, settlement, and HUD read the same source.

const PLAYER_HP := 100.0
const PLAYER_SPEED := 240.0
const DASH_SPEED := 690.0
const DASH_DURATION := 0.16
const DASH_COOLDOWN := 1.15
const HURT_INVULNERABILITY := 0.65
const SHOT_DAMAGE := 20.0
const SHOT_INTERVAL := 0.25
const PROJECTILE_SPEED := 650.0
const PROJECTILE_LIFETIME := 1.6
const ENEMY_HP := 60.0
const ENEMY_SPEED := 96.0
const ENEMY_DAMAGE := 14.0
const ENEMY_WINDUP := 0.65
const ENEMY_RECOVERY := 0.9
const ENEMY_RANGE := 48.0
const SPLIT_RATIO := 0.4
const SPLIT_ANGLE := 1.05
const EMBER_DPS := 3.0
const EMBER_DURATION := 3.0
const ARC_RATIO := 0.35
const ARC_TARGETS := 2
const ARC_RANGE := 220.0
const DEATH_KEEP_RATIO := 0.5
const MAX_PROJECTILES := 100
const TRIGGER_BUDGET := 4
const GOLD_PER_ENEMY := 17
const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 18.0
const MAX_ENEMIES := 18
const ENEMY_KNOCKBACK := 175.0
const PLAYER_KNOCKBACK := 120.0
const GOLD_ATTRACT_RADIUS := 120.0
const GOLD_PICKUP_RADIUS := 25.0
const GOLD_ATTRACT_SPEED := 330.0
const ENEMY_SPAWN_INTERVAL := 7.0
const INTERACTION_RADIUS := 68.0
const ENEMY_SPAWN_GRACE := 0.8
const PLAYER_KNOCKBACK_DECAY := 660.0
const ENEMY_KNOCKBACK_DECAY := 560.0
const ENEMY_SEPARATION_DISTANCE := 43.2
const ENEMY_SEPARATION_STRENGTH := 3.0
const ENEMY_SEPARATION_SPEED_RATIO := 0.8
const ENEMY_SPAWN_SAFE_DISTANCE := 190.0
const WAVE_BASE_COUNT := 2
const WAVE_MAX_COUNT := 4
const WAVE_GROWTH_EVERY := 3

static func death_keep(gold: int) -> int:
	return ProfileStore.retained_gold(gold, "death")
