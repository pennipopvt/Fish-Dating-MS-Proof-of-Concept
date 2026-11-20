shader_type canvas_item;
render_mode unshaded;

// Keep sky above the real waterline visible even when the camera submerges.
uniform vec4 tint_color : source_color = vec4(0.10, 0.36, 0.67, 0.45);
uniform float submersion : hint_range(0.0, 1.0) = 0.0;
uniform float surface_y_uv : hint_range(-3.0, 3.0) = 1.0;

void fragment() {
    float underwater = smoothstep(surface_y_uv - 0.015, surface_y_uv + 0.03, UV.y);
    COLOR = vec4(tint_color.rgb, tint_color.a * submersion * underwater);
}
