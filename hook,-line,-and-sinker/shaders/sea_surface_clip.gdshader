shader_type canvas_item;

// Only underwater visuals use this material. Clip their fragments before
// the World/Water screen-texture pass so they cannot appear in the sky or
// contaminate its reflected image. Physics remains unaffected.
//
// FRAGCOORD is in the same 320x180 viewport pixel space as Water's
// waterline_y. Unlike tile-vertex world positions, it remains accurate
// when the TileMapLayer is batched, repainted, or the camera moves.
uniform float surface_screen_y = 140.0;

void fragment() {
	if (FRAGCOORD.y < surface_screen_y) {
		discard;
	}
}
