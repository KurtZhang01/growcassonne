shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 shallow_color : source_color = vec3(0.14, 0.50, 0.65);
uniform vec3 deep_color : source_color = vec3(0.04, 0.22, 0.38);

void fragment() {
	float wave_a = sin(UV.x * 24.0 + UV.y * 9.0 + TIME * 1.15);
	float wave_b = sin(UV.y * 31.0 - UV.x * 7.0 - TIME * 0.82);
	float wave = wave_a * 0.5 + wave_b * 0.5;
	float soft_depth = smoothstep(0.0, 0.72, distance(UV, vec2(0.5)) * 1.42);
	ALBEDO = mix(deep_color, shallow_color, soft_depth + wave * 0.055);
	ROUGHNESS = 0.28 + wave * 0.025;
	METALLIC = 0.08;
	SPECULAR = 0.52;
	EMISSION = shallow_color * max(wave, 0.0) * 0.018;
}
