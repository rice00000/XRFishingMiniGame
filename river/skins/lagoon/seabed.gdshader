// Beach + seabed on one flat, subdivided plane. The shoreline runs along X at about
// z = shore_z (in this node's space): dry sand on the +Z side where the player stands,
// sloping down under the water on the -Z side, with moving caustic light.
shader_type spatial;
render_mode cull_back;

uniform vec3 dry_sand : source_color = vec3(0.84, 0.76, 0.58);
uniform vec3 wet_sand : source_color = vec3(0.62, 0.53, 0.38);
uniform vec3 shallow_tint : source_color = vec3(0.35, 0.95, 0.85);
uniform vec3 deep_tint : source_color = vec3(0.02, 0.28, 0.5);
uniform float shore_z = -2.3;
uniform float slope = 0.8;
uniform float max_depth = 2.2;
uniform float caustic_strength = 0.45;
uniform float caustic_scale = 1.3;

varying float height;
varying vec2 ground_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float ground_height(vec2 p) {
	float shore = shore_z + sin(p.x * 0.31) * 0.5 + sin(p.x * 0.83 + 1.7) * 0.2;
	float bumps = (noise(p * 0.6) - 0.5) * 0.12 + (noise(p * 2.3) - 0.5) * 0.03;
	float below = -min((shore - p.y) * slope, max_depth);
	float above = min((p.y - shore) * 0.03, 0.05);
	return (p.y < shore ? below : above) + bumps;
}

// Thin bright lines where three drifting wave patterns cancel out.
float caustics(vec2 p, float t) {
	vec2 q = p * caustic_scale;
	float a = sin(q.x + sin(q.y * 1.3 + t) * 1.2 + t * 0.7);
	float b = sin(q.y * 1.1 + sin(q.x * 0.9 - t * 0.8) * 1.4 - t * 0.5);
	float c = sin((q.x + q.y) * 0.8 + sin(q.x * 1.7 + t) - t * 0.6);
	return pow(1.0 - abs(a + b + c) / 3.0, 7.0);
}

void vertex() {
	vec2 p = VERTEX.xz;
	height = ground_height(p);
	float e = 0.1;
	float hx = ground_height(p + vec2(e, 0.0));
	float hz = ground_height(p + vec2(0.0, e));
	VERTEX.y += height;
	NORMAL = normalize(vec3(height - hx, e, height - hz));
	ground_xz = p;
}

void fragment() {
	float depth = -height;
	vec3 sand = mix(dry_sand, wet_sand, smoothstep(0.05, -0.02, height));
	sand *= 0.92 + 0.16 * noise(ground_xz * 7.0);
	vec3 col = mix(sand, sand * shallow_tint * 1.1, smoothstep(0.0, 0.5, depth));
	col = mix(col, deep_tint, smoothstep(0.4, max_depth, depth));
	float under = smoothstep(0.02, 0.2, depth) * (1.0 - smoothstep(1.2, max_depth, depth));
	col += vec3(0.9, 1.0, 0.95) * caustics(ground_xz, TIME * 1.1) * caustic_strength * under;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
