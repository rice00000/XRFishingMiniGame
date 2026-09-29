// Clear tropical water. Cheap enough for standalone VR: no screen or depth texture.
// The turquoise shallows come from the seabed shader showing through; this surface
// adds tint, sky reflection at grazing angles, small waves and sun glints.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform vec3 near_color : source_color = vec3(0.35, 0.85, 0.85);
uniform vec3 far_color : source_color = vec3(0.05, 0.35, 0.6);
uniform vec3 horizon_color : source_color = vec3(0.6, 0.8, 0.95);
// Opacity looking straight down; grazing angles and distance go fully opaque.
uniform float clarity : hint_range(0.0, 1.0) = 0.35;
uniform float far_distance = 45.0;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
uniform float wave_height = 0.025;
uniform float flow_speed = 0.03;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(world_pos.x * 0.9 + TIME * 1.2) + sin(world_pos.z * 1.3 - TIME * 0.8);
	VERTEX.y += w * 0.5 * wave_height;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec3 n1 = texture(normal_a, uv * 0.11 + TIME * vec2(flow_speed, flow_speed * 0.4)).rgb;
	vec3 n2 = texture(normal_b, uv * 0.07 - TIME * vec2(flow_speed * 0.6, flow_speed * 0.9)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	float farness = smoothstep(3.0, far_distance, length(world_pos - CAMERA_POSITION_WORLD));
	vec3 water = mix(near_color, far_color, farness);
	ALBEDO = mix(water, horizon_color, fresnel * 0.7);
	ALPHA = clamp(mix(clarity, 1.0, max(fresnel, farness)), 0.0, 1.0);
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
}
