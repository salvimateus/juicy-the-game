extends "res://game/interactables/occupiable.gd"

# Chair or bed from res://game/art/furniture (furniture.json: units, origin at the PNG's bottom-left,
# y up). The art faces +x with the backrest / headboard on the left; facing -1 mirrors it.
# The node origin is the floor point under the seat (chair) or under the middle of the bed.
# The character rests with the furniture behind its back: its origin comes from the rig
# (InteractionActions.furniture_origin when it exists, else CHAIR_SEAT / BED_SEAT), and the
# furniture geometry goes to the rig through adventurer.action_params. Level children draw before
# the player, so the backrest and the headboard stay behind the character.
# A bed may come in two layers (texture_back / texture_front, or bed_back.png / bed_front.png next to
# the texture, or layers.back / layers.front): the front one (blanket and side rail) covers the body once the character lies under
# the blanket, on the rig events UNDER_BLANKET / OUT_OF_BLANKET or, without them, when lie_down
# ends and when get_up starts. Without the layers the single texture is used.

const SPEC_PATH := "res://game/art/furniture/furniture.json"
const RIG_ACTIONS := "res://rig/clips/interaction_actions.gd"

@export var prop := "chair"

const UNDER_BLANKET := &"under_blanket"
const OUT_OF_BLANKET := &"out_of_blanket"

var spec := {}
# PNG bottom-left relative to the node origin, for facing 1.
var art_origin := Vector2.ZERO
var body_line_y := 0.0
var _sprite: Sprite2D
var _front: Sprite2D
var _blanket_events := false


func _ready() -> void:
	spec = _read_spec()
	var w := float(spec.get("width", 0.0))
	var h := float(spec.get("height", 0.0))
	var anchor_x := float(spec.get("seat_center_x", w / 2.0)) if prop == "chair" else w / 2.0
	art_origin = Vector2(-anchor_x, 0.0)
	rest_height = float(spec.get("seat_top_y" if prop == "chair" else "mattress_top_y", rest_height))
	rest_offset = Vector2(_rest_x_from_art_origin() + art_origin.x, 0.0)
	body_line_y = float(spec.get("body_line_y", rest_height))
	var main_path := String(spec.get("texture", ""))
	var back_path := _layer_path("back")
	var front_path := _layer_path("front")
	var layered := back_path != "" and front_path != ""
	_sprite = _make_layer("Sprite", back_path if layered else main_path)
	if layered:
		_front = _make_layer("Front", front_path)
	_apply_facing()


# layers.<name> in the JSON, else texture_<name>, else <texture>_<name>.png beside the main texture.
func _layer_path(layer: String) -> String:
	var layers: Dictionary = spec.get("layers", {}) if spec.get("layers") is Dictionary else {}
	var path := String(layers.get(layer, spec.get("texture_" + layer, "")))
	var suffix := "_" + layer
	if path == "":
		var main := String(spec.get("texture", ""))
		path = main.get_basename() + suffix + "." + main.get_extension() if main != "" else ""
	return path if path != "" and ResourceLoader.exists(path) else ""


# Sprite scaled so the texture spans the JSON size in units (1:1 art or one texel per art pixel).
func _make_layer(node_name: String, path: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.centered = false
	s.texture = load(path) as Texture2D if path != "" else null
	if s.texture:
		var w := float(spec.get("width", s.texture.get_width()))
		var k := w / float(s.texture.get_width())
		if not is_equal_approx(k, roundf(k)) and not is_equal_approx(k, 1.0):
			push_warning("%s: %s is %s px for %s units" % [prop, path, s.texture.get_size(), w])
		s.scale = Vector2.ONE * k
	add_child(s)
	return s


func _read_spec() -> Dictionary:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing %s" % SPEC_PATH)
		return {}
	var data = JSON.parse_string(file.get_as_text())
	return data.get(prop, {}) if data is Dictionary else {}


# Character origin x measured from the PNG's left edge (facing 1).
func _rest_x_from_art_origin() -> float:
	var rig_script := load(RIG_ACTIONS) as Script if ResourceLoader.exists(RIG_ACTIONS) else null
	if rig_script and rig_script.get_script_method_list().any(func(m): return m.name == "furniture_origin"):
		var o = (rig_script as Variant).furniture_origin(prop, spec)
		if o is Vector2:
			return o.x
	# Fallback: the rig's seat point relative to its origin (seat at negative x for facing 1).
	var consts := rig_script.get_script_constant_map() if rig_script else {}
	var seat: Vector2 = consts.get("CHAIR_SEAT" if prop == "chair" else "BED_SEAT", Vector2(-120, -rest_height))
	return _seat_x() - seat.x


# Seat point x from the PNG's left edge: the seat centre, or for the bed the spot on the edge
# where the character sits before lying back (40% of the way from pillow to foot).
func _seat_x() -> float:
	if prop == "chair":
		return float(spec.get("seat_center_x", 0.0))
	var pillow := float(spec.get("pillow_x", 0.0))
	return pillow + 0.4 * (float(spec.get("foot_x", pillow)) - pillow)


# Furniture geometry in character space (origin at the resting character, facing 1, y up negative).
func furniture_params() -> Dictionary:
	var rest_x := _rest_x_from_art_origin()
	var p := {kind = prop, rest_height = rest_height, body_line_y = body_line_y}
	for key in ["seat_back_x", "seat_front_x", "seat_center_x", "pillow_x", "pillow_left_x", "foot_x"]:
		if spec.has(key):
			p[key] = float(spec[key]) - rest_x
	if spec.has("blanket_peak_y"):
		p["blanket_peak_y"] = float(spec.blanket_peak_y)
	if spec.get("blanket_mound_x") is Array and spec.blanket_mound_x.size() == 2:
		p["blanket_mound_x"] = [float(spec.blanket_mound_x[0]) - rest_x, float(spec.blanket_mound_x[1]) - rest_x]
	return p


func _start_rest() -> void:
	var rig := adventurer_of(occupant)
	if rig and &"action_params" in rig:
		var p := furniture_params()
		rig.action_params[&"rest_height"] = rest_height
		rig.action_params[&"body_line_y"] = body_line_y
		rig.action_params[&"furniture"] = p
		if p.has("pillow_x"):
			rig.action_params[&"pillow_x"] = p.pillow_x
	if _front and rig and rig.has_signal(&"action_event") and not rig.action_event.is_connected(_on_rig_event):
		rig.action_event.connect(_on_rig_event)
	super._start_rest()


func _on_rig_event(id: StringName, event_name: StringName) -> void:
	if event_name == UNDER_BLANKET:
		_blanket_events = true
		_set_front(true)
	elif event_name == OUT_OF_BLANKET:
		_blanket_events = true
		_set_front(false)


# Over the body: one above the occupant's absolute z (the player scene has its own z_index, and a
# tie would fall back to tree order, where the level draws first). Behind: the level's order.
func _set_front(over_body: bool) -> void:
	if _front == null:
		return
	if over_body and is_instance_valid(occupant):
		_front.z_as_relative = false
		_front.z_index = _absolute_z(occupant) + 1
	else:
		_front.z_as_relative = true
		_front.z_index = 0


static func _absolute_z(item: Node) -> int:
	var z := 0
	var n := item
	while n is CanvasItem:
		z += (n as CanvasItem).z_index
		if not (n as CanvasItem).z_as_relative:
			break
		n = n.get_parent()
	return z


func _on_rig_action_finished(id: StringName) -> void:
	if id == enter_action and not _blanket_events and not _exit_pending:
		_set_front(true)
	super._on_rig_action_finished(id)


func leave() -> void:
	if state == State.OCCUPIED and not _blanket_events and not _settling():
		_set_front(false)
	super.leave()


func _release() -> void:
	var rig := _rig
	if rig and is_instance_valid(rig) and rig.has_signal(&"action_event") and rig.action_event.is_connected(_on_rig_event):
		rig.action_event.disconnect(_on_rig_event)
	_set_front(false)
	super._release()


func _apply_facing() -> void:
	for s in [_sprite, _front]:
		if s == null or s.texture == null:
			continue
		var w: float = s.texture.get_width() * s.scale.x
		var h: float = s.texture.get_height() * s.scale.y
		s.flip_h = facing < 0
		var left := art_origin.x if facing >= 0 else -(art_origin.x + w)
		s.position = Vector2(left, -h)


# Horizontal extent of the art relative to the origin, for level layout.
func get_extent() -> Vector2:
	var w := float(spec.get("width", 0.0))
	var left := art_origin.x if facing >= 0 else -(art_origin.x + w)
	return Vector2(left, left + w)
