shader_type canvas_item;

// Visual-only mask on the underwater Solids TileMapLayer. Do NOT remove or
// move painted tiles: their collision geometry remains intact. WorldDayNight
// sets this from World/Water's actual world-space top edge.
uniform float surface_world_y = 140.0;
varying float pixel_world_y;

void vertex() {
	pixel_world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	if (pixel_world_y < surface_world_y) {
		discard;
	}
}
