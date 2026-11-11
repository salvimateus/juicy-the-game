shader_type canvas_item;
// FX particles: each MultiMesh instance samples its atlas region (custom data: uv offset, uv size).

void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}
