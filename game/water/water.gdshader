shader_type canvas_item;

// Pixel-art water over the WaterBody domain. One texel of col_data per art-pixel column:
// r = surface row, g = bed row (255 = dry), b = foam 0..1, a = flow speed 0..1.
// Every decision is made per art pixel (floor of the grid coordinate), so nothing is smoothed.

uniform sampler2D col_data : filter_nearest, repeat_disable;
uniform vec2 grid = vec2(536.0, 200.0);
// Water-filled passages (orifices) in art pixels: x0, top of water, x1, bottom.
uniform vec4 tunnels[4];
uniform int tunnel_count = 0;
uniform float light_rows = 3.0;
uniform float deep_rows = 24.0;
uniform vec4 c_highlight : source_color = vec4(0.71, 0.9, 0.94, 0.92);
uniform vec4 c_light : source_color = vec4(0.35, 0.7, 0.82, 0.74);
uniform vec4 c_mid : source_color = vec4(0.2, 0.47, 0.62, 0.64);
uniform vec4 c_deep : source_color = vec4(0.13, 0.27, 0.43, 0.7);
uniform vec4 c_foam : source_color = vec4(0.93, 0.97, 1.0, 0.95);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float row_of(float v) {
	return floor(v * 255.0 + 0.5);
}

// Top of the air above column x: its surface when wet, its bed when dry.
float air_top(int x) {
	vec4 d = texelFetch(col_data, ivec2(clamp(x, 0, int(grid.x) - 1), 0), 0);
	float s = row_of(d.r);
	return s < 254.5 ? s : row_of(d.g);
}

vec4 shade(vec2 p, float depth, bool edge, float foam, float speed) {
	float t = floor(TIME * 8.0);
	bool checker = mod(p.x + p.y, 2.0) < 1.0;
	vec4 c;
	if (depth < 0.5 || edge) {
		c = c_highlight;
	} else if (depth < light_rows || (depth < light_rows + 1.0 && checker)) {
		c = c_light;
		// Glints drifting along the surface band.
		if (hash(vec2(floor(p.x - TIME * 5.0), depth)) > 0.94) {
			c = c_highlight;
		}
	} else if (depth < deep_rows || (depth < deep_rows + 2.0 && checker)) {
		c = c_mid;
		if (hash(vec2(floor(p.x * 0.5) + floor(TIME * 1.5) * 7.0, floor(p.y * 0.5))) > 0.988) {
			c = mix(c_mid, c_light, 0.6);
		}
	} else {
		c = c_deep;
	}
	if (speed > 0.12 && depth > 0.5) {
		float streak = hash(vec2(floor((p.x - TIME * (10.0 + speed * 70.0)) / 3.0), p.y));
		if (streak > 1.0 - speed * 0.06) {
			c = mix(c, c_highlight, 0.7);
		}
	}
	if (foam > 0.01 && depth < 1.0 + foam * 5.0) {
		if (hash(vec2(p.x + t * 13.0, p.y - t * 3.0)) < foam * (1.0 - depth * 0.12)) {
			c = c_foam;
		}
	}
	return c;
}

void fragment() {
	vec2 p = floor(UV * grid);
	int x = int(p.x);
	vec4 d = texelFetch(col_data, ivec2(x, 0), 0);
	float surf = row_of(d.r);
	float bed = row_of(d.g);
	vec4 col = vec4(0.0);
	if (surf < 254.5 && p.y >= surf && p.y < bed) {
		bool edge = p.y < air_top(x - 1) || p.y < air_top(x + 1);
		col = shade(p, p.y - surf, edge, d.b, d.a);
	}
	for (int i = 0; i < tunnel_count; i++) {
		vec4 r = tunnels[i];
		if (p.x >= r.x && p.x < r.z && p.y >= r.y && p.y < r.w) {
			col = shade(p, p.y - r.y, false, 0.0, 0.6);
		}
	}
	COLOR = col;
}
