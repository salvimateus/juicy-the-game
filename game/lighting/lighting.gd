extends CanvasLayer

# Darkness overlay for LightingZones: one fullscreen multiply pass above the world and below the
# HUD layers (9, 10). While the player stands in a zone it fades in, blacks out everything outside
# the zone rect and lights the inside with a flickering, dithered torch around the player.
# Consumed through preload (no class_name): `Lighting.flash(global_pos, radius, duration)`.
# A LightingZone spawns one in the current scene when none exists.

const SCRIPT_PATH := "res://game/lighting/lighting.gd"
const SHADER := preload("res://game/lighting/lighting.gdshader")
const GameScale := preload("res://game/game_scale.gd")
const PLAYER_GROUP := &"player"

static var _current: CanvasLayer
static var _zones: Array[Node] = []

# Torch animation updates at this rate, stepped like the sprite animation.
@export var flicker_fps := 12.0
# Max centre jitter in world units (one art pixel is 6).
@export var torch_jitter := 6.0
@export var flash_color := Color(1.0, 0.92, 0.7)

var _overlay: ColorRect
var _mat: ShaderMaterial
var _player: Node2D
var _zone: Node
var _fade := 0.0
var _noise := FastNoiseLite.new()
var _flicker_clock := 0.0
var _flicker_step := 0.0
var _radius_k := 1.0
var _intensity_k := 1.0
var _jitter := Vector2.ZERO
var _prev_pos := Vector2.ZERO
var _cur_pos := Vector2.ZERO
var _flash_pos := Vector2.ZERO
var _flash_radius := 0.0
var _flash_left := 0.0


static func flash(global_pos: Vector2, radius := 520.0, duration := 0.034) -> void:
	if is_instance_valid(_current):
		_current.start_flash(global_pos, radius, duration)


static func ensure(from: Node) -> void:
	if is_instance_valid(_current) or not from.is_inside_tree():
		return
	var host := from.get_tree().current_scene
	if host == null:
		return
	var node: CanvasLayer = load(SCRIPT_PATH).new()
	node.name = "Lighting"
	_current = node
	host.add_child.call_deferred(node)


static func register_zone(zone: Node) -> void:
	if not _zones.has(zone):
		_zones.append(zone)


static func unregister_zone(zone: Node) -> void:
	_zones.erase(zone)


func _init() -> void:
	layer = 5
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.9
	_noise.fractal_octaves = 2
	_noise.seed = 7


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null


func _ready() -> void:
	process_priority = 1000
	process_physics_priority = 1000
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = _mat
	add_child(_overlay)
	visible = false


func start_flash(global_pos: Vector2, radius: float, duration: float) -> void:
	_flash_pos = global_pos
	_flash_radius = radius
	_flash_left = duration


func _find_player() -> Node2D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
		if _player:
			_cur_pos = _player.global_position
			_prev_pos = _cur_pos
	return _player


# Physics-interpolated player position: the 2D API has no interpolated getter.
func _physics_process(_delta: float) -> void:
	if _find_player() == null:
		return
	_prev_pos = _cur_pos
	_cur_pos = _player.global_position
	if _prev_pos.distance_squared_to(_cur_pos) > 160000.0:
		_prev_pos = _cur_pos


func _player_pos() -> Vector2:
	if get_tree().physics_interpolation and _player.is_physics_interpolated_and_enabled():
		return _prev_pos.lerp(_cur_pos, Engine.get_physics_interpolation_fraction())
	return _player.global_position


func _active_zone(point: Vector2) -> Node:
	var best: Node = null
	for z in _zones:
		if z.contains(point) and (best == null or z.zone_priority > best.zone_priority):
			best = z
	return best


func _process(delta: float) -> void:
	if _find_player() == null:
		return
	var pos := _player_pos()
	var inside := _active_zone(pos)
	if inside:
		_zone = inside
	if _zone == null or not is_instance_valid(_zone):
		_zone = null
		_fade = 0.0
		visible = false
		return
	var fade_time: float = maxf(_zone.fade_time, 0.001)
	_fade = move_toward(_fade, 1.0 if inside else 0.0, delta / fade_time)
	if _fade <= 0.0 and inside == null:
		_zone = null
		visible = false
		return
	visible = true
	_update_flicker(delta)
	_flash_left -= delta
	_push(pos)


func _update_flicker(delta: float) -> void:
	_flicker_clock += delta
	var step := 1.0 / maxf(flicker_fps, 1.0)
	if _flicker_clock < step:
		return
	_flicker_clock = fmod(_flicker_clock, step)
	_flicker_step += 1.0
	var t := _flicker_step * step
	var amount: float = _zone.flicker_amount
	# Two noise tracks plus a rare sharper dip read as a flame rather than a breathing sine.
	var slow := _noise.get_noise_1d(t)
	var fast := _noise.get_noise_1d(t * 3.7 + 100.0)
	var dip := minf(_noise.get_noise_1d(t * 1.3 + 300.0) + 0.45, 0.0)
	_radius_k = 1.0 + amount * (0.7 * slow + 0.3 * fast)
	_intensity_k = clampf(1.0 + amount * (0.5 * slow + 0.6 * fast) + dip * amount * 2.0, 0.75, 1.0)
	_jitter = Vector2(_noise.get_noise_1d(t * 2.3 + 500.0), _noise.get_noise_1d(t * 2.9 + 700.0)) * torch_jitter


func _push(pos: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var zoom_k := xf.x.x
	var cell := GameScale.art_pixel() * zoom_k
	var origin := Vector2(fposmod(xf.origin.x, cell), fposmod(xf.origin.y, cell))
	var rect: Rect2 = xf * _zone.world_rect()
	var center: Vector2 = xf * (pos + _zone.torch_offset + _jitter)
	_mat.set_shader_parameter(&"torch_pos", center)
	_mat.set_shader_parameter(&"torch_radius", _zone.torch_radius * zoom_k * _radius_k)
	_mat.set_shader_parameter(&"torch_intensity", _intensity_k)
	_mat.set_shader_parameter(&"torch_color", _zone.torch_color)
	_mat.set_shader_parameter(&"tunnel_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	_mat.set_shader_parameter(&"cell_px", cell)
	_mat.set_shader_parameter(&"grid_origin", origin)
	_mat.set_shader_parameter(&"ambient", _zone.ambient)
	_mat.set_shader_parameter(&"ambient_color", _zone.ambient_color)
	_mat.set_shader_parameter(&"outside_black", _zone.outside_black)
	_mat.set_shader_parameter(&"fade", smoothstep(0.0, 1.0, _fade))
	_mat.set_shader_parameter(&"bands", float(_zone.bands))
	_mat.set_shader_parameter(&"dither_width", _zone.dither_width)
	if _flash_left > 0.0:
		var fp: Vector2 = xf * _flash_pos
		_mat.set_shader_parameter(&"flash", Vector4(fp.x, fp.y, _flash_radius * zoom_k, 1.0))
		_mat.set_shader_parameter(&"flash_color", flash_color)
	else:
		_mat.set_shader_parameter(&"flash", Vector4.ZERO)
