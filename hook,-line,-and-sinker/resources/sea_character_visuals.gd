class_name SeaCharacterVisuals
extends Resource

# Per-character presentation only: combat, movement and story state stay
# in their existing systems, not in this resource.
@export_group("Fish-Form World Sprite")
@export_range(12.0, 96.0, 1.0, "suffix:px") var follower_width: float = 24.0

@export_group("Underwater Dialogue Portrait")
@export_range(0.5, 3.0, 0.05) var portrait_scale: float = 1.0
@export_range(-45.0, 45.0, 1.0, "suffix:°") var portrait_angle_degrees: float = 0.0
@export var portrait_offset: Vector2 = Vector2.ZERO
