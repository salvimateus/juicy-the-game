extends RefCounted
# Visual knobs of the fog layers (uniforms of fog_layer.gdshader). Cost knobs: levels (none),
# detail (one value noise per layer pixel), all others are free.
# The simulated density runs from 0 at the top of the blanket to about 1 on the floor; the ramp
# starts just above 0 so the top breaks into a sparse stipple, and saturates well before the floor.
# color_deep is darker and greyer than the horizon sky (#b2d2ee) so the core reads over the sky;
# color_light is lighter than it, so the thin top reads as a bright haze over dark ground.

const COMMON := {
	ramp_lo = 0.05, ramp_hi = 0.75, ramp_gamma = 0.5, levels = 4.0,
	bank_scale = 0.00025, bank_min = 0.7, bank_speed = 0.004,
	wisp_scale = Vector2(0.0011, 0.016), wisp_amount = 0.35,
	swamp_tint = 0.12, color_swamp = Color(0.678, 0.718, 0.682),
}
const BACK := {alpha_max = 0.8, wisp_speed = 1.0,
	color_light = Color("#f6faff"), color_deep = Color("#98adc2")}
const FRONT := {alpha_max = 0.8, wisp_speed = 1.6, strip_alpha_max = 0.62,
	color_light = Color("#eef4fa"), color_deep = Color("#91a6bc"), color_front = Color("#8ca1b7")}
# Wisps off on LOW (Fog.Quality order: LOW, MEDIUM, HIGH).
const DETAIL_BY_QUALITY := [false, true, true]
