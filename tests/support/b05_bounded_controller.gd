extends "res://tests/support/s11_battle_controller.gd"
## Reuse the production-input observer, but the mage sample never submits basics.
func maintain_primary() -> void:
	if Game.run != null and Game.run.hero_id != "CH03": super.maintain_primary()
