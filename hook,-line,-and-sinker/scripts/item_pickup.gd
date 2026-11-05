class_name ItemPickup
extends Interactable

@export var item: ItemData

func _ready() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	collision.shape = shape
	add_child(collision)
	var icon := Sprite2D.new()
	icon.position = Vector2(0, -10)
	if item != null:
		icon.texture = item.sprite
	add_child(icon)
	super._ready()

func interact(_player: Node2D) -> void:
	var player := _player as Player
	if player == null or item == null:
		return
	if player.take_item(item):
		if player.current_interactable == self:
			player.current_interactable = null
		queue_free()
