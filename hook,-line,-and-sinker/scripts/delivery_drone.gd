class_name DeliveryDrone
extends Node2D

# Flies in from off-screen carrying pickups (items or upgrade packages),
# drops each one at its drop point, then flies away and frees itself.
#
# Usage:
#   var drone := DeliveryDrone.new()
#   world.add_child(drone)
#   drone.deliver([pickup_a, pickup_b], [pos_a, pos_b])  # pickups not yet in the tree

signal item_dropped(pickup: ItemPickup)
signal finished

const TEXTURE := preload("res://sprites/placeholders/drone.png")

@export var fly_in_offset := Vector2(220, -140)   # where it enters from, relative to the first drop
@export var fly_out_offset := Vector2(-220, -140) # where it leaves to, relative to the last drop
@export var hover_height := 36.0                  # height above the drop point while releasing
@export var fly_time := 1.4
@export var move_time := 0.5
@export var hover_time := 0.35
@export var fall_time := 0.35
@export var bob_amount := 1.5
@export var bob_speed := 6.0

const CARRY_OFFSET := Vector2(0, 10)  # where a held item hangs under the claw
const PICKUP_ICON_OFFSET := Vector2(0, -10)  # matches ItemPickup's icon position

var _body: Sprite2D
var _carried: Sprite2D
var _time := 0.0


func _ready() -> void:
	z_index = 10
	_body = Sprite2D.new()
	_body.texture = TEXTURE
	add_child(_body)

	_carried = Sprite2D.new()
	_carried.position = CARRY_OFFSET
	_carried.z_index = -1
	add_child(_carried)


func _process(delta: float) -> void:
	_time += delta
	# Body bobs; snap to whole pixels to stay pixel-perfect.
	_body.position.y = round(sin(_time * bob_speed) * bob_amount)
	_carried.position.y = CARRY_OFFSET.y + _body.position.y


func deliver(pickups: Array[ItemPickup], drop_positions: Array[Vector2]) -> void:
	assert(pickups.size() == drop_positions.size())
	if pickups.is_empty():
		queue_free()
		return

	global_position = drop_positions[0] + fly_in_offset
	_face(drop_positions[0].x)

	for i in pickups.size():
		var pickup := pickups[i]
		var hover := drop_positions[i] + Vector2(0, -hover_height)
		_carried.texture = pickup.get_icon()
		_carried.visible = true

		_face(hover.x)
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "global_position", hover, fly_time if i == 0 else move_time)
		await tween.finished
		await get_tree().create_timer(hover_time, false).timeout

		await _drop(pickup, drop_positions[i])

	await get_tree().create_timer(hover_time, false).timeout
	var away := global_position + fly_out_offset
	_face(away.x)
	var leave := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	leave.tween_property(self, "global_position", away, fly_time)
	await leave.finished

	finished.emit()
	queue_free()


# Let go of the carried pickup: it falls, then lands in the world.
func _drop(pickup: ItemPickup, ground: Vector2) -> void:
	_carried.visible = false

	var falling := Sprite2D.new()
	falling.texture = _carried.texture
	falling.z_index = z_index - 1
	get_parent().add_child(falling)
	falling.global_position = _carried.global_position

	var fall := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(falling, "global_position", ground + PICKUP_ICON_OFFSET, fall_time)
	await fall.finished
	falling.queue_free()

	get_parent().add_child(pickup)
	pickup.global_position = ground
	item_dropped.emit(pickup)


func _face(target_x: float) -> void:
	if _body != null and target_x != global_position.x:
		_body.flip_h = target_x < global_position.x
