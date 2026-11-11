class_name RigData
extends RefCounted
## Skeleton, parts, props and anchors of the adventurer, plus the packed atlas shared by parts and FX.
## Rig units: 1 unit = 1 source PNG pixel, y down, origin on the ground under the hip at rest,
## positive rotation clockwise on screen.

const PIECES_DIR := "res://assets/pecas/"
const EXTRA_DIR := "res://assets/pecas_extra/"
const PROPS_JSON := "res://assets/pecas_extra/props.json"
const ATLAS_WIDTH := 1024
const ATLAS_PAD := 2

# name, parent, x, y, rest rotation (deg). Parent-first; hip stays bone 0 and each arm keeps
# upper arm, forearm and hand consecutive (solve_leg / solve_arm rely on it).
const BONES := [
	["hip", "", 0, -182, 0],
	["waist", "hip", 0, 0, 0],
	["torso", "hip", 0, -15, 0],
	["neck", "torso", 5, -132, 0],
	["head", "neck", 0, 0, 0],
	["hair", "head", 0, -60, 0],
	["scarfWrap", "torso", 2, -128, 6],
	["scarf1", "scarfWrap", -42, -8, 0],
	["scarf2", "scarf1", -70, 28, 0],
	["upperArmB", "torso", 50, -110, 0],
	["foreArmB", "upperArmB", 0, 52, 0],
	["handB", "foreArmB", 0, 58, 0],
	["thighB", "hip", 18, -6, 0],
	["kneeB", "thighB", 18, 96, 0],
	["shinB", "thighB", 18, 96, 0],
	["footB", "shinB", -22, 54, 0],
	["thighF", "hip", -16, -6, 0],
	["kneeF", "thighF", 1, 95, 0],
	["shinF", "thighF", 1, 95, 0],
	["footF", "shinF", -5, 54, 0],
	["upperArmF", "torso", -58, -110, 0],
	["foreArmF", "upperArmF", 0, 52, 0],
	["handF", "foreArmF", 0, 58, 0],
	["gripB", "handB", 0, 36, 90],
	["gripF", "handF", 0, 34, 90],
	["revolverHammer", "gripB", 0, 0, 0],
	["gloveB", "handB", 0, 0, 90],
	["gloveF", "handF", 0, 0, 90],
]

# Base draw order, back to front. pivot (full-image coordinates) lands on the bone joint; src crops.
# cabelo.png is not drawn: the head already carries the hair. The back arm (B) moves in front of the
# head while raised (see the Adventurer draw orders).
const PARTS := [
	{"name": "scarfTail", "bone": "scarf2", "image": "cachecol.png", "pivot": [78, 50], "src": [0, 0, 86, 95]},
	{"name": "scarfMid", "bone": "scarf1", "image": "cachecol.png", "pivot": [148, 22], "src": [72, 0, 84, 95]},
	{"name": "foreArmB", "bone": "foreArmB", "image": "antebraco_dir.png", "pivot": [30, 8]},
	{"name": "handB", "bone": "handB", "image": "mao_dir.png", "pivot": [35, 8]},
	{"name": "upperArmB", "bone": "upperArmB", "image": "braco_superior_dir.png", "pivot": [35, 14]},
	{"name": "thighB", "bone": "thighB", "image": "coxa_dir.png", "pivot": [44, 12]},
	{"name": "footB", "bone": "footB", "image": "bota_dir.png", "pivot": [40, 42], "src": [0, 34, 102, 51]},
	{"name": "shaftB", "bone": "shinB", "image": "bota_dir.png", "pivot": [62, -12], "src": [0, 0, 102, 44]},
	{"name": "kneeB", "bone": "kneeB", "image": "canela_dir.png", "pivot": [62, 40], "src": [0, 19, 87, 55]},
	{"name": "thighF", "bone": "thighF", "image": "coxa_esq.png", "pivot": [46, 12]},
	{"name": "footF", "bone": "footF", "image": "bota_esq.png", "pivot": [40, 42], "src": [0, 34, 105, 51]},
	{"name": "shaftF", "bone": "shinF", "image": "bota_esq.png", "pivot": [45, -12], "src": [0, 0, 105, 44]},
	{"name": "kneeF", "bone": "kneeF", "image": "canela_esq.png", "pivot": [47, 40], "src": [0, 19, 92, 54]},
	{"name": "body", "bone": "torso", "image": "corpo.png", "pivot": [100, 140]},
	{"name": "belt", "bone": "waist", "image": "cinto_bolsa.png", "pivot": [95, 25]},
	{"name": "scarfWrap", "bone": "scarfWrap", "image": "cachecol.png", "pivot": [190, 30], "src": [142, 0, 124, 95]},
	{"name": "foreArmF", "bone": "foreArmF", "image": "antebraco_esq.png", "pivot": [32, 8]},
	{"name": "handF", "bone": "handF", "image": "mao_esq.png", "pivot": [35, 8]},
	{"name": "upperArmF", "bone": "upperArmF", "image": "braco_superior_esq.png", "pivot": [40, 14]},
	{"name": "head", "bone": "head", "image": "cabeca.png", "pivot": [80, 110], "src": [0, 0, 142, 119]},
]

const FOOT_ANKLE_HEIGHT := 39.0
const FOOT_HEEL := -34.0
const FOOT_TOE := 58.0

const LEG_NAMES := {
	"front": {"thigh": "thighF", "knee": "kneeF", "shin": "shinF", "foot": "footF"},
	"back": {"thigh": "thighB", "knee": "kneeB", "shin": "shinB", "foot": "footB"},
}

const ANCHORS := {
	"toeF": ["footF", 58, 30], "toeB": ["footB", 58, 30],
	"heelF": ["footF", -30, 39], "heelB": ["footB", -30, 39],
	"soleF": ["footF", 10, 39], "soleB": ["footB", 10, 39],
	"fistF": ["handF", 0, 66], "fistB": ["handB", 0, 66],
	"chest": ["torso", 22, -92], "headTop": ["head", -8, -112],
	"gripF": ["gripF", 0, 0], "gripB": ["gripB", 0, 0],
}

const PROP_DEFAULTS := {
	"revolver": {"file": "revolver.png", "bone": "gripB", "pivotPoint": "grip", "drawBefore": "handB"},
	"kunai": {"file": "kunai.png", "bone": "gripF", "pivotPoint": "grip", "drawBefore": "handF"},
	"glove_front": {"file": "glove_front.png", "bone": "gloveF", "pivotPoint": "wrist", "drawBefore": "handF", "hides": ["handF"]},
	"glove_back": {"file": "glove_back.png", "bone": "gloveB", "pivotPoint": "wrist", "drawBefore": "handB", "hides": ["handB"]},
	"chair": {"file": "chair.png", "scene": true},
	"bow": {"file": "bow.png", "bone": "gripB", "pivotPoint": "grip", "drawBefore": "handB", "string": ["stringTop", "stringBottom"]},
	"arrow": {"file": "arrow.png", "bone": "gripF", "pivotPoint": "nock", "drawBefore": "handF"},
	"ak47": {"file": "ak47.png", "bone": "gripB", "pivotPoint": "grip", "drawBefore": "handB"},
}

# A new non-point [x, y] pair in props.json must be listed here or it turns into an anchor.
const NON_POINT_KEYS := ["size", "file", "bone", "pivotPoint", "drawBefore", "drawAfter", "hides", "scene", "angle", "pivot", "replaces", "string", "frameSize", "headAnchor", "frames", "field"]


class Leg:
	var thigh: int
	var shin: int
	var foot: int
	var cap: int
	var hip_x: float
	var hip_y: float
	var upper: float
	var upper_angle: float
	var lower: float
	var lower_angle: float


class Part:
	var name: String
	var bone: int
	var image: String
	var pivot: Vector2
	var src: Rect2i  # crop in the source image (size resolved)
	var prop_bit := 0
	var hide_bit := 0
	var follows := ""
	var frame_field := -1  # index into face fields, -1 for regular parts
	var frame_count := 0
	var frame_step := Vector2i.ZERO
	var region: Rect2  # atlas region of the (first) frame
	var box := Rect2()  # opaque bounds relative to the pivot
	var has_box := false
	var string_anchors := PackedStringArray()


class FxSprite:
	var id: int
	var key: String
	var frame_count: int
	var steps: int  # rotation variants per frame
	var rotation_step: float
	var regions: Array[Rect2] = []  # frame * steps + variant
	var origins := PackedVector2Array()


static var _shared: RigData

var bone_names := PackedStringArray()
var parent := PackedInt32Array()
var bone_x := PackedFloat32Array()
var bone_y := PackedFloat32Array()
var rest_rot := PackedFloat32Array()
var hammer_angle := PackedFloat32Array()
var index := {}
var bone_count := 0
var torso := 0
var waist := 0
var legs := {}
var anchors := {}  # name -> Vector3(bone, x, y)
var parts: Array[Part] = []
var part_index := {}
var props := {}  # key -> {bit, file, scene, points, pivot, hides, spec}
var face_fields := PackedStringArray()
var images := {}  # file -> Image
var atlas: ImageTexture
var fx_sprites := {}  # key -> FxSprite
var fx_sprite_list: Array[FxSprite] = []


static func shared() -> RigData:
	if _shared == null:
		_shared = RigData.new()
		_shared._build()
	return _shared


static func release_shared() -> void:
	_shared = null


func bone(name: String) -> int:
	assert(index.has(name), "Unknown bone %s" % name)
	return index[name]


func anchor(name: String) -> Vector3:
	return anchors.get(name, Vector3(-1, 0, 0))


func fx_sprite(key: String) -> FxSprite:
	assert(fx_sprites.has(key), "Unknown FX sprite %s" % key)
	return fx_sprites[key]


func rest_ankle_x(side: String) -> float:
	var leg: Leg = legs[side]
	return bone_x[0] + leg.hip_x + bone_x[leg.shin] + bone_x[leg.foot]


func _build() -> void:
	for i in BONES.size():
		var b: Array = BONES[i]
		index[b[0]] = i
		bone_names.append(b[0])
		parent.append(-1 if b[1] == "" else index[b[1]])
		bone_x.append(float(b[2]))
		bone_y.append(float(b[3]))
		rest_rot.append(deg_to_rad(float(b[4])))
		hammer_angle.append(0.0)
		assert(parent[i] < i, "Bone %s must come after its parent" % b[0])
	bone_count = BONES.size()
	for i in RigBone.NAMES.size():
		assert(bone_names[i] == RigBone.NAMES[i], "RigBone is out of sync with BONES at %d" % i)
	torso = index["torso"]
	waist = index["waist"]
	for side in LEG_NAMES:
		var names: Dictionary = LEG_NAMES[side]
		var leg := Leg.new()
		leg.thigh = index[names.thigh]
		leg.shin = index[names.shin]
		leg.foot = index[names.foot]
		leg.cap = index[names.knee]
		leg.hip_x = bone_x[leg.thigh]
		leg.hip_y = bone_y[leg.thigh]
		leg.upper = Vector2(bone_x[leg.shin], bone_y[leg.shin]).length()
		leg.upper_angle = atan2(-bone_x[leg.shin], bone_y[leg.shin])
		leg.lower = Vector2(bone_x[leg.foot], bone_y[leg.foot]).length()
		leg.lower_angle = atan2(-bone_x[leg.foot], bone_y[leg.foot])
		legs[side] = leg
	for name in ANCHORS:
		var a: Array = ANCHORS[name]
		anchors[name] = Vector3(index[a[0]], a[1], a[2])

	var specs: Array[Dictionary] = []
	for p in PARTS:
		specs.append(p.duplicate())
	for spec in specs:
		_load_image(PIECES_DIR, spec.image)
	_load_props(specs)
	parts.clear()
	for spec in specs:
		parts.append(_make_part(spec))
	for i in parts.size():
		part_index[parts[i].name] = i
	_measure_parts()
	_build_atlas()


func _load_image(dir: String, file: String) -> Image:
	if images.has(file):
		return images[file]
	var path := dir + file
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	images[file] = img
	return img


func _make_part(spec: Dictionary) -> Part:
	var p := Part.new()
	p.name = spec.name
	p.bone = index[spec.bone]
	p.image = spec.image
	var pv: Array = spec.get("pivot", [0, 0])
	p.pivot = Vector2(pv[0], pv[1])
	var img: Image = images.get(spec.image)
	var w := img.get_width() if img else 0
	var h := img.get_height() if img else 0
	if spec.has("src"):
		var s: Array = spec.src
		p.src = Rect2i(int(s[0]), int(s[1]), int(s[2]), int(s[3]))
	else:
		p.src = Rect2i(0, 0, w, h)
	p.prop_bit = spec.get("propBit", 0)
	p.hide_bit = spec.get("hideBit", 0)
	p.follows = spec.get("follows", "")
	if spec.has("frameField"):
		p.frame_field = face_fields.find(spec.frameField)
		p.frame_count = spec.frameCount
		p.frame_step = spec.frameStep
	if spec.has("string"):
		p.string_anchors = PackedStringArray(spec.string)
	return p


func _read_props_json() -> Dictionary:
	if not FileAccess.file_exists(PROPS_JSON):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(PROPS_JSON))
	return data if data is Dictionary else {}


func _load_props(specs: Array[Dictionary]) -> void:
	var all := {}
	for key in PROP_DEFAULTS:
		all[key] = (PROP_DEFAULTS[key] as Dictionary).duplicate()
	var json := _read_props_json()
	for key in json:
		if json[key] is Dictionary:
			var merged: Dictionary = all.get(key, {})
			merged.merge(json[key], true)
			all[key] = merged
	var bit := 1
	for key in all:
		if key == "revolver_hammer":
			continue
		var spec: Dictionary = all[key]
		var file: String = spec.get("file", "%s.png" % key)
		var img := _load_image(EXTRA_DIR, file)
		if img == null:
			continue
		if spec.has("headAnchor") and spec.has("frames"):
			_add_face_part(specs, key, spec, file, img)
			continue
		var pivot_arr: Array = spec.get("pivot", spec.get(spec.get("pivotPoint", ""), [0, 0]))
		var pivot := Vector2(pivot_arr[0], pivot_arr[1])
		var points := {}
		for name in spec:
			var v = spec[name]
			if not NON_POINT_KEYS.has(name) and v is Array and v.size() == 2 and (v[0] is float or v[0] is int):
				points[name] = Vector2(v[0], v[1])
		var prop := {"key": key, "bit": bit, "file": file, "scene": spec.get("scene", false), "points": points, "pivot": pivot, "hides": spec.get("hides", []), "spec": spec}
		props[key] = prop
		bit <<= 1
		if prop.scene or not spec.has("bone") or not index.has(spec.bone):
			continue
		var bone_i: int = index[spec.bone]
		for name in points:
			var pt: Vector2 = points[name] - pivot
			anchors["%s.%s" % [key, name]] = Vector3(bone_i, pt.x, pt.y)
		var part := {"name": key, "bone": spec.bone, "image": file, "pivot": [pivot.x, pivot.y], "prop": key, "propBit": prop.bit}
		if spec.has("string"):
			var names := PackedStringArray()
			for s in spec.string:
				names.append("%s.%s" % [key, s])
			part["string"] = names
		var at := -1
		if spec.has("drawAfter"):
			at = _spec_index(specs, spec.drawAfter)
			if at >= 0:
				at += 1
		elif spec.has("drawBefore"):
			at = _spec_index(specs, spec.drawBefore)
		if at >= 0:
			specs.insert(at, part)
		else:
			specs.append(part)
	_load_hammer(all, specs)
	for key in props:
		for hidden in props[key].hides:
			var i := _spec_index(specs, hidden)
			if i >= 0:
				specs[i]["hideBit"] = specs[i].get("hideBit", 0) | props[key].bit


func _spec_index(specs: Array[Dictionary], name: String) -> int:
	for i in specs.size():
		if specs[i].name == name:
			return i
	return -1


func _add_face_part(specs: Array[Dictionary], key: String, spec: Dictionary, file: String, img: Image) -> void:
	var field: String = spec.get("field", key.split("_")[0])
	var frames := int(spec.frames)
	var fs: Array = spec.get("frameSize", [img.get_width() / frames, img.get_height()])
	var fw := int(fs[0])
	var fh := int(fs[1])
	var head: Dictionary = specs[_spec_index(specs, "head")]
	var pv: Array = spec.get("pivot", [0, 0])
	var anchor_pt: Array = spec.headAnchor
	var horizontal := img.get_width() >= fw * frames
	var part := {
		"name": key, "bone": "head", "image": file,
		"pivot": [pv[0] - (anchor_pt[0] - head.pivot[0]), pv[1] - (anchor_pt[1] - head.pivot[1])],
		"src": [0, 0, fw, fh], "frameField": field, "follows": "head", "frameCount": frames,
		"frameStep": Vector2i(fw, 0) if horizontal else Vector2i(0, fh),
	}
	specs.insert(_spec_index(specs, "head") + 1, part)
	if not face_fields.has(field):
		face_fields.append(field)
	anchors["%s.anchor" % key] = Vector3(index["head"], anchor_pt[0] - head.pivot[0], anchor_pt[1] - head.pivot[1])


func _load_hammer(all: Dictionary, specs: Array[Dictionary]) -> void:
	if not props.has("revolver") or not (all.revolver as Dictionary).has("hammerPivot"):
		return
	var gun: Dictionary = props.revolver
	var hp: Array = all.revolver.hammerPivot
	var bi: int = index["revolverHammer"]
	bone_x[bi] = hp[0] - gun.pivot.x
	bone_y[bi] = hp[1] - gun.pivot.y
	anchors["revolver.hammer"] = Vector3(bi, 0, 0)
	var spec: Dictionary = all.get("revolver_hammer", {})
	if not spec.has("pivot"):
		return
	var file: String = spec.get("file", "revolver_hammer.png")
	if _load_image(EXTRA_DIR, file) == null:
		return
	hammer_angle[bi] = deg_to_rad(float(spec.get("cockedAngle", 0)))
	var part := {"name": "revolverHammer", "bone": "revolverHammer", "image": file, "pivot": spec.pivot, "prop": "revolver", "propBit": gun.bit, "follows": "revolver"}
	var at := _spec_index(specs, "revolver")
	specs.insert(at if at >= 0 else specs.size(), part)


func _measure_parts() -> void:
	for p in parts:
		var img: Image = images.get(p.image)
		if img == null:
			continue
		var used := img.get_region(p.src).get_used_rect()
		if used.size.x <= 0:
			continue
		p.box = Rect2(Vector2(used.position + p.src.position) - p.pivot, used.size)
		p.has_box = true


func _build_atlas() -> void:
	# Collect every image to pack: part crops (whole strips for face parts) and FX sprite variants.
	var entries: Array = []  # [Image, callable target]
	var crops := {}
	for p in parts:
		var img: Image = images.get(p.image)
		if img == null:
			continue
		var rect := p.src
		if p.frame_field >= 0:
			rect = Rect2i(0, 0, img.get_width(), img.get_height())
		var key := "%s:%s" % [p.image, rect]
		if not crops.has(key):
			crops[key] = {"image": img.get_region(rect), "rect": Rect2()}
			entries.append(crops[key])
		p.set_meta("crop", key)
		p.set_meta("crop_origin", rect.position)
	var fx_defs := RigFxSprites.build()
	for def in fx_defs:
		var s := FxSprite.new()
		s.id = fx_sprite_list.size()
		s.key = def.key
		s.frame_count = def.frames.size()
		s.rotation_step = def.rotation_step
		s.steps = maxi(1, roundi(TAU / def.rotation_step)) if def.rotation_step > 0.0 else 1
		var variants: Array = []
		for frame: Image in def.frames:
			for r in s.steps:
				var v := RigFxSprites.rotate_nearest(frame, def.origin, r * s.rotation_step)
				var entry := {"image": v.image, "rect": Rect2()}
				entries.append(entry)
				variants.append(entry)
				s.origins.append(v.origin)
		s.set_meta("variants", variants)
		fx_sprites[s.key] = s
		fx_sprite_list.append(s)

	# Shelf packing, tallest first.
	var order := range(entries.size())
	order.sort_custom(func(a, b): return entries[a].image.get_height() > entries[b].image.get_height())
	var x := ATLAS_PAD
	var y := ATLAS_PAD
	var shelf := 0
	for i in order:
		var img: Image = entries[i].image
		if x + img.get_width() + ATLAS_PAD > ATLAS_WIDTH:
			x = ATLAS_PAD
			y += shelf + ATLAS_PAD
			shelf = 0
		entries[i].rect = Rect2(x, y, img.get_width(), img.get_height())
		x += img.get_width() + ATLAS_PAD
		shelf = maxi(shelf, img.get_height())
	var height := nearest_po2(y + shelf + ATLAS_PAD)
	var sheet := Image.create_empty(ATLAS_WIDTH, height, false, Image.FORMAT_RGBA8)
	for e in entries:
		var img: Image = e.image
		sheet.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(e.rect.position))
	atlas = ImageTexture.create_from_image(sheet)

	for p in parts:
		if not p.has_meta("crop"):
			continue
		var r: Rect2 = crops[p.get_meta("crop")].rect
		var off: Vector2i = p.src.position - (p.get_meta("crop_origin") as Vector2i)
		p.region = Rect2(r.position + Vector2(off), Vector2(p.src.size))
	for s in fx_sprite_list:
		for e in s.get_meta("variants"):
			s.regions.append(e.rect)
