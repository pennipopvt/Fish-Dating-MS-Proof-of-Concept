class_name BobberShelf
extends Interactable

# Two 16x16 shelf tiles per row. New complete rows grow upward.
const TILE_SIZE := 16
const COLUMNS := 2
const SHELF_TEXTURE: Texture2D = preload("res://sprites/environment/bobber_shelf.png")

@export var prompt: InteractPrompt
@onready var display: Node2D = $Display
@onready var collision: CollisionShape2D = $CollisionShape2D

var _player_in_range := false


func _ready() -> void:
	super._ready()
	BobberManager.collection_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for child in display.get_children():
		display.remove_child(child)
		child.queue_free()
	var unlocked: Array[BobberData] = BobberManager.get_unlocked_bobbers()
	var rows: int = maxi(1, ceili(float(unlocked.size()) / COLUMNS))
	for i in range(rows * COLUMNS):
		var col: int = i % COLUMNS
		var row: int = i / COLUMNS
		var center := Vector2(float(col * TILE_SIZE) - TILE_SIZE / 2.0, -float(row * TILE_SIZE) - TILE_SIZE / 2.0)
		var tile := Sprite2D.new()
		tile.name = "ShelfTile_%d" % i
		tile.texture = SHELF_TEXTURE
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tile.position = center
		display.add_child(tile)
		if i < unlocked.size():
			var sprite := Sprite2D.new()
			sprite.name = "Bobber_%s" % String(unlocked[i].bobber_id)
			sprite.texture = unlocked[i].sprite
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position = center
			# Inherit the shelf layer. No additional z offset above Penni.
			display.add_child(sprite)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(COLUMNS * TILE_SIZE, rows * TILE_SIZE)
	collision.shape = shape
	collision.position = Vector2(0, -rows * TILE_SIZE / 2.0)
	if prompt != null:
		prompt.position = Vector2(0, -rows * TILE_SIZE - 11)


func interact(player: Node2D) -> void:
	if not (player is Player) or player.busy or GameManager.is_modal_ui_open():
		return
	get_tree().call_group(&"bobber_menu", &"open")
	_update_prompt()


func _on_body_entered(body: Node2D) -> void:
	super._on_body_entered(body)
	if body is Player:
		_player_in_range = true
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	super._on_body_exited(body)
	if body is Player:
		_player_in_range = false
		_update_prompt()


func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_in_range and not GameManager.is_modal_ui_open():
		prompt.pop_in()
	else:
		prompt.pop_out()
