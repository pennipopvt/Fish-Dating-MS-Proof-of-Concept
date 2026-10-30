
shader_type canvas_item;
render_mode unshaded;

uniform vec4 top_color : source_color =
    vec4(0.24, 0.41, 0.69, 1.0);

uniform vec4 horizon_color : source_color =
    vec4(0.86, 0.68, 0.55, 1.0);

void fragment() {
    float t = smoothstep(0.0, 1.0, UV.y);
    vec3 sky = mix(
        top_color.rgb,
        horizon_color.rgb,
        t
    );

    COLOR = vec4(sky, 1.0);
}
