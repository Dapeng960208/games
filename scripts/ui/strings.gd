class_name Words
extends RefCounted

static var locale := "zh_CN"
static var catalog: Dictionary = {}

static func initialize(language: String) -> void:
	text("TITLE")
	for lang in ["zh_CN", "en"]:
		var translation := Translation.new()
		translation.locale = lang
		for key in catalog:
			translation.add_message(key, catalog[key].get(lang, key))
		TranslationServer.add_translation(translation)
	set_locale(language)

static func set_locale(language: String) -> void:
	locale = language
	TranslationServer.set_locale(locale)

static func text(key: String, values: Dictionary = {}) -> String:
	if catalog.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://localization/strings.json"))
		if parsed is Dictionary:
			catalog = parsed
	var entry: Dictionary = catalog.get(key, {})
	var result: String = entry.get(locale, entry.get("en", key))
	var formatted := values.duplicate()
	for name in formatted:
		if typeof(formatted[name]) == TYPE_FLOAT and float(formatted[name]) == floor(float(formatted[name])):
			formatted[name] = int(formatted[name])
	return result.format(formatted)
