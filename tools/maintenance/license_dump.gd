extends SceneTree
func _initialize() -> void:
	var file := FileAccess.open("res://docs/legal/godot_third_party.txt",FileAccess.WRITE)
	file.store_string(Engine.get_license_text()+"\n\nTHIRD PARTY COMPONENTS\n\n")
	for item in Engine.get_copyright_info():
		file.store_string(JSON.stringify(item,"  ")+"\n\n")
	var licenses := Engine.get_license_info()
	for name in licenses:
		file.store_string(str(name)+"\n"+str(licenses[name])+"\n\n")
	file.close()
	print("Engine license notices saved")
	quit()
