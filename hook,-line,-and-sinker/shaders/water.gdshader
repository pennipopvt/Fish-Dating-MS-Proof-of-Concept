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

	// Vertically squished, wobbly reflection.
	float vertical_wave = sin(
		depth * 0.65 + TIME * 1.4
	) * 1.5;

	vertical_wave += sin(
		depth * 1.3 - TIME * 0.9
	) * 0.7;

	float reflected_y = waterline_y
		- depth * reflection_squish
		+ round(vertical_wave);

	// Horizontal reflection distortion.
	float wave = sin(
		depth * 0.42 + TIME * ripple_speed * 3.0
	);

	wave += 0.5 * sin(
		depth * 0.9 - TIME * ripple_speed * 2.0
	);

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
		reflection_strength
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
		* highlight_intensity;

	final_color = mix(
		final_color,
		highlight_color.rgb,
		highlight
	);

	COLOR = vec4(final_color, 1.0);
}