shader_type canvas_item;
render_mode unshaded, blend_mix;

// 1-pixel stars on the 320x180 in-game pixel grid. No external sprite needed.
uniform float visibility : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 pixel = floor(UV * vec2(320.0, 180.0));
    vec2 cell = floor(pixel / 10.0);
    vec2 local = mod(pixel, 10.0);
    float chance = hash21(cell);
    vec2 point = floor(vec2(hash21(cell + 13.7), hash21(cell + 47.3)) * 10.0);
    float dot_pixel = (1.0 - step(0.5, abs(local.x - point.x)))
                    * (1.0 - step(0.5, abs(local.y - point.y)));
    float star = step(0.86, chance) * dot_pixel;
    float twinkle = 0.85 + 0.15 * sin(TIME * 0.9 + chance * 15.0);
    vec3 tint = mix(vec3(0.61, 0.75, 1.0), vec3(1.0, 0.96, 0.80), hash21(cell + 8.0));
    COLOR = vec4(tint, star * twinkle * visibility);
}
