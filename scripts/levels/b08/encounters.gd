extends RefCounted
## Bounded authored room slice. No random replacement, no infinite respawn.
static func waves(id: String, difficulty: int) -> Array:
	if difficulty not in range(5): return []
	if id=="L43": return [[{"id":"B08-M01","rank":"normal","at":[1150,930]},{"id":"B08-M02","rank":"normal","at":[1550,930]},{"id":"B08-M03","rank":"normal","at":[1950,950]}]]
	if id!="L44": return []
	var result: Array = [[{"id":"B08-M04","rank":"normal","at":[1400,800]},{"id":"B08-M05","rank":"elite" if difficulty>=3 else "normal","at":[1240,970]},{"id":"B08-M06","rank":"normal","at":[1650,760]}]]
	if difficulty>=3: result.append([{"id":"B08-M04","rank":"normal","at":[1450,550]},{"id":"B08-M06","rank":"normal","at":[1100,650]}])
	return result
