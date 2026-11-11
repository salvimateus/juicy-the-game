extends RefCounted
## Shared helpers for the hit reactions.


## 1 for a hit from the front (travelling against the facing), -1 from behind.
static func hit_side(host) -> float:
	var d: Vector2 = host.action_params.get(&"hit_direction", Vector2.LEFT)
	return -1.0 if d.x * host.facing > 0.001 else 1.0


## Decaying shake added to the pose (screen shake request and sprite jitter).
static func shake(pose: RigPose, since: float, amp: float, seconds: float, freq: float) -> void:
	if since < 0.0 or since >= seconds:
		return
	var decay := pow(1.0 - since / seconds, 2.0)
	var p := TAU * freq * since
	pose.shake_x += amp * decay * sin(p)
	pose.shake_y += amp * 0.6 * decay * sin(p * 1.3 + 1.0)


static func window01(u: float, span: Array) -> float:
	return clampf((u - float(span[0])) / (float(span[1]) - float(span[0])), 0.0, 1.0)


static func ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)
