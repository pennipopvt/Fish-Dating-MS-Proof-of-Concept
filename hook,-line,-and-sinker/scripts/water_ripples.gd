
extends Node2D

@export var ripple_count: int = 15

# Area relative to the WaterRipples node.
@export var area_size := Vector2(320.0, 40.0)

@export var min_lifetime: float = 2.0
@export var max_lifetime: float = 5.0

@export var drift_distance: float = 12.0
@export var max_opacity: float = 0.55

var templates: Array[Sprite2D] = []
var ripples: Array[Sprite2D] = []
var ripple_states: Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is Sprite2D:
			templates.append(child)
			child.hide()

	if templates.is_empty():
		return

	for i in range(ripple_count):
		var template = templates.pick_random()
		var ripple := template.duplicate() as Sprite2D

		add_child(ripple)
		ripple.show()

		ripples.append(ripple)
		_reset_ripple(ripple, true)


func _process(delta: float) -> void:
	for ripple in ripples:
		var state: Dictionary = ripple_states[ripple]

		state["age"] += delta

		if state["age"] >= state["lifetime"]:
			_reset_ripple(ripple)
			continue

		var progress: float = (
			state["age"] / state["lifetime"]
		)

		# Slowly drift horizontally.
		ripple.position.x = round(
			state["start_x"]
			+ progress * state["distance"]
		)

		# Fade in and out.
		ripple.modulate.a = (
			sin(progress * PI)
			* state["opacity"]
		)


func _reset_ripple(
	ripple: Sprite2D,
	random_start: bool = false
) -> void:
	var lifetime := randf_range(
		min_lifetime,
		max_lifetime
	)

	var age := 0.0

	if random_start:
		age = randf_range(0.0, lifetime)

	var start_x := randf_range(
		0.0,
		area_size.x
	)

	var start_y := randf_range(
		0.0,
		area_size.y
	)

	ripple.position = Vector2(
		start_x,
		start_y
	)

	ripple_states[ripple] = {
		"age": age,
		"lifetime": lifetime,
		"start_x": start_x,
		"distance": randf_range(
			-drift_distance,
			drift_distance
		),
		"opacity": randf_range(
			max_opacity * 0.4,
			max_opacity
		)
	}
