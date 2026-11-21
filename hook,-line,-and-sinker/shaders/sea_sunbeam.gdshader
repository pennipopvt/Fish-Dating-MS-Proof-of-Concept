shader_type canvas_item;
render_mode unshaded, blend_add;

// World-space, additive, softly feathered sunlight. No 2D light nodes,
// occlusion textures, collisions or camera-dependent rendering.
uniform vec4 beam_color : source_color = vec4(0.78, 0.93, 1.0, 1.0);
uniform vec4 daylight_color : source_color = vec4(1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.26;
uniform float daylight_strength : hint_range(0.0, 1.0) = 1.0;
uniform float beam_width = 72.0;
uniform float beam_length = 280.0;
uniform float sway_pixels = 2.0;
uniform float sway_speed = 0.5;
uniform float surface_world_y = 140.0;

varying vec2 local_beam_position;
varying vec2 global_beam_position;

void vertex() {
	local_beam_position = VERTEX;
	global_beam_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float depth = clamp(local_beam_position.y / max(beam_length, 1.0), 0.0, 1.0);
	float half_width = beam_width * mix(0.30, 0.75, depth);
	float drift = sin(TIME * sway_speed + depth * 4.0) * sway_pixels;
	float horizontal = abs((local_beam_position.x - drift) / max(half_width, 1.0));
	float soft_side = 1.0 - smoothstep(0.12, 0.94, horizontal);
	float soft_top = smoothstep(0.0, 0.06, depth);
	float soft_bottom = 1.0 - smoothstep(0.55, 1.0, depth);
	float water_only = smoothstep(surface_world_y - 1.0, surface_world_y + 3.0,
			global_beam_position.y);
	float alpha = strength * daylight_strength * soft_side * soft_top
			* soft_bottom * water_only;
	COLOR = vec4(beam_color.rgb * daylight_color.rgb, alpha);
}
