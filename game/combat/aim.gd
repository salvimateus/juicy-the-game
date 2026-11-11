extends RefCounted

# Shared aim for every weapon: the right stick (aim_left/right/up/down) points the shot; the mouse
# does the same from the shoulder to the cursor, its distance (up to mouse_range) acting as the
# stick's deflection. Pointing behind (horizontal part past flip_threshold) turns the character
# and the angle mirrors; near vertical the facing stays. The left stick also turns the character;
# when both disagree in the same frame the right stick wins. A centred stick keeps the last angle.

var mouse_range := 600.0
# Horizontal part of the aim vector, against the facing, that turns the character around.
var flip_threshold := 0.25
var shoulder := Vector2(0, -290)

var player
# Angle relative to the facing (radians; negative up), and the stick deflection 0..1.
var angle := 0.0
var magnitude := 0.0
var allow_mouse := true
var mouse_mode := false


func _init(owner_player) -> void:
	player = owner_player


func reset() -> void:
	angle = 0.0
	magnitude = 0.0


# Reads the inputs; up_limit / down_limit in radians (negative up).
func update(up_limit: float, down_limit: float) -> void:
	var v := Vector2(player.axis(&"aim_left", &"aim_right"), player.axis(&"aim_up", &"aim_down"))
	if v.length() > 0.01:
		mouse_mode = false
	elif allow_mouse and mouse_mode:
		v = (player.get_global_mouse_position() - (player.global_position + shoulder)) / mouse_range
	var aim_turn := absf(v.x) > flip_threshold
	if aim_turn and int(signf(v.x)) != player.facing:
		_turn(int(signf(v.x)))
	elif not aim_turn:
		var x: float = player.axis(&"move_left", &"move_right")
		if absf(x) >= 0.5 and int(signf(x)) != player.facing:
			_turn(int(signf(x)))
	magnitude = clampf(v.length(), 0.0, 1.0)
	if magnitude < 0.01:
		return
	# Relative to the facing; within the flip dead zone (near vertical) the side stays as it is.
	angle = clampf(atan2(v.y, absf(v.x)), up_limit, down_limit)


# The rig turns inside its aim loops (and the revolver's fire and cocking) when can_flip_now().
func _turn(dir: int) -> void:
	var rig = player.rig
	if rig.has_method(&"can_flip_now") and not rig.can_flip_now():
		return
	player.set_facing(dir)


func on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and allow_mouse:
		mouse_mode = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3:
		mouse_mode = false
