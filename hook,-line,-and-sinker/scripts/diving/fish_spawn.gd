@tool
extends Marker2D
class_name DivingFishSpawn

## Place this marker in the lagoon to decide where a wild fish starts.
## Pick a FishData resource in the Inspector; its inventory sprite will appear
## as a preview in the editor, but only the actual fish actor exists at runtime.
@export var species: FishData:
	set(value):
		species = value
		queue_redraw()

@export var random_seed: int = 2041


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
