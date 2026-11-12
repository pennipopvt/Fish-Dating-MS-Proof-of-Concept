shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float visibility : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // Quantize to scene pixels for a crisp, 24px crescent moon.
    vec2 p = floor(UV * 24.0) + 0.5;
    float disc = 1.0 - step(10.4, length(p - vec2(12.0)));
    float cutout = 1.0 - step(9.3, length(p - vec2(17.0, 8.4)));
    float crescent = disc * (1.0 - cutout);
    COLOR = vec4(0.92, 0.95, 1.0, crescent * visibility);
}
