@tool
extends Marker2D
class_name DivingFishSpawn

## Place this marker in the sea to decide where a wild fish starts.
## Pick a FishData resource in the Inspector; its inventory sprite will appear
## as a preview in the editor, but only the actual fish actor exists at runtime.
@export var species: FishData:
	set(value):
		species = value
		queue_redraw()

@export var random_seed: int = 2041
@export_group("Story Placement")
# Assign the opening fish by Inspector data rather than a fragile node name.
# Leave this false for ordinary fish. Only one spawn should be selected.
@export var is_first_dive_fish: bool = false

@export_group("Fish Approach and Flee")
# A fish tries to stay this far from Penni. Zero permits close approaches.
@export_range(0.0, 120.0, 1.0) var preferred_player_distance: float = 48.0
# Fish notice Penni from this far away and begin swimming outward.
@export_range(0.0, 160.0, 1.0) var alert_distance: float = 74.0
# Retreat must be faster than Penni's 78px/s swim to create real spacing.
# Zero reverts to the older low-speed retreat.
@export_range(0.0, 180.0, 1.0) var flee_speed: float = 105.0


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, Color(0.61, 0.89, 0.86, 0.75), 1.0)
	if species == null or species.item_data == null:
		return
	var texture: Texture2D = species.item_data.sprite
	if texture == null:
		return
	var aspect: float = float(texture.get_height()) / maxf(float(texture.get_width()), 1.0)
	var preview: Rect2 = Rect2(-10.0, -10.0 * aspect, 20.0, 20.0 * aspect)
	draw_texture_rect(texture, preview, false)
