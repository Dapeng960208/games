extends Node
## Headless production-asset integrity, geometry mapping and residency checks.
## No generated working copies, screenshots, profiles or artifact inputs needed.
const Detail = preload("res://scripts/presentation/world/environment_detail.gd")
const DESTINATION := Rect2(17,23,2082.0513,1410.8108)
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("ENVIRONMENT_NATIVE_RESOURCES: "+message)
func digest(bytes: PackedByteArray) -> String:
 var context := HashingContext.new()
 context.start(HashingContext.HASH_SHA256)
 context.update(bytes)
 return context.finish().hex_encode()
func texture_checks(sprite: Sprite2D, tile: Dictionary, source_size: Vector2) -> void:
 var dimensions: Array = tile.native_size
 var rect_values: Array = tile.source_rect
 var rect := Rect2(rect_values[0],rect_values[1],rect_values[2],rect_values[3])
 var texture: Texture2D = sprite.texture
 check(texture.get_size()==Vector2(dimensions[0],dimensions[1]),"actual native dimensions match manifest")
 check(texture.get_width()/rect.size.x>=2.35 and texture.get_height()/rect.size.y>=2.35,"genuine source density supports physical 2K")
 check(sprite.position.is_equal_approx(DESTINATION.position+rect.position/source_size*DESTINATION.size),"tile position preserves exact source mapping")
 check((sprite.scale*texture.get_size()).is_equal_approx(rect.size/source_size*DESTINATION.size),"tile extent preserves exact source mapping")
 var pixels := texture.get_image()
 check(pixels!=null and pixels.has_mipmaps(),"runtime texture has mipmaps")
 if pixels==null: return
 if pixels.is_compressed(): check(pixels.decompress()==OK,"lossless native texture decodes")
 pixels.clear_mipmaps()
 pixels.convert(Image.FORMAT_RGB8)
 check(digest(pixels.get_data())==str(tile.decoded_rgb_sha256),"runtime base RGB equals original generation pixels")
 check(digest(FileAccess.get_file_as_bytes(AssetCatalog.resolve(str(tile.texture))))==str(tile.webp_sha256),"shipped lossless file hash matches")
func _ready() -> void:
 var rooms := AssetCatalog.directories(Detail.ROOT)
 if rooms.is_empty():
  check(false,"formal native room asset directory exists")
  get_tree().quit(1)
  return
 var inspected := 0
 var layer := Detail.new()
 add_child(layer)
 for registered_id: String in rooms:
  var id := registered_id.to_upper()
  var path := Detail.ROOT+id+"/manifest.json"
  if not FileAccess.file_exists(AssetCatalog.resolve(path)): continue
  var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path)))
  # Candidate packs are deliberately unavailable to normal gameplay.
  if not bool(manifest.get("approved",false)):
   check(not layer.configure(id,DESTINATION),id+" unreviewed pack remains disabled")
   continue
  inspected += 1
  check(digest(FileAccess.get_file_as_bytes(AssetCatalog.resolve(str(manifest.source_texture))))==str(manifest.source_sha256),id+" original geometry-reference painting unchanged")
  check(layer.configure(id,DESTINATION),id+" approved room loads")
  check(layer.tiles.size()==6,id+" loads exactly six owned native textures")
  var references: Array[WeakRef]=[]
  for index: int in layer.tiles.size():
   references.append(weakref(layer.tiles[index].texture))
   texture_checks(layer.tiles[index],manifest.tiles[index],Vector2(manifest.source_size[0],manifest.source_size[1]))
  layer.clear()
  check(layer.resident_bytes==0 and layer.tiles.is_empty(),id+" clears residency accounting")
  for reference: WeakRef in references: check(reference.get_ref()==null,id+" native texture released, no global cache retention")
 check(inspected>0,"at least one room is actually approved")
 check(not layer.configure("NO_SUCH_ROOM",DESTINATION),"missing pack retains original fallback")
 layer.free()
 print("ENVIRONMENT_NATIVE_RESOURCES_RESULT approved_rooms=",inspected," checks=",checks," failures=",failures)
 get_tree().quit(1 if failures else 0)
