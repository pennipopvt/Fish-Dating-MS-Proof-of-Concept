class_name IntroBoatRock
extends Node2D

# Author these small movements on the IntroBoat root. Moving the root keeps
# its animated art and PlayerSpot/CameraFocus markers in the same motion.
@export_group("Gentle Boat Rock")
@export_range(0.0, 5.0, 0.1, "suffix:deg") var rocking_degrees: float = 1.4
@export_range(0.5, 12.0, 0.1, "suffix:s") var rocking_period_seconds: float = 3.8
@export_range(0.0, 8.0, 0.1, "suffix:px") var vertical_bob_pixels: float = 1.4

var _rest_position: Vector2
var _elapsed: float = 0.0


func _ready() -> void:
	_rest_position = position


func _process(delta: float) -> void:
	_elapsed += delta
	var phase: float = _elapsed * TAU / maxf(rocking_period_seconds, 0.1)
	rotation_degrees = sin(phase) * rocking_degrees
	position = _rest_position + Vector2(0.0, sin(phase + 0.65) * vertical_bob_pixels)
