shader_type sky;
render_mode use_half_res_pass;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float x00 = mix(hash31(cell), hash31(cell + vec3(1.0, 0.0, 0.0)), local.x);
	float x10 = mix(hash31(cell + vec3(0.0, 1.0, 0.0)), hash31(cell + vec3(1.0, 1.0, 0.0)), local.x);
	float x01 = mix(hash31(cell + vec3(0.0, 0.0, 1.0)), hash31(cell + vec3(1.0, 0.0, 1.0)), local.x);
	float x11 = mix(hash31(cell + vec3(0.0, 1.0, 1.0)), hash31(cell + vec3(1.0, 1.0, 1.0)), local.x);
	return mix(mix(x00, x10, local.y), mix(x01, x11, local.y), local.z);
}

float cloud_field(vec3 p) {
	float field = value_noise(p) * 0.52;
	field += value_noise(p * 2.03 + vec3(4.2, 1.7, -2.8)) * 0.27;
	field += value_noise(p * 4.11 + vec3(-1.4, 3.8, 6.1)) * 0.14;
	field += value_noise(p * 8.17) * 0.07;
	return field;
}

vec3 sky_gradient(vec3 direction) {
	float height = clamp(direction.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 lower = vec3(0.985, 0.992, 1.000);
	vec3 horizon = vec3(0.945, 0.980, 1.000);
	vec3 upper = vec3(0.530, 0.790, 0.940);
	vec3 color = mix(lower, horizon, smoothstep(0.0, 0.46, height));
	color = mix(color, upper, smoothstep(0.46, 1.0, height));
	float broad_haze = exp(-pow((height - 0.38) * 2.65, 2.0));
	return mix(color, vec3(0.995, 0.998, 1.000), broad_haze * 0.34);
}

vec4 moving_clouds(vec3 direction) {
	vec3 slow_wind = vec3(TIME * 0.030, TIME * 0.004, TIME * -0.018);
	vec3 fast_wind = vec3(TIME * -0.052, TIME * 0.006, TIME * 0.028);
	float broad = cloud_field(direction * 3.15 + slow_wind);
	float wisps = cloud_field(direction * 6.4 + fast_wind);
	float height = direction.y * 0.5 + 0.5;
	float cloud_band = smoothstep(0.02, 0.18, height) * (1.0 - smoothstep(0.78, 0.96, height));
	float density = smoothstep(0.67, 0.86, broad * 0.82 + wisps * 0.18) * cloud_band;
	float soft_edge = smoothstep(0.60, 0.80, broad) * cloud_band;
	float alpha = clamp(density * 0.16 + soft_edge * 0.04, 0.0, 0.18);
	vec3 shadow = vec3(0.77, 0.88, 0.96);
	vec3 pearl = vec3(0.99, 1.00, 1.00);
	vec3 color = mix(shadow, pearl, smoothstep(0.50, 0.82, wisps));
	return vec4(color, alpha);
}

void sky() {
	if (AT_HALF_RES_PASS) {
		vec4 clouds = moving_clouds(EYEDIR);
		COLOR = clouds.rgb;
		ALPHA = clouds.a;
	} else {
		vec3 color = sky_gradient(EYEDIR);
		color = mix(color, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
		float atmosphere = value_noise(EYEDIR * 2.2 + vec3(TIME * 0.010, 0.0, 0.0));
		color += vec3(0.010, 0.018, 0.026) * atmosphere;
		COLOR = color;
	}
}
