shader_type canvas_item;
// Rig parts: flash / tint fill the silhouette (opaque pixels only). COLOR already carries the
// texture color here.

uniform vec4 fill_color : source_color = vec4(1.0);
uniform float fill_amount = 0.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, fill_color.rgb, fill_amount);
}
