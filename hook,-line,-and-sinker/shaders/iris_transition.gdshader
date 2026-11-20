shader_type canvas_item;
render_mode unshaded;

// Circular iris: opaque black outside the circle, transparent inside.
// UV is aspect corrected so the opening remains round at any window size.
uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float radius = 2.5;
uniform float aspect_ratio = 1.7777778;

void fragment() {
	vec2 offset = UV - center_uv;
	offset.x *= aspect_ratio;
	float d = length(offset);
	float softness = 0.005;
	float darkness = smoothstep(radius - softness, radius + softness, d);
	COLOR = vec4(0.0, 0.0, 0.0, darkness);
}
