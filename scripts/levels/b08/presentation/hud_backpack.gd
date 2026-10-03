extends "res://scripts/presentation/equipment/backpack_panel.gd"
## Inspect the disposable demo loadout without committing its B01 receipt.

func _render() -> void:
	super._render()
	if status_label == null: return
	status_label.text = _t("B08 候选：仅查看试玩装备与属性，不换装、不掉落、不保存。","B08 candidate: inspect trial equipment and attributes; no swaps, drops or saves.")
	status_label.tooltip_text = status_label.text
	for label: Label in find_children("*","Label",true,false):
		if label.text == _t("暂停换装 · 生命与冷却保留","Paused swaps · HP/cooldowns preserved"):
			label.text = _t("暂停查看 · 生命与冷却保留","Paused inspection · HP/cooldowns preserved")
		elif label.text == _t("当前筛选无装备。点全部清除筛选；本局掉落需撤离才永久入库。","No matching gear. Choose All to clear filters. Run loot is secured after extraction."):
			label.text = _t("当前筛选无试玩装备。点全部清除筛选。","No trial gear matches. Choose All to clear filters.")

func _detail() -> void:
	super._detail()
	for id: String in ["BackpackEquip","BackpackUnequip"]:
		var action := detail_root.find_child(id,true,false) as Button
		if action != null:
			action.disabled = true
			action.hide()

func _apply(_id: String, _slot: String) -> void:
	# No route from this local inspector to Gear.apply or save transactions.
	return
