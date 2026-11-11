extends "res://game/interactables/interactable.gd"

# Floor lever under a gallows with a spiked log hung on two ropes. Pulling the lever drops the
# raised log, which swings through the spot where the player stands; the first frame the log box
# overlaps the player's body it calls player.hurt(&"hit", ...). A dodge or roll in time escapes
# (hurt returns false while invulnerable). The log then settles and is winched back up.
# Origin: floor point where the player stands to pull the lever (under the pivot).

const Art := preload("res://game/interactables/interactables_art.gd")

signal triggered
# Emitted on the first overlap of a swing; hit is false when the player escaped.
signal impact(player: Node, hit: bool)
signal rearmed

enum State { ARMED, SWINGING, SETTLING, WINCHING }

@export var rope_length := 420.0
# Angle (rad, from vertical, positive towards +x) of the raised log.
@export var raised_angle := 1.05
# Extra margin around the log hit boxes (world units, negative shrinks).
@export var hit_margin := 0.0
@export var gravity := 2600.0
@export var damping := 1.1
@export var settle_time := 1.4
@export var winch_time := 1.3
@export var hit_strength := 1.0

var state := State.ARMED
var angle := 0.0
var _speed := 0.0
var _t := 0.0
var _winch_from := 0.0
var _hit_done := false
var _victim: Node2D
var _lever: Sprite2D
var _log: Sprite2D
var _ropes: Node2D
var _a := 6.0


func _ready() -> void:
	_a = GameScale.art_pixel()
	angle = raised_angle
	var frame := art_sprite(Art.gallows(), Vector2(Art.GALLOWS_ORIGIN))
	frame.name = "Gallows"
	add_child(frame)
	_ropes = Node2D.new()
	_ropes.name = "Ropes"
	_ropes.draw.connect(_draw_ropes)
	add_child(_ropes)
	_log = art_sprite(Art.SPIKED_LOG, Vector2(Art.LOG_ORIGIN))
	_log.scale = Vector2.ONE * Art.LOG_TEXEL
	_log.name = "Log"
	add_child(_log)
	_lever = art_sprite(Art.lever(false), Vector2(-6, -14))
	_lever.name = "Lever"
	_lever.position = Vector2(-108, 0)
	add_child(_lever)
	_update_log()


func get_prompt(_player: Node) -> String:
	return prompt


func can_interact(_player: Node) -> bool:
	return state == State.ARMED


func get_interact_point() -> Vector2:
	return global_position


func interact(player: Node) -> void:
	if state != State.ARMED:
		return
	_victim = player as Node2D
	state = State.SWINGING
	_t = 0.0
	_speed = 0.0
	_hit_done = false
	_lever.texture = Art.lever(true)
	Feedback.sfx(&"trap_snap", global_position + Vector2(0, -600))
	haptic(&"trap_snap", 1.0)
	triggered.emit()


func pivot_local() -> Vector2:
	return Vector2(0, Art.GALLOWS_ORIGIN.y + 8) * _a


func log_center_local() -> Vector2:
	return pivot_local() + Vector2(sin(angle), cos(angle)) * rope_length


# World-space hit boxes of the log (body and spikes, see Art.LOG_HIT_BOXES).
func log_rects() -> Array[Rect2]:
	var c := global_position + _log.position
	var out: Array[Rect2] = []
	for b in Art.LOG_HIT_BOXES:
		out.append(Rect2(c + Vector2(b[0], b[1]) * Art.LOG_TEXEL, Vector2(b[2], b[3]) * Art.LOG_TEXEL).grow(hit_margin))
	return out


func _physics_process(delta: float) -> void:
	match state:
		State.SWINGING, State.SETTLING:
			_t += delta
			var acc := -gravity / rope_length * sin(angle) - damping * _speed
			_speed += acc * delta
			angle += _speed * delta
			if state == State.SWINGING:
				_check_hit()
				# One full pass and back is enough for the hit window.
				if _t > 1.2:
					state = State.SETTLING
					_t = 0.0
			elif _t >= settle_time:
				state = State.WINCHING
				_t = 0.0
				_speed = 0.0
				_winch_from = angle
		State.WINCHING:
			_t += delta
			var k := clampf(_t / winch_time, 0.0, 1.0)
			# Ratchet up in visible clicks.
			k = floorf(k * 12.0) / 12.0
			angle = lerpf(_winch_from, raised_angle, k)
			if _t >= winch_time:
				angle = raised_angle
				state = State.ARMED
				_lever.texture = Art.lever(false)
				Feedback.sfx(&"button_press", global_position, 0.5)
				rearmed.emit()
	_update_log()


func _check_hit() -> void:
	if _hit_done or not is_instance_valid(_victim):
		return
	var body := body_rect(_victim)
	if not log_rects().any(func(r: Rect2): return r.intersects(body)):
		return
	var dir := Vector2(-signf(_speed) if _speed != 0.0 else -1.0, 0.0)
	var hit := hurt(_victim, &"hit", global_position + log_center_local(), dir, hit_strength)
	# Escaping the first overlap (dodge, roll, mercy time) ends the hit window of this swing.
	_hit_done = true
	impact.emit(_victim, hit)


func _update_log() -> void:
	var c := log_center_local()
	var t := float(Art.LOG_TEXEL)
	_log.position = Vector2(roundf(c.x / t) * t, roundf(c.y / t) * t)
	_ropes.queue_redraw()


# Ropes as chunky pixel steps from the beam rings to the log lugs.
func _draw_ropes() -> void:
	for side: float in [-1.0, 1.0]:
		var top: Vector2 = pivot_local() + Vector2(side * 15.0 * _a, 0)
		var bottom: Vector2 = _log.position + Vector2(side * 15.0 * _a, Art.LOG_ROPE_Y * Art.LOG_TEXEL)
		var steps := int(maxf(absf(bottom.x - top.x), absf(bottom.y - top.y)) / _a)
		for i in steps + 1:
			var p: Vector2 = top.lerp(bottom, float(i) / maxf(1.0, steps))
			var q := Vector2(floorf(p.x / _a) * _a, floorf(p.y / _a) * _a)
			_ropes.draw_rect(Rect2(q, Vector2(_a, _a)), Art.ROPE if i % 3 != 2 else Art.ROPE_DARK)
