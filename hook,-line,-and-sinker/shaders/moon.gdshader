shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float visibility : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // A full moon makes sense for our simplified night: it rises near
    // sunset and sets near sunrise. Preserve crisp 1-pixel-edged artwork.
    vec2 p = floor(UV * 24.0) + 0.5;
    float disc = 1.0 - step(10.4, length(p - vec2(12.0)));

    // Subtle fixed crater patches, without smoothing away pixel edges.
    float crater_a = 1.0 - step(2.8, length(p - vec2(8.0, 8.0)));
    float crater_b = 1.0 - step(1.8, length(p - vec2(15.0, 15.0)));
    float crater_c = 1.0 - step(1.5, length(p - vec2(16.0, 7.0)));
    float crater = max(crater_a * 0.22, max(crater_b * 0.15, crater_c * 0.18));

    vec3 color = vec3(0.92, 0.95, 1.0) * (1.0 - crater);
    COLOR = vec4(color, disc * visibility);
}
