shader_type canvas_item;
// Hair: the rig part fill (flash / tint) plus a bend in whole art pixels. The root stays on the
// scalp and the displacement grows toward the tips. The hair bone pose bends the hair (rotation and
// offset relative to the head); a breeze with irregular gusts runs on TIME on top.

uniform vec4 fill_color : source_color = vec4(1.0);
uniform float fill_amount = 0.0;
// Atlas texel rect of the (padded) hair image.
uniform vec4 region = vec4(0.0);
// Scalp point, in art pixels from the region origin.
uniform vec2 root = vec2(0.0);
uniform float art_pixel = 6.0;
// Hair bone relative to the head: rotation (rad), offset x and y (art pixels).
uniform vec3 bend = vec3(0.0);
// Distance from the root (art pixels) where the motion reaches full strength.
uniform float reach = 15.0;
// Breeze push at the tips, in art pixels.
uniform float breeze = 1.6;
uniform vec2 breeze_dir = vec2(-1.0, 0.35);
uniform float seed = 0.0;
uniform float front_weight = 0.3;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

float gusts(float t) {
	float g = sin(t * 0.73) + 0.7 * sin(t * 1.91 + 1.3) + 0.8 * sin(t * 0.29 + 4.0);
	return smoothstep(0.8, 2.1, g);
}

void fragment() {
	vec2 texel = UV / TEXTURE_PIXEL_SIZE - region.xy;
	vec2 cell = floor(texel / art_pixel);
	vec2 sub = texel - cell * art_pixel;
	vec2 v = cell + 0.5 - root;
	float dist = length(v);
	// The bangs over the face move less than the hair behind and above the scalp.
	float w = smoothstep(2.0, reach, dist) * mix(front_weight, 1.0, 1.0 - smoothstep(-3.0, 2.0, v.x));
	float c = cos(bend.x);
	float s = sin(bend.x);
	vec2 d = (vec2(c * v.x - s * v.y, s * v.x + c * v.y) - v + bend.yz) * w;
	// The tips lag the root, so a gust travels down the hair.
	float t = TIME + seed - dist * 0.09;
	float sway = 0.3 + 0.22 * sin(t * 1.6) + 0.12 * sin(t * 3.3 + 0.6) + 0.9 * gusts(t);
	d += breeze_dir * sway * breeze * w * w;
	vec2 src = cell - round(d);
	vec2 size = region.zw / art_pixel;
	vec4 col = vec4(0.0);
	if (all(greaterThanEqual(src, vec2(0.0))) && all(lessThan(src, size))) {
		col = texture(TEXTURE, (region.xy + src * art_pixel + sub) * TEXTURE_PIXEL_SIZE) * tint;
	}
	col.rgb = mix(col.rgb, fill_color.rgb, fill_amount);
	COLOR = col;
}
