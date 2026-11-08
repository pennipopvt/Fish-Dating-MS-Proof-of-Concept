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
	icon.texture = get_icon()
	add_child(icon)
	super._ready()

# What the pickup looks like in the world (and while a drone carries it).
func get_icon() -> Texture2D:
	return item.sprite if item != null else null

func interact(_player: Node2D) -> void:
	var player := _player as Player
	if player == null or item == null:
		return
	if not player.take_item(item):
		return
	player.release_interactable(self)
	queue_free()
