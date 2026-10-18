class_name RigData
extends RefCounted
## Baked skeletal animation data made by tools/spriter_to_json.py, plus its part textures.
## Loaded once per rig folder and shared by every character that uses it.

## Floats per object per frame: file index (-1 hidden), x, y, rotation, scale_x, scale_y, alpha, z, pivot_x, pivot_y
const STRIDE := 10

static var _cache := {}

var dir := ""
var fps := 60.0
var objects: Array[String] = []
var textures: Array[Texture2D] = []
var files: Array[String] = []  # each texture's part name ("Head", "Face 02"...), for swapping art
## animation name -> {"length": seconds, "frames": count, "data": PackedFloat32Array}
var animations := {}


static func load_rig(dir_path: String) -> RigData:
	if _cache.has(dir_path):
		return _cache[dir_path]
	# load() (not FileAccess) so the JSON is packed into Android/exported builds.
	var res = load(dir_path + "/rig.json")
	if res == null or typeof(res.data) != TYPE_DICTIONARY:
		push_error("RigData: cannot load %s/rig.json" % dir_path)
		return null
	var d: Dictionary = res.data
	var rd := RigData.new()
	rd.dir = dir_path
	rd.fps = float(d["fps"])
	for o in d["objects"]:
		rd.objects.append(String(o))
	for f in d["files"]:
		rd.textures.append(load("%s/parts/%s.png" % [dir_path, f["name"]]))
		rd.files.append(String(f["name"]))
	for anim_name in d["animations"]:
		var a: Dictionary = d["animations"][anim_name]
		var flat := PackedFloat32Array()
		for frame in a["frames"]:
			flat.append_array(PackedFloat32Array(frame))
		rd.animations[anim_name] = {"length": float(a["length"]), "frames": a["frames"].size(), "data": flat}
	_cache[dir_path] = rd
	return rd
