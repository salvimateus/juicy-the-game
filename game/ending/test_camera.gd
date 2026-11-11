extends Camera2D

# Fixed camera of the ending test bench with the add_shake contract of game/game_camera.gd.

var _shake := 0.0
var _shake_time := 0.0
var _shake_left := 0.0


func add_shake(amount: float, duration: float) -> void:
	if amount * maxf(duration, 0.001) >= _shake * _shake_left:
		_shake = amount
		_shake_time = maxf(duration, 0.001)
		_shake_left = _shake_time


func _process(delta: float) -> void:
	offset = Vector2.ZERO
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var k := _shake * _shake_left / _shake_time
		offset = Vector2(randf_range(-k, k), randf_range(-k, k))
