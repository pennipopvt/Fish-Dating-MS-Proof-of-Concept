
extends Node2D

@export var cloud_count: int = 12
@export var spawn_width: float = 320.0
@export var follow_viewport_size: bool = true
@export var min_height: float = 10.0
@export var max_height: float = 90.0

@export var min_speed: float = 0.5
@export var max_speed: float = 2.0

@export var min_opacity: float = 0.4
@export var max_opacity: float = 0.9

var templates: Array[Sprite2D] = []
var clouds: Array[Sprite2D] = []
var speeds: Dictionary = {}
var _viewport_dimensions: Vector2 = Vector2(320.0, 180.0)


func _ready() -> void:
	if follow_viewport_size:
		_viewport_dimensions = get_viewport_rect().size
		spawn_width = _viewport_dimensions.x
		get_viewport().size_changed.connect(_on_viewport_resized)
	# Collect the original sprites as templates.
	for child in get_children():
		if child is Sprite2D:
			templates.append(child)
			child.hide()

	if templates.is_empty():
		return

	# Spawn randomized copies.
	for i in range(cloud_count):
		var template = templates.pick_random()
		var cloud := template.duplicate() as Sprite2D

		add_child(cloud)
		cloud.show()

		cloud.position = Vector2(
			randf_range(0.0, spawn_width),
			randf_range(min_height, max_height) * _viewport_dimensions.y / 180.0
		)

		cloud.modulate.a = randf_range(
			min_opacity,
			max_opacity
		)

		speeds[cloud] = randf_range(
			min_speed,
			max_speed
		)

		clouds.append(cloud)


func _process(delta: float) -> void:
	for cloud in clouds:
		cloud.position.x += speeds[cloud] * delta

		if cloud.texture == null:
			continue

		var half_width := (
			cloud.texture.get_width()
			* absf(cloud.scale.x) / 2.0
		)

		if cloud.position.x - half_width > spawn_width:
			cloud.position.x = -half_width


# Preserve cloud coverage and speed when the SubViewport expands, rather
# than continuing to spawn and wrap clouds at the old 320px edge.
func _on_viewport_resized() -> void:
	if not follow_viewport_size:
		return
	var next_size: Vector2 = get_viewport_rect().size
	if next_size.x <= 0.0 or next_size.y <= 0.0 or next_size == _viewport_dimensions:
		return
	var horizontal_ratio: float = next_size.x / maxf(_viewport_dimensions.x, 1.0)
	var vertical_ratio: float = next_size.y / maxf(_viewport_dimensions.y, 1.0)
	for cloud in clouds:
		if is_instance_valid(cloud):
			cloud.position.x *= horizontal_ratio
			cloud.position.y *= vertical_ratio
	_viewport_dimensions = next_size
	spawn_width = next_size.x
