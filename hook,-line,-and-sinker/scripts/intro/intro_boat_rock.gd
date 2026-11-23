class_name IntroBoatRock
extends Node2D

# Move the whole reusable boat, including its seat markers and occupants,
# gently up/down with the waves. Do not rotate the boat or Penni.
@export_group("Boat Bobbing")
@export_range(0.5, 12.0, 0.1, "suffix:s") var rocking_period_seconds: float = 3.8
@export_range(0.0, 8.0, 0.1, "suffix:px") var vertical_bob_pixels: float = 2.0

var _rest_position: Vector2
var _rest_rotation: float
var _elapsed: float = 0.0


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	var phase: float = _elapsed * TAU / maxf(rocking_period_seconds, 0.1)
	# No pitch/roll: only a small floating movement relative to the
	# editor-authored boat position, which is now lower at the waterline.
	rotation = _rest_rotation
	position = _rest_position + Vector2(0.0, sin(phase) * vertical_bob_pixels)
