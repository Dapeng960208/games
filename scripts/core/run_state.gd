class_name RunState
extends RefCounted
## Transient expedition data. Only an abandonment receipt is persisted in M1.

var id: String = ""
var gold: int = 0
var hp: float = Balance.PLAYER_HP
var relics: Array[String] = []
var shots: int = 0
var kills: int = 0
var elapsed: float = 0.0

func receipt() -> Dictionary:
	return {
		"id": id, "gold": gold, "discoveries": relics.duplicate(),
		"shots": shots, "kills": kills, "elapsed": elapsed,
	}
