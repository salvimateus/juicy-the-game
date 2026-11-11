shader_type canvas_item;
render_mode unshaded;

// Pixel-art render of the fog simulation on the art grid: the density is read once per art
// pixel and mapped to a continuous ramp quantized to a few levels, ordered-dithered (Bayer 4x4,
// locked to the world art grid) between neighbouring levels, so the top of the blanket breaks
// into a graded stipple. Large slow banks and wind-stretched wisps reshape the visible density
// without touching the simulation. Both layers draw the whole blanket at every height, split by a
// simulated depth, so characters sit inside the fog. Back layer: behind the level, so the ground
// hides it without clipping. Front layer: over the characters, plus a denser strip at the shins
// (below knee_hi at rest).

uniform sampler2D sim_tex : filter_linear, repeat_disable;
uniform sampler2D solid_tex : filter_nearest, repeat_disable;
uniform sampler2D rest_tex : filter_linear, repeat_disable;
uniform vec2 sim_origin;
uniform vec2 sim_world_size;
uniform vec2 solid_origin;
uniform vec2 solid_size;
uniform vec2 rest_origin;
uniform vec2 rest_size;
uniform float rest_h_max = 1150.0;
uniform float rest_range = 1.6;
uniform vec2 wind = vec2(18.0, 0.0);
uniform float time;
uniform float density_scale = 1.0;
uniform float art = 6.0;
uniform bool front = false;
uniform float knee_lo = 30.0;
uniform float knee_hi = 95.0;
uniform int ground_sink_px = 7;
uniform int stone_sink_px = 2;

// Ramp: density ramp_lo..ramp_hi maps to 0..1, bent by ramp_gamma (0..2: 1 = linear, 2 = squared,
// 0 = 2g - g^2) and quantized to `levels`. alpha_max is the total alpha of both layers stacked at
// the top level (kept under 80%, so what is behind is tinted, never hidden); front_share is the range of that total
// the front layer takes, driven by a slow depth noise. Values come from fog_tuning.gd.
uniform float ramp_lo = 0.05;
uniform float ramp_hi = 0.75;
uniform float ramp_gamma = 0.5;
uniform float levels = 4.0;
uniform float alpha_max = 0.8;
uniform float strip_alpha_max = 0.62;
uniform vec2 front_share = vec2(0.32, 0.56);
uniform float opacity_scale = 1.0;
// Wind-stretched wisps (one value noise per pixel); off on LOW quality.
uniform bool detail = true;
// Banks: a 1D noise along x makes the blanket denser and thinner across the level.
uniform float bank_scale = 0.00025;
uniform float bank_min = 0.7;
uniform float bank_speed = 0.004;
uniform vec2 wisp_scale = vec2(0.0011, 0.016);
uniform float wisp_amount = 0.35;
uniform float wisp_speed = 1.0;
// Cool sky blues with a hint of swamp green; blended by interpolation, so the fog lightens and
// desaturates what is behind it.
uniform float swamp_tint = 0.12;
uniform vec4 color_light : source_color = vec4(0.965, 0.980, 1.0, 1.0);
uniform vec4 color_deep : source_color = vec4(0.596, 0.678, 0.761, 1.0);
uniform vec4 color_front : source_color = vec4(0.549, 0.631, 0.718, 1.0);
uniform vec4 color_swamp : source_color = vec4(0.678, 0.718, 0.682, 1.0);

varying vec2 world;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(vec2(i, 3.7)), hash(vec2(i + 1.0, 3.7)), f * f * (3.0 - 2.0 * f));
}

// Quantized ramp: level in 0..levels, ordered-dithered between neighbours by the Bayer rank.
// Linear from ramp_lo to ramp_hi, so thin fog already shows; ramp_gamma bends it (below 1 it
// rises fast and then saturates, above 1 it holds back the thin fog).
float ramp_level(float v, float rank) {
	float g = clamp((v - ramp_lo) / (ramp_hi - ramp_lo), 0.0, 1.0);
	g = mix(g, g * g, ramp_gamma - 1.0);
	return min(floor(g * levels + rank), levels) / levels;
}

float solid_at(vec2 p) {
	vec2 suv = (p - solid_origin) / solid_size;
	if (suv.x < 0.0 || suv.y < 0.0 || suv.x > 1.0 || suv.y > 1.0) {
		return 0.0;
	}
	return texture(solid_tex, suv).r;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 ap = floor(world / art);
	vec2 wc = (ap + 0.5) * art;
	// Front layer: the fog runs down into a solid below open air, so its base is never a straight
	// cut at the surface. Ground (mask value ~0.6, grass or dirt) is drawn in front of the fog with
	// an irregular edge, so the fog sinks ground_sink_px art pixels at full strength behind it;
	// other solids (stone) get stone_sink_px pixels of dithered fade. Deeper texels are clipped.
	float fade = 1.0;
	if (front) {
		float s0 = solid_at(wc);
		if (s0 > 0.3) {
			bool ground = s0 < 0.8;
			int depth = ground ? ground_sink_px : stone_sink_px;
			fade = 0.0;
			for (int k = 1; k <= 8; k++) {
				if (k > depth) {
					break;
				}
				vec2 up = wc - vec2(0.0, float(k) * art);
				if (solid_at(up) < 0.3) {
					wc = up;
					fade = ground ? 1.0 : 1.0 - float(k) / float(depth + 1);
					break;
				}
			}
			if (fade <= 0.0) {
				discard;
			}
		}
	}
	float d = texture(sim_tex, (wc - sim_origin) / sim_world_size).r;
	if (front) {
		// The air cells touching the floor lose a little fog to the bilinear reads of the solid;
		// the strip takes the denser of its texel and the one two art pixels up.
		d = max(d, texture(sim_tex, (wc - vec2(0.0, 2.0 * art) - sim_origin) / sim_world_size).r);
	}
	// The front layer reads the Bayer matrix shifted by two pixels, so the level borders of the
	// two layers do not line up and the fog gets volume.
	vec2 bp = front ? ap + vec2(2.0, 2.0) : ap;
	int bi = int(mod(bp.x, 4.0)) + int(mod(bp.y, 4.0)) * 4;
	float rank = (BAYER[bi] + 0.5) / 16.0;

	// Large banks and wind-stretched wisps shape the visible density; the simulation is untouched.
	float bank = mix(bank_min, 1.0, noise1(wc.x * bank_scale + time * bank_speed));
	float dv = d * bank;
	if (detail) {
		float wisp = vnoise((wc - wind * time * wisp_speed) * wisp_scale);
		float edge = 1.0 - smoothstep(0.35, 0.9, d);
		dv *= 1.0 + (wisp - 0.5) * 2.0 * wisp_amount * edge;
	}
	float k = ramp_level(dv, rank);
	float total = min(k * alpha_max * opacity_scale, 0.95);
	vec3 col = mix(mix(color_light.rgb, color_deep.rgb, k), color_swamp.rgb, swamp_tint);

	// Simulated depth: a slow drifting noise decides how much of each patch of fog passes in
	// front of the characters; the two layers stack to the level's total alpha.
	float dn = vnoise((wc - wind * time * 0.8) * vec2(0.0035, 0.006) + vec2(0.0, time * 0.05));
	float share = mix(front_share.x, front_share.y, dn);
	float a_front = total * share;
	float alpha = front ? a_front : 1.0 - (1.0 - total) / max(1.0 - a_front, 0.001);

	if (front) {
		// Strip over the feet and shins, denser than the share; stirred fog lifts it and the
		// drifting noise keeps its top wavy.
		vec2 ruv = (wc - rest_origin) / rest_size;
		vec2 rs = texture(rest_tex, clamp(ruv, 0.0, 1.0)).rg;
		float h = rs.g * rest_h_max;
		vec2 q = (wc - wind * time * 1.4) * vec2(0.0016, 0.0042);
		float n = vnoise(q) * 0.65 + vnoise(q * 2.3 + 7.1) * 0.35;
		float r0 = rs.r * rest_range;
		float rest = r0 * mix(0.92 + 0.16 * n, 0.55 + 0.9 * n, smoothstep(0.95, 0.35, r0)) * density_scale;
		float lift = 260.0 * clamp((d - rest) / 0.5, 0.0, 1.0) + (n - 0.5) * 44.0;
		float knee = 1.0 - smoothstep(knee_lo, knee_hi, h - lift);
		float ks = ramp_level(d * knee * bank, rank);
		float strip = min(ks * strip_alpha_max * opacity_scale, 0.95);
		if (strip > alpha) {
			alpha = strip;
			col = mix(color_front.rgb, color_swamp.rgb, swamp_tint);
		}
		// Below a stone surface the fog fades out by dithering, not by a softer alpha.
		if (rank > fade) { alpha = 0.0; }
	}
	if (alpha <= 0.004) {
		discard;
	}
	COLOR = vec4(col, alpha);
}
