class_name RigTrack
extends RefCounted
## Keyframe track: [[t, value, ease?], ...] sorted by t. ease names the curve used to arrive at a
## key (default inOut; step holds the previous value). A periodic track wraps over a period of 1.

enum Ease { STEP, LINEAR, IN, OUT, IN_OUT, BACK }
const EASE_NAMES := {"step": Ease.STEP, "linear": Ease.LINEAR, "in": Ease.IN, "out": Ease.OUT, "inOut": Ease.IN_OUT, "back": Ease.BACK}

var times := PackedFloat32Array()
var values := PackedFloat32Array()
var eases := PackedInt32Array()


## time_scale converts key times (e.g. 1 / duration for normalized tracks); component picks one
## entry of array values.
static func from_keys(keys: Array, time_scale := 1.0, component := -1) -> RigTrack:
	var tr := RigTrack.new()
	for k: Array in keys:
		tr.times.append(float(k[0]) * time_scale)
		tr.values.append(float(k[1][component]) if component >= 0 else float(k[1]))
		tr.eases.append(EASE_NAMES[k[2]] if k.size() > 2 else Ease.IN_OUT)
	return tr


## Compiles a tuning dictionary of tracks; array-valued tracks split into name0, name1, ...
static func compile(tracks: Dictionary, time_scale := 1.0) -> Dictionary:
	var out := {}
	for name in tracks:
		var keys: Array = tracks[name]
		if keys[0][1] is Array:
			for i in (keys[0][1] as Array).size():
				out["%s%d" % [name, i]] = from_keys(keys, time_scale, i)
		else:
			out[name] = from_keys(keys, time_scale)
	return out


static func apply_ease(kind: int, t: float) -> float:
	match kind:
		Ease.STEP:
			return 0.0
		Ease.LINEAR:
			return t
		Ease.IN:
			return t * t
		Ease.OUT:
			return 1.0 - (1.0 - t) * (1.0 - t)
		Ease.BACK:
			var k := t - 1.0
			return 1.0 + 2.7 * k * k * k + 1.7 * k * k
	return t * t * (3.0 - 2.0 * t)


func sample(u: float, periodic := false) -> float:
	var n := times.size()
	if n == 1:
		return values[0]
	if u <= times[0]:
		if not periodic:
			return values[0]
		return _segment(n - 1, 0, u + 1.0, 1.0)
	for i in range(1, n):
		if u < times[i]:
			return _segment(i - 1, i, u, 0.0)
	if not periodic:
		return values[n - 1]
	return _segment(n - 1, 0, u, 1.0)


func _segment(i0: int, i1: int, u: float, wrap: float) -> float:
	var t0 := times[i0]
	var span := times[i1] + wrap - t0
	var t := (u - t0) / span if span > 0.0 else 1.0
	return values[i0] + (values[i1] - values[i0]) * apply_ease(eases[i1], clampf(t, 0.0, 1.0))
