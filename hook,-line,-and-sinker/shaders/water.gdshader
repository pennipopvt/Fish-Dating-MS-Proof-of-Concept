shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform vec4 water_color : source_color = vec4(0.12, 0.32, 0.48, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.75, 0.9, 1.0, 1.0);

uniform float reflection_strength : hint_range(0.0, 1.0) = 0.55;
uniform float reflection_squish : hint_range(0.25, 4.0) = 2.0;

uniform float ripple_strength : hint_range(0.0, 8.0) = 2.0;
uniform float ripple_speed : hint_range(0.0, 5.0) = 0.6;

uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.45;
uniform float highlight_density : hint_range(0.0, 1.0) = 0.25;
uniform float highlight_speed : hint_range(0.0, 5.0) = 0.5;

uniform float waterline_y = 140.0;
// Viewer submersion is computed once by WorldDayNight from Penni's
// world-space depth. Unlike the old per-pixel fade, an observer standing
// on shore sees an OPAQUE surface at every depth.
uniform float viewer_submersion : hint_range(0.0, 1.0) = 0.0;
// Reflected detail can fade naturally as the sampled surface extends
// away from the shore, without making underwater terrain visible.
uniform float reflection_fade_depth : hint_range(4.0, 160.0) = 64.0;
// Additional blue tint on top of the underlying sea when submerged;
// UnderwaterTint already contributes a separate screen-space blue haze.
uniform float deep_water_alpha : hint_range(0.0, 1.0) = 0.18;


// Stable random number for each pixel-grid cell.
float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}


void fragment() {
	vec2 pixel_size = SCREEN_PIXEL_SIZE;
	vec2 screen_pixel = SCREEN_UV / pixel_size;

	float depth = max(screen_pixel.y - waterline_y, 0.0);
	float reflection_falloff = smoothstep(0.0, max(reflection_fade_depth, 1.0), depth);

	// Preserve the order of reflected rows: never add independent vertical
	// waves that can make foreground/sky stripes cross over each other.
	// Positive squish keeps the mirrored image monotonically ordered.
	float reflected_y = waterline_y - depth * max(reflection_squish, 0.01);

	// Ripples travel perpendicular to the shore (along depth), both inward
	// and outward. They shift the reflection sideways without folding its Y.
	float inward = sin(depth * 0.42 - TIME * ripple_speed * 3.0);
	float outward = sin(depth * 0.9 + TIME * ripple_speed * 2.0);
	float wave = inward + 0.5 * outward;
	float offset = round(wave * ripple_strength);

	vec2 sample_pixel = vec2(
		screen_pixel.x + offset,
		reflected_y
	);

	sample_pixel = floor(sample_pixel) + vec2(0.5);

	vec2 sample_uv = clamp(
		sample_pixel * pixel_size,
		pixel_size * 0.5,
		vec2(1.0) - pixel_size * 0.5
	);

	vec3 reflection = textureLod(
		screen_texture,
		sample_uv,
		0.0
	).rgb;

	vec3 final_color = mix(
		water_color.rgb,
		reflection,
		reflection_strength * (1.0 - reflection_falloff)
	);

	// Small horizontal glints, grouped into 8x3-pixel cells.
	vec2 cell_size = vec2(8.0, 3.0);
	vec2 cell = floor(screen_pixel / cell_size);
	vec2 local_pixel = mod(floor(screen_pixel), cell_size);

	// Offset the pattern by row so it looks less regular.
	cell.x += floor(mod(cell.y, 3.0)) * 0.37;

	float random_value = hash(cell);

	// Animate the visibility of each glint.
	float shimmer = sin(
		TIME * highlight_speed * 3.0
		+ random_value * 6.28318
	);

	shimmer = smoothstep(0.25, 0.95, shimmer);

	// A short horizontal line, 3 pixels wide and 1 pixel tall.
	float glint_shape =
		(1.0 - step(3.0, local_pixel.x))
		* (1.0 - step(1.0, local_pixel.y));

	float glint_exists = step(
		1.0 - highlight_density,
		random_value
	);

	float highlight = glint_shape
		* glint_exists
		* shimmer
		* highlight_intensity * (1.0 - viewer_submersion) * (1.0 - reflection_falloff);

	final_color = mix(
		final_color,
		highlight_color.rgb,
		highlight
	);

	// Above water: opaque reflective surface hiding every sea tile.
	// Underwater: translucent non-reflective blue, revealing sea and actors.
	// Do not derive opacity from pixel depth; that exposed the seabed from land.
	COLOR = vec4(final_color, mix(1.0, deep_water_alpha, viewer_submersion));
}