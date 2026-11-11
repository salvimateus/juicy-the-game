shader_type canvas_item;
render_mode blend_mul, unshaded;

// Multiplies the frame below: black outside the zone rect, a dim ambient inside it and a banded,
// Bayer-dithered torch (plus an optional flash) sampled per art pixel. All positions in screen units.

const float BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };

uniform vec2 torch_pos;
uniform float torch_radius = 200.0;
uniform float torch_intensity = 1.0;
uniform vec3 torch_color : source_color = vec3(1.0, 0.72, 0.42);
uniform vec4 tunnel_rect;
uniform float cell_px = 3.0;
uniform vec2 grid_origin;
uniform float ambient = 0.08;
uniform vec3 ambient_color : source_color = vec3(0.6, 0.6, 0.8);
uniform float outside_black = 1.0;
uniform float fade = 0.0;
uniform float bands = 4.0;
uniform float dither_width = 0.5;
// Brightest band lerps this far from torch_color to white, so the body keeps its own colours.
uniform float core_white = 0.5;
// xy centre, z radius, w strength (0 = off).
uniform vec4 flash;
uniform vec3 flash_color : source_color = vec3(1.0, 0.92, 0.7);

varying vec2 screen_pos;

void vertex() {
	screen_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Normalized distance -> band level in [0, 1], dithered only across the band edges. The quadratic
// falloff and the extra step keep a wide solid core (0.45 of the radius with four bands).
float band_level(float d, float threshold) {
	float t = clamp(1.0 - d * d, 0.0, 1.0) * (bands + 1.0);
	float lo = floor(t);
	float w = max(dither_width, 0.001);
	float up = step(threshold, (t - lo - (1.0 - w)) / w);
	return min(lo + up, bands) / bands;
}

void fragment() {
	vec2 p = screen_pos;
	vec2 cell = floor((p - grid_origin) / cell_px);
	vec2 center = grid_origin + (cell + 0.5) * cell_px;
	int i = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	float threshold = (BAYER[i] + 0.5) / 16.0;

	float level = band_level(length(center - torch_pos) / torch_radius, threshold);
	// Four bands light 1, .67, .39, .17 of the scene.
	float k = level * (0.55 + 0.45 * level) * torch_intensity;
	vec3 tint = mix(torch_color, vec3(1.0), core_white * level * level);
	vec3 light = ambient_color * ambient + tint * k * (1.0 - ambient);

	if (flash.w > 0.0) {
		float f = band_level(length(center - flash.xy) / flash.z, threshold);
		light = max(light, flash_color * f * flash.w);
	}

	vec2 lo = tunnel_rect.xy;
	vec2 hi = lo + tunnel_rect.zw;
	float inside = step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
	vec3 result = mix(vec3(1.0 - outside_black), min(light, vec3(1.0)), inside);
	COLOR = vec4(mix(vec3(1.0), result, fade), 1.0);
}
