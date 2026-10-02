extends RefCounted
## Optional combat interfaces share static script properties. Cache their names,
## rather than rebuilding hundreds of property descriptors on each AI query.
static var _names: Dictionary = {}
static func read(value: Variant, key: String, fallback: Variant = null) -> Variant:
	if not value is Object or not is_instance_valid(value): return fallback
	var script: Variant = value.get_script()
	var identity: Variant = script.get_instance_id() if script is Script else value.get_class()
	if not _names.has(identity):
		var names := {}
		for property: Dictionary in value.get_property_list(): names[str(property.name)] = true
		_names[identity] = names
	return value.get(key) if _names[identity].has(key) else fallback
