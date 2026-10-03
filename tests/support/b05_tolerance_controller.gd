extends RefCounted
## Supplemental single-packet receiver. No movement, offense or defensive input.
var rejected := {}
var decisions: Array = []
func step(_time: float) -> void: pass
