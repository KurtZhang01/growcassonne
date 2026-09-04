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
	vec3 lower = vec3(0.110, 0.340, 0.400);
	vec3 middle = vec3(0.180, 0.500, 0.540);
	vec3 upper = vec3(0.050, 0.200, 0.270);
	vec3 color = mix(lower, middle, smoothstep(0.0, 0.48, height));
	color = mix(color, upper, smoothstep(0.48, 1.0, height));
	float broad_haze = exp(-pow((height - 0.40) * 2.25, 2.0));
	return color + vec3(0.030, 0.065, 0.068) * broad_haze;
}

vec4 moving_clouds(vec3 direction) {
	vec3 slow_wind = vec3(TIME * 0.010, TIME * 0.0015, TIME * -0.006);
	vec3 fast_wind = vec3(TIME * -0.017, TIME * 0.002, TIME * 0.009);
	float broad = cloud_field(direction * 3.15 + slow_wind);
	float wisps = cloud_field(direction * 6.4 + fast_wind);
	float height = direction.y * 0.5 + 0.5;
	float cloud_band = smoothstep(0.02, 0.18, height) * (1.0 - smoothstep(0.78, 0.96, height));
	float density = smoothstep(0.59, 0.76, broad * 0.82 + wisps * 0.18) * cloud_band;
	float soft_edge = smoothstep(0.48, 0.70, broad) * cloud_band;
	float alpha = clamp(density * 0.52 + soft_edge * 0.13, 0.0, 0.54);
	vec3 shadow = vec3(0.27, 0.44, 0.47);
	vec3 pearl = vec3(0.68, 0.80, 0.79);
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
		float atmosphere = value_noise(EYEDIR * 2.2 + vec3(TIME * 0.002, 0.0, 0.0));
		color += vec3(0.012, 0.030, 0.032) * atmosphere;
		COLOR = color;
	}
}
