shader_type canvas_item;

uniform float warning_strength : hint_range(0.0, 1.0) = 0.0;

// Red only around the edges; leave the center clear for targeting fish.
void fragment() {
    vec2 q = abs(UV * 2.0 - 1.0);
    float radius = length(q * vec2(0.9, 1.05));
    float border = smoothstep(0.60, 1.21, radius);
    COLOR = vec4(0.80, 0.07, 0.10, border * warning_strength * 0.76);
}
