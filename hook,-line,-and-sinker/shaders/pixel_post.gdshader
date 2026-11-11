shader_type spatial;
// EXPERIMENT (jerry-baitboxtest): full-screen post-process for BaitBox3DView,
// run at the low render resolution so every effect is in whole pixels.
//  - Outline: 1-px ink line on the far side of depth jumps (silhouettes).
//  - Creases: darker line where surface normals turn sharply.
//  - Palette: snap every color to the nearest palette entry (compared in sRGB).
// The quad is drawn over the whole view in the vertex shader.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

uniform bool use_outline = true;
uniform bool use_palette = true;
uniform vec3 outline_color = vec3(0.110, 0.137, 0.094); // sRGB
uniform float depth_threshold = 0.12;   // world units
uniform float normal_threshold = 0.75;  // dot product below this = crease
uniform float crease_darken = 0.72;
uniform vec3 palette[16];               // sRGB
uniform int palette_size = 0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float raw_depth(ivec2 p) {
	return texelFetch(depth_tex, p, 0).r;
}

float linear_depth(ivec2 p, vec2 size, mat4 inv_projection) {
	vec2 uv = (vec2(p) + 0.5) / size;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw_depth(p), 1.0);
	return -view.z / view.w;
}

vec3 view_normal(ivec2 p) {
	return normalize(texelFetch(normal_tex, p, 0).xyz * 2.0 - 1.0);
}

vec3 nearest_palette(vec3 srgb) {
	vec3 best = srgb;
	float best_distance = 1e9;
	for (int i = 0; i < palette_size; i++) {
		vec3 d = (srgb - palette[i]) * vec3(0.30, 0.59, 0.11);
		float distance = dot(d, d);
		if (distance < best_distance) {
			best_distance = distance;
			best = palette[i];
		}
	}
	return best;
}

void fragment() {
	vec2 size = VIEWPORT_SIZE;
	ivec2 p = ivec2(FRAGCOORD.xy);
	ivec2 max_p = ivec2(size) - 1;
	vec4 screen = texelFetch(screen_tex, p, 0);
	bool background = raw_depth(p) <= 0.0000001;  // reversed Z: far plane = 0
	float here = background ? 1e6 : linear_depth(p, size, INV_PROJECTION_MATRIX);

	bool outline = false;
	bool crease = false;
	if (use_outline) {
		ivec2 offsets[4] = { ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1) };
		vec3 n_here = background ? vec3(0.0) : view_normal(p);
		for (int i = 0; i < 4; i++) {
			ivec2 q = clamp(p + offsets[i], ivec2(0), max_p);
			if (raw_depth(q) <= 0.0000001) {
				continue;
			}
			float there = linear_depth(q, size, INV_PROJECTION_MATRIX);
			// Draw on the far pixel only, so lines sit outside the near shape.
			if (there < here - depth_threshold) {
				outline = true;
			} else if (!background && i % 2 == 1 && abs(there - here) < depth_threshold
					&& dot(n_here, view_normal(q)) < normal_threshold) {
				crease = true;  // left/down neighbors only: a 1-px line
			}
		}
	}

	vec3 color = to_srgb(screen.rgb);
	if (crease) {
		color *= crease_darken;
	}
	if (use_palette && palette_size > 0) {
		color = nearest_palette(color);
	}
	if (outline) {
		color = outline_color;
	}
	ALBEDO = to_linear(color);
	ALPHA = (background && !outline) ? 0.0 : 1.0;
}
