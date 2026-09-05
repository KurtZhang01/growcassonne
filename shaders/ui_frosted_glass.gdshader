shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 tint_color : source_color = vec4(0.957, 0.957, 0.933, 0.40);
uniform float blur_lod : hint_range(0.0, 5.0, 0.1) = 3.2;
uniform float blur_radius : hint_range(0.0, 24.0, 0.5) = 12.0;

void fragment() {
	vec2 offset = SCREEN_PIXEL_SIZE * blur_radius;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb * 0.20;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(offset.x, 0.0), blur_lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(offset.x, 0.0), blur_lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(0.0, offset.y), blur_lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(0.0, offset.y), blur_lod).rgb * 0.12;
	blurred += textureLod(screen_texture, SCREEN_UV + offset, blur_lod).rgb * 0.08;
	blurred += textureLod(screen_texture, SCREEN_UV - offset, blur_lod).rgb * 0.08;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(offset.x, -offset.y), blur_lod).rgb * 0.08;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(-offset.x, offset.y), blur_lod).rgb * 0.08;
	vec3 frosted = mix(blurred, tint_color.rgb, tint_color.a);
	COLOR = vec4(frosted, 1.0);
}
