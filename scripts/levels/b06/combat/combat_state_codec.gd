extends RefCounted
## Closed JSON codec for isolated B06 combat snapshots. It never persists raw
## instance IDs, engine Objects, textures, Callables or executable resources.
const MAX_NODES:=20000
static func encode(value:Variant,actor_to_id:Callable)->Dictionary:
	var budget:=[0]
	var result:=_encode(value,actor_to_id,budget,0)
	return {"ok":bool(result.ok),"value":result.get("value")}
static func _encode(value:Variant,resolver:Callable,budget:Array,depth:int)->Dictionary:
	budget[0]+=1
	if depth>32 or int(budget[0])>MAX_NODES: return {"ok":false}
	if value==null or value is bool or value is String:
		if value is String and value.length()>4096: return {"ok":false}
		return {"ok":true,"value":value}
	if value is int or value is float:
		return {"ok":is_finite(float(value)) and absf(float(value))<=1e15,"value":value}
	if value is StringName: return {"ok":true,"value":str(value)}
	if value is Vector2: return {"ok":value.is_finite(),"value":{"$b06":"v2","x":value.x,"y":value.y}}
	if value is Color: return {"ok":is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a),"value":{"$b06":"color","v":[value.r,value.g,value.b,value.a]}}
	if value is WeakRef:
		var actor:Variant=value.get_ref()
		if not is_instance_valid(actor) or not resolver.is_valid(): return {"ok":false}
		var id:Variant=resolver.call(actor)
		if not id is String or id.is_empty() or id.length()>192: return {"ok":false}
		return {"ok":true,"value":{"$b06":"actor","id":id}}
	if value is Array:
		var array:Array=[]
		for item:Variant in value:
			var encoded:=_encode(item,resolver,budget,depth+1)
			if not encoded.ok: return encoded
			array.append(encoded.value)
		return {"ok":true,"value":array}
	if value is Dictionary:
		var dict:Dictionary={}
		for key:Variant in value:
			if (not key is String and not key is StringName) or key=="$b06": return {"ok":false}
			if key=="owner_id": continue
			if key=="hit_ids":
				var ids:Array=[]
				for instance:Variant in value[key]:
					var actor:Variant=instance_from_id(int(instance))
					if not is_instance_valid(actor): return {"ok":false}
					var id:Variant=resolver.call(actor)
					if not id is String or id.is_empty(): return {"ok":false}
					ids.append(id)
				dict["b06_hit_actor_ids"]=ids
				continue
			var encoded:=_encode(value[key],resolver,budget,depth+1)
			if not encoded.ok: return encoded
			dict[str(key)]=encoded.value
		return {"ok":true,"value":dict}
	return {"ok":false}
static func decode(value:Variant,id_to_actor:Callable)->Dictionary:
	var budget:=[0]
	return _decode(value,id_to_actor,budget,0)
static func _decode(value:Variant,resolver:Callable,budget:Array,depth:int)->Dictionary:
	budget[0]+=1
	if depth>32 or int(budget[0])>MAX_NODES: return {"ok":false}
	if value==null or value is bool or value is String:
		return {"ok":not value is String or value.length()<=4096,"value":value}
	if value is int or value is float: return {"ok":is_finite(float(value)) and absf(float(value))<=1e15,"value":value}
	if value is Array:
		var array:Array=[]
		for item:Variant in value:
			var decoded:=_decode(item,resolver,budget,depth+1)
			if not decoded.ok: return decoded
			array.append(decoded.value)
		return {"ok":true,"value":array}
	if not value is Dictionary: return {"ok":false}
	if value.has("$b06"):
		match str(value["$b06"]):
			"v2":
				if value.size()!=3 or not _number(value.get("x")) or not _number(value.get("y")): return {"ok":false}
				return {"ok":true,"value":Vector2(value.x,value.y)}
			"color":
				if value.size()!=2 or not value.get("v") is Array or value.v.size()!=4: return {"ok":false}
				for channel:Variant in value.v:
					if not _number(channel): return {"ok":false}
				return {"ok":true,"value":Color(value.v[0],value.v[1],value.v[2],value.v[3])}
			"actor":
				if value.size()!=2 or not value.get("id") is String or not resolver.is_valid(): return {"ok":false}
				var actor:Variant=resolver.call(value.id)
				if not actor is Node2D or not is_instance_valid(actor) or actor.is_queued_for_deletion(): return {"ok":false}
				return {"ok":true,"value":weakref(actor)}
			_: return {"ok":false}
	var result:Dictionary={}
	for key:Variant in value:
		if not key is String or key=="owner_id" or key=="hit_ids": return {"ok":false}
		if key=="b06_hit_actor_ids":
			if not value[key] is Array: return {"ok":false}
			var ids:Array=[]
			for id:Variant in value[key]:
				if not id is String: return {"ok":false}
				var actor:Variant=resolver.call(id)
				if not actor is Node2D or not is_instance_valid(actor): return {"ok":false}
				ids.append(actor.get_instance_id())
			result["hit_ids"]=ids
			continue
		var decoded:=_decode(value[key],resolver,budget,depth+1)
		if not decoded.ok: return decoded
		result[key]=decoded.value
	if result.has("owner"):
		if not result.owner is WeakRef: return {"ok":false}
		result["owner_id"]=result.owner.get_ref().get_instance_id()
	return {"ok":true,"value":result}
static func _number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<=1e15
