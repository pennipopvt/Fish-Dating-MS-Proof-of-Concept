
extends Node2D

@export var cloud_count: int = 12
@export var spawn_width: float = 320.0
@export var min_height: float = 10.0
@export var max_height: float = 90.0

@export var min_speed: float = 0.5
@export var max_speed: float = 2.0

@export var min_opacity: float = 0.4
@export var max_opacity: float = 0.9

var templates: Array[Sprite2D] = []
var clouds: Array[Sprite2D] = []
var speeds: Dictionary = {}


func _ready() -> void:
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
			randf_range(min_height, max_height)
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
