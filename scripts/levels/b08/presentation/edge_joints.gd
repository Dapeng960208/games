extends RefCounted
## Two exterior assembly samples; exact floor subtraction belongs to the host.
const ROOT := "asset://b08/rooms/l43/edge_joints/"
static func configure(environment: Node2D) -> bool:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(ROOT+"manifest.json")))
	if not data is Dictionary: environment.errors.append("Invalid edge-joint manifest"); return false
	for item: Dictionary in data.attachments:
		var texture: Texture2D=preload("res://scripts/infrastructure/assets/texture_sampler.gd").sampled(ROOT+str(item.file))
		if texture==null: environment.errors.append("Missing edge joint: "+str(item.file)); continue
		environment.textures[item.file]=texture
		environment.snapshot[item.file]={"size":texture.get_size(),"sha256":FileAccess.get_sha256(AssetCatalog.resolve(ROOT+str(item.file)))}
		environment.register(item.file,Vector2(item.source_anchor[0],item.source_anchor[1]),Vector2(item.blueprint_anchor[0],item.blueprint_anchor[1]),float(item.world_per_source_pixel)/.58)
		var layer: Dictionary=environment.layers.pop_back()
		layer["edge_joint"]=true
		# A convex painted cap is not a new walkable projection into the vertical
		# step. Keep the sample strictly below the real south contact baseline.
		var baseline: float=float(item.blueprint_anchor[1])*.58
		var allowed: PackedVector2Array=environment.polygon(Rect2(0,baseline,1624,1044-baseline))
		var pieces: Array[PackedVector2Array]=[]
		for shape: PackedVector2Array in layer.shapes: pieces.append_array(Geometry2D.intersect_polygons(shape,allowed))
		layer.shapes=pieces
		# Existing arch and fascia remain in front of each supporting foundation.
		var index: int=environment.layers.size()
		for i: int in environment.layers.size():
			if environment.layers[i].file=="bridge_arch.png": index=i; break
		environment.layers.insert(index,layer)
	return environment.errors.is_empty()
