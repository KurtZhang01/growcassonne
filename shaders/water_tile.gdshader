shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 shallow_color : source_color = vec3(0.18, 0.62, 0.78);
uniform vec3 deep_color : source_color = vec3(0.05, 0.28, 0.48);

void fragment() {
	float wave_a = sin(UV.x * 24.0 + UV.y * 9.0 + TIME * 1.15);
	float wave_b = sin(UV.y * 31.0 - UV.x * 7.0 - TIME * 0.82);
	float wave = wave_a * 0.5 + wave_b * 0.5;
	float soft_depth = smoothstep(0.0, 0.72, distance(UV, vec2(0.5)) * 1.42);
	ALBEDO = mix(deep_color, shallow_color, soft_depth + wave * 0.055);
	ROUGHNESS = 0.18 + wave * 0.035;
	METALLIC = 0.16;
	SPECULAR = 0.78;
	EMISSION = shallow_color * max(wave, 0.0) * 0.045;
}
