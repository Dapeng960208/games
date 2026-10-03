extends GridContainer
## Compact cells share full numeric tooltips and a persistent selection detail.
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
var cell_size := Vector2(96,126)

func configure(width: float, count: int) -> void:
	columns = count
	cell_size = Vector2(floorf((width-(count-1)*10)/count),126)
	custom_minimum_size.x = width
	add_theme_constant_override("h_separation",10)
	add_theme_constant_override("v_separation",10)

func add_item(item: Dictionary, level: int, hero_id: String, id_prefix: String, selected: bool, footer: String, action: Callable, equipped: bool = false) -> Button:
	var cell := GameStyle.button(self,"",Vector2.ZERO,cell_size,action)
	cell.name = id_prefix+str(item.get("instance_id", item.id)).replace(":","_")
	cell.custom_minimum_size = cell_size
	GameStyle.button_skin(cell,"socket")
	if selected: GameStyle.selected(cell,"socket")
	GameStyle.equipment_icon(cell,item,Vector2((cell_size.x-78)*.5,9),Vector2(78,78)).name = "CatalogEquipmentArt_"+str(item.id)
	var title := GameStyle.content_text(item,"name")
	var race := GameStyle.content_text(item,"race_name")
	if not race.is_empty(): title = title.replace(race,"")
	var name_label := GameStyle.literal(cell,title,Vector2(5,87),Vector2(cell_size.x-10,19),12,Inspect.rarity_color(item))
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rarity := GameStyle.literal(cell,Inspect.rarity_label(item),Vector2(5,2),Vector2(cell_size.x-10,14),10,Inspect.rarity_color(item))
	rarity.name = "EquipmentRarity"
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cell.set_meta("rarity",Inspect.rarity(item))
	var state := GameStyle.literal(cell,footer,Vector2(5,108),Vector2(cell_size.x-10,17),11,GameStyle.GREEN if equipped else GameStyle.AMBER)
	state.autowrap_mode = TextServer.AUTOWRAP_OFF
	state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.tooltip_text = Inspect.tooltip(item,level,hero_id)
	return cell
