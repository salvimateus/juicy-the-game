shader_type canvas_item;
render_mode blend_disabled, unshaded;

// One simulation step of the fog, drawn over the whole sim SubViewport, which keeps its previous
// frame (clear mode never) and reads it back through the screen texture.
// State per texel (RGBA half float): R density, GB velocity (units/s), A curl of the last step.

#define MAX_IMPULSES 64

uniform sampler2D prev_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D solid_tex : filter_nearest, repeat_disable;
uniform sampler2D rest_tex : filter_linear, repeat_disable;
uniform vec2 solid_origin;
uniform vec2 solid_size;      // world size of the mask
uniform vec2 rest_origin;
uniform vec2 rest_size;
uniform float rest_range = 1.6;

uniform vec2 origin;          // world position of the grid's top-left corner
uniform vec2 grid;            // texels
uniform float cell;
uniform vec2 shift;           // texels the grid moved since the last step
uniform float dt;
uniform float time;
uniform bool reset;
uniform vec2 wind = vec2(18.0, 0.0);
uniform float density_scale = 1.0;
uniform float damping = 1.5;
uniform float relax_time = 1.4;   // refill of thinned fog
uniform float settle_time = 3.2;  // return of lifted fog
uniform float diffusion = 1.5;
uniform float vorticity = 0.9;
uniform float turbulence = 0.9;
uniform float settle = 60.0;
uniform float lift = 520.0;

uniform int imp_count = 0;
uniform vec4 imp_a[MAX_IMPULSES];
uniform vec4 imp_b[MAX_IMPULSES];

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

float solid_at(vec2 w) {
	vec2 uv = (w - solid_origin) / solid_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	// The mask stores ground as 0.6 and other solids as 1.0; the simulation treats both as solid.
	return step(0.3, texture(solid_tex, uv).r);
}

// Rest density at a world point, with a slow drifting billow so the fog never sits still.
float rest_at(vec2 w) {
	vec2 q = (w - wind * time * 1.4) * vec2(0.0016, 0.0042);
	float n = vnoise(q) * 0.65 + vnoise(q * 2.3 + 7.1) * 0.35;
	// The drifting noise also shifts the profile up and down, so the top of the blanket waves.
	// Only the upper, thinner part waves; the floor layer stays put.
	vec2 uv0 = (w - rest_origin) / rest_size;
	if (uv0.x < 0.0 || uv0.y < 0.0 || uv0.x > 1.0 || uv0.y > 1.0) {
		return 0.0;
	}
	float r0 = texture(rest_tex, uv0).r * rest_range;
	float wave = (vnoise(vec2((w.x - wind.x * time * 2.0) * 0.0025, time * 0.08)) - 0.5) * 110.0;
	wave *= 1.0 - smoothstep(0.45, 0.9, r0);
	float r = texture(rest_tex, (w + vec2(0.0, wave) - rest_origin) / rest_size).r * rest_range;
	// Billows vary the top of the band a lot and the floor layer little.
	float var_k = smoothstep(0.95, 0.35, r);
	return r * mix(0.92 + 0.16 * n, 0.55 + 0.9 * n, var_k) * density_scale;
}

vec4 rest_state(vec2 w) {
	return vec4(rest_at(w), wind, 0.0);
}

vec4 prev_state(vec2 t) {
	// t: texel coordinates (centre = .5) of the previous grid.
	if (t.x < 0.5 || t.y < 0.5 || t.x > grid.x - 0.5 || t.y > grid.y - 0.5) {
		return rest_state(origin + (t - shift) * cell);
	}
	return texture(prev_tex, t / grid);
}

vec2 curl_noise(vec2 p) {
	float e = 0.5;
	float n1 = vnoise(p + vec2(0.0, e));
	float n2 = vnoise(p - vec2(0.0, e));
	float n3 = vnoise(p + vec2(e, 0.0));
	float n4 = vnoise(p - vec2(e, 0.0));
	return vec2(n1 - n2, -(n3 - n4)) / (2.0 * e);
}

void fragment() {
	vec2 c = SCREEN_UV * grid;
	vec2 w = origin + c * cell;
	if (solid_at(w) > 0.5) {
		// Solid cells hold no fog, so a solid that disappears leaves an empty space the fog
		// flows into instead of popping in.
		COLOR = vec4(0.0);
	} else if (reset) {
		COLOR = rest_state(w);
	} else {
		vec2 pc = c + shift;
		vec4 s0 = prev_state(pc);
		// Semi-Lagrangian advection of density and velocity.
		vec4 s = prev_state(pc - s0.gb * dt / cell);
		float d = s.r;
		vec2 v = s.gb;

		vec4 e = prev_state(pc + vec2(1.0, 0.0));
		vec4 wv = prev_state(pc - vec2(1.0, 0.0));
		vec4 so = prev_state(pc + vec2(0.0, 1.0));
		vec4 no = prev_state(pc - vec2(0.0, 1.0));

		float se = solid_at(w + vec2(cell, 0.0));
		float sw = solid_at(w - vec2(cell, 0.0));
		float ss = solid_at(w + vec2(0.0, cell));
		float sn = solid_at(w - vec2(0.0, cell));

		// Diffusion over the open neighbours only, so walls do not drain the fog next to them.
		float open_n = 4.0 - se - sw - ss - sn;
		float avg = open_n > 0.5 ? (e.r * (1.0 - se) + wv.r * (1.0 - sw) + so.r * (1.0 - ss) + no.r * (1.0 - sn)) / open_n : d;
		d = mix(d, avg, clamp(diffusion * dt, 0.0, 0.5));
		v = mix(v, (e.gb + wv.gb + so.gb + no.gb) * 0.25, clamp(diffusion * 0.6 * dt, 0.0, 0.5));

		// Vorticity confinement: amplify the swirls the pushes create.
		float curl = ((e.b - wv.b) - (so.g - no.g)) / (2.0 * cell);
		vec2 grad = vec2(abs(e.a) - abs(wv.a), abs(so.a) - abs(no.a));
		float gl = length(grad);
		if (gl > 1e-5) {
			vec2 nrm = grad / gl;
			v += vorticity * cell * vec2(nrm.y, -nrm.x) * s0.a * dt * 25.0;
		}

		// Turbulence where the fog is stirred, plus a slow wandering wind.
		vec2 stir = v - wind;
		float stirred = length(stir);
		vec2 tn = curl_noise(w * 0.012 + vec2(time * 0.35, -time * 0.21));
		v += tn * stirred * turbulence * 3.0 * dt;
		float gust = vnoise(vec2(w.x * 0.0007 - time * 0.05, time * 0.03));
		vec2 local_wind = wind * (0.55 + 0.9 * gust) + vec2(0.0, 6.0 * sin(time * 0.4 + w.x * 0.002));

		float rest = rest_at(w);
		// Stirred fog rises in volutes; once calm, fog lifted above its rest settles back down.
		float stir_k = clamp(stirred / 350.0, 0.0, 1.0);
		if (d > 0.04) {
			v.y -= lift * stir_k * dt;
		}
		v.y += settle * max(d - rest, 0.0) * (1.0 - stir_k) * dt;

		for (int k = 0; k < MAX_IMPULSES; k++) {
			if (k >= imp_count) {
				break;
			}
			vec4 a = imp_a[k];
			vec4 b = imp_b[k];
			int type = int(b.w + 0.5);
			if (type == 2) {
				// Line: a thin tunnel with outward flow and eddies on its edges.
				vec2 ab = a.zw - a.xy;
				float len2 = max(dot(ab, ab), 1.0);
				float t = clamp(dot(w - a.xy, ab) / len2, 0.0, 1.0);
				vec2 cp = a.xy + ab * t;
				vec2 rel = w - cp;
				float dist = length(rel);
				float width = b.x;
				if (dist < width * 3.0) {
					vec2 dir = ab / sqrt(len2);
					vec2 nrm = vec2(-dir.y, dir.x);
					float side = sign(dot(rel, nrm));
					float core = 1.0 - smoothstep(width * 0.4, width, dist);
					float ring = smoothstep(width * 3.0, width, dist) * (1.0 - core * 0.6);
					d *= 1.0 - 0.95 * core * min(b.y, 1.0);
					v += nrm * side * 170.0 * b.y * ring;
					v += dir * 260.0 * b.y * core;
					float along = dot(w - a.xy, dir);
					v += dir * side * sin(along / (width * 3.5) + b.z) * 220.0 * b.y * ring;
				}
			} else if (type == 5) {
				// Sweep: a body rolling along a segment ploughs a wide furrow, throwing the fog
				// sideways and up into large curls. Meant to be called once per physics frame of the move.
				vec2 ab = a.zw - a.xy;
				float len2 = max(dot(ab, ab), 1.0);
				float t = clamp(dot(w - a.xy, ab) / len2, 0.0, 1.0);
				vec2 rel = w - (a.xy + ab * t);
				float dist = length(rel);
				float r = b.x;
				if (dist < r * 1.8) {
					vec2 dir = ab / sqrt(len2);
					vec2 away = dist > 0.001 ? rel / dist : vec2(0.0, -1.0);
					float core = 1.0 - smoothstep(r * 0.35, r, dist);
					float ring = smoothstep(r * 1.8, r * 0.6, dist) * (1.0 - core * 0.5);
					d *= 1.0 - 0.35 * core * min(b.y, 1.0);
					v += away * 260.0 * b.y * ring;
					v.y -= 230.0 * b.y * ring;
					v += dir * 160.0 * b.y * core;
					float along = dot(w - a.xy, dir);
					v += vec2(-dir.y, dir.x) * sin(along / (r * 0.9) + b.z) * 160.0 * b.y * ring;
				}
			} else if (type == 6) {
				// Swirl: a vortex where a body left (dodge).
				vec2 rel = w - a.xy;
				float dist = length(rel);
				float r = b.x;
				if (dist < r) {
					float f = 1.0 - dist / r;
					float ring = f * (1.0 - f) * 4.0;
					v += vec2(-rel.y, rel.x) / max(dist, 1.0) * 900.0 * b.y * ring;
					v.y -= 200.0 * b.y * ring;
					d *= 1.0 - 0.3 * f * f * min(abs(b.y), 1.0);
				}
			} else {
				vec2 rel = w - a.xy;
				float dist = length(rel);
				float r = b.x;
				if (dist < r) {
					float f = 1.0 - dist / r;
					float wgt = f * f * (3.0 - 2.0 * f);
					vec2 dirn = dist > 0.001 ? rel / dist : vec2(0.0, -1.0);
					if (type == 0) {
						// Push: carry the fog along, with counter-rotating eddies on the flanks.
						vec2 pv = a.zw * b.y;
						float sp = length(pv);
						v += pv * wgt * 0.9;
						if (sp > 1.0) {
							vec2 pd = pv / sp;
							vec2 perp = vec2(-pd.y, pd.x);
							float side = sign(dot(rel, perp));
							float flank = wgt * (1.0 - wgt) * 4.0;
							v += perp * side * sp * 0.45 * flank;
							v -= pd * sp * 0.25 * flank * abs(dot(dirn, perp));
						}
						d *= 1.0 - 0.35 * wgt * min(b.y, 1.0);
					} else if (type == 1) {
						// Burst: radial blast that rolls up into curls at its front.
						float ring = wgt * (1.0 - wgt) * 4.0;
						v += dirn * 1100.0 * b.y * (wgt * 0.5 + ring);
						v.y -= 230.0 * b.y * ring * abs(dirn.x);
						v += vec2(-dirn.y, dirn.x) * sign(dirn.x) * 260.0 * b.y * ring;
						d *= 1.0 - 0.8 * wgt * min(b.y, 1.0);
					} else if (type == 3) {
						d += b.y * wgt;
						v += dirn * 160.0 * wgt;
					} else if (type == 4) {
						// Body: continuously drags the fog along, parts it and sheds a wake.
						float k = 1.0 - exp(-9.0 * dt * wgt);
						v = mix(v, a.zw * 0.85, k);
						float sp = length(a.zw);
						if (sp > 20.0) {
							vec2 pd = a.zw / sp;
							vec2 perp = vec2(-pd.y, pd.x);
							float side = sign(dot(rel, perp));
							float flank = wgt * (1.0 - wgt) * 4.0;
							v += perp * side * sp * (0.9 + 0.6 * sin(time * 9.0 + b.z)) * flank * dt * 12.0;
							d *= 1.0 - (1.0 - exp(-8.0 * dt)) * wgt * min(sp / 300.0, 1.0);
							// The wake behind a moving body rises a little.
							if (dot(rel, pd) < 0.0) {
								v.y -= min(sp, 900.0) * 0.6 * wgt * dt * 10.0;
							}
						}
					}
				}
			}
		}

		// Damping toward the wind and slow return to the rest profile.
		v = mix(v, local_wind, 1.0 - exp(-damping * dt));
		float tau = d < rest ? relax_time : settle_time;
		d = mix(d, rest, 1.0 - exp(-dt / tau));

		// Walls: no flow into solid neighbours.
		if (se > 0.5) { v.x = min(v.x, 0.0); }
		if (sw > 0.5) { v.x = max(v.x, 0.0); }
		if (ss > 0.5) { v.y = min(v.y, 0.0); }
		if (sn > 0.5) { v.y = max(v.y, 0.0); }

		float vmax = 2400.0;
		float vl = length(v);
		if (vl > vmax) {
			v *= vmax / vl;
		}
		COLOR = vec4(clamp(d, 0.0, 2.5), v, curl);
	}
}
