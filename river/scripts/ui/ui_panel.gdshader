shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Flat rounded rectangle with a thin border, for every UI panel, button and card.
// Put it on a QuadMesh; `size` is the quad's size in metres.

uniform vec2 size = vec2(1.0, 1.0);
uniform float radius = 0.06;
uniform vec4 fill : source_color = vec4(0.05, 0.16, 0.22, 1.0);
uniform vec4 border : source_color = vec4(0.95, 0.85, 0.66, 1.0);
uniform float border_width = 0.012;

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = abs(p) - size * 0.5 + vec2(radius);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float aa = max(fwidth(d), 0.0005);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float edge = smoothstep(-border_width - aa, -border_width + aa, d);
	vec4 color = mix(fill, border, edge * border.a);
	ALBEDO = color.rgb;
	ALPHA = color.a * inside;
}
