
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color =
    vec4(1.0, 0.68, 0.24, 1.0);

uniform float intensity : hint_range(0.0, 2.0) = 0.65;
uniform float falloff : hint_range(1.0, 8.0) = 3.0;

void fragment() {
    vec2 center = UV - vec2(0.5);
    float dist = length(center) * 2.0;

    float glow = exp(-dist * dist * falloff);
    glow *= 1.0 - smoothstep(0.2, 1.0, dist);

    COLOR = vec4(
        glow_color.rgb,
        glow * intensity
    );
}
