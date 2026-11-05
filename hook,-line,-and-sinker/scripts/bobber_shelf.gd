class_name BobberShelf
extends Interactable

# A 16x16 authored shelf tile per slot; the bottom row never moves.
const TILE_SIZE := 16
const COLUMNS := 2

@export var prompt: InteractPrompt
@onready var display: Node2D = $Display
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var menu: CanvasLayer = $Menu
@onready var options: GridContainer = $Menu/Center/Panel/Margin/Contents/Options
@onready var close_button: Button = $Menu/Center/Panel/Margin/Contents/Close

var _player_in_range: bool = false
var _is_open: bool = false


func _ready() -> void:
	super._ready()
	menu.hide()
	close_button.pressed.connect(close_menu)
	BobberManager.collection_changed.connect(_refresh)
	BobberManager.equipped_changed.connect(_on_equipped_changed)
	_refresh()


func _refresh() -> void:
	for node in display.get_children():
		display.remove_child(node)
		node.queue_free()
	var unlocked: Array[BobberData] = BobberManager.get_unlocked_bobbers()
	var rows: int = maxi(1, ceili(float(unlocked.size()) / COLUMNS))
	var shelf_texture: Texture2D = preload("res://sprites/environment/bobber_shelf.png")
	for i in range(rows * COLUMNS):
		var col: int = i % COLUMNS
		var row: int = i / COLUMNS
		var center := Vector2((col * TILE_SIZE) - TILE_SIZE / 2.0, -row * TILE_SIZE - TILE_SIZE / 2.0)
		var tile := Sprite2D.new()
		tile.name = "ShelfTile_%d" % i
		tile.texture = shelf_texture
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tile.position = center
		display.add_child(tile)
		if i < unlocked.size():
			var bobber := Sprite2D.new()
			bobber.name = "Bobber_%s" % String(unlocked[i].bobber_id)
			bobber.texture = unlocked[i].sprite
			bobber.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			bobber.position = center
			bobber.z_index = 1
			display.add_child(bobber)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(COLUMNS * TILE_SIZE, rows * TILE_SIZE)
	collision.shape = shape
	collision.position = Vector2.ZERO + Vector2(0, -rows * TILE_SIZE / 2.0)
	_refresh_options()


func _refresh_options() -> void:
	for child in options.get_children():
		options.remove_child(child)
		child.queue_free()
	for data in BobberManager.get_unlocked_bobbers():
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 94)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var image := TextureRect.new()
		image.texture = data.sprite
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(40, 40)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(image)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = data.display_name + ("  ✓" if data.bobber_id == BobberManager.equipped_id else "")
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
		button.add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.pressed.connect(_equip.bind(data.bobber_id))
		options.add_child(button)


func _equip(id: StringName) -> void:
	BobberManager.equip_bobber(id)


func _on_equipped_changed(_bobber: BobberData) -> void:
	if _is_open:
		_refresh_options()


func interact(_player: Node2D) -> void:
	if _player is Player and not _is_open:
		_is_open = true
		menu.show()
		_update_prompt()


func close_menu() -> void:
	_is_open = false
	menu.hide()
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed(&"ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()


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
	if _player_in_range and not _is_open:
		prompt.pop_in()
	else:
		prompt.pop_out()
