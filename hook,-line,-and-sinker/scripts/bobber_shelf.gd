class_name BobberShelf
extends Interactable

# The shelf is two 16x16 tiles wide and grows upward in complete rows.
const TILE_SIZE := 16
const COLUMNS := 2
const SHELF_TEXTURE: Texture2D = preload("res://sprites/environment/bobber_shelf.png")
const TILE_SIZE_UI := Vector2(120, 120)
const TILE_NORMAL_COLOR := Color("2a5f7a")
const TILE_HOVER_COLOR := Color("36789a")
const TILE_SELECTED_COLOR := Color("4f9fca")
const EQUIPPED_BORDER_COLOR := Color("f2c14e")

@export var prompt: InteractPrompt
@onready var display: Node2D = $Display
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var menu: CanvasLayer = $Menu
@onready var options: GridContainer = $Menu/Panel/Margin/Layout/Body/Scroll/Options
@onready var bobber_icon_frame: PanelContainer = $Menu/Panel/Margin/Layout/Body/Details/Header/BobberIconFrame
@onready var bobber_icon: TextureRect = $Menu/Panel/Margin/Layout/Body/Details/Header/BobberIconFrame/BobberIcon
@onready var bobber_name: Label = $Menu/Panel/Margin/Layout/Body/Details/Header/Names/BobberName
@onready var equipped_label: Label = $Menu/Panel/Margin/Layout/Body/Details/Header/Names/EquippedLabel
@onready var description_label: Label = $Menu/Panel/Margin/Layout/Body/Details/Description
@onready var equip_button: Button = $Menu/Panel/Margin/Layout/Body/Details/Equip
@onready var close_button: Button = $Menu/Panel/Margin/Layout/Close

var _player_in_range := false
var _selected: BobberData = null
var _tiles: Dictionary = {}
var _button_group := ButtonGroup.new()


func _ready() -> void:
	super._ready()
	menu.hide()
	bobber_icon_frame.add_theme_stylebox_override("panel", _make_style(TILE_NORMAL_COLOR))
	close_button.pressed.connect(close_menu)
	equip_button.pressed.connect(_equip_selected)
	BobberManager.collection_changed.connect(_refresh)
	BobberManager.equipped_changed.connect(_on_equipped_changed)
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
			sprite.z_index = 1
			display.add_child(sprite)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(COLUMNS * TILE_SIZE, rows * TILE_SIZE)
	collision.shape = shape
	collision.position = Vector2(0, -rows * TILE_SIZE / 2.0)
	# Keep the interaction bubble above the tallest shelf.
	prompt.position = Vector2(0, -rows * TILE_SIZE - 11)
	if menu.visible:
		_refresh_options()


func _refresh_options() -> void:
	for child in options.get_children():
		options.remove_child(child)
		child.queue_free()
	_tiles.clear()
	var unlocked: Array[BobberData] = BobberManager.get_unlocked_bobbers()
	for data in unlocked:
		var tile := Button.new()
		tile.custom_minimum_size = TILE_SIZE_UI
		tile.toggle_mode = true
		tile.button_group = _button_group
		tile.tooltip_text = data.display_name
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var equipped: bool = data.bobber_id == BobberManager.equipped_id
		tile.add_theme_stylebox_override("normal", _make_style(TILE_NORMAL_COLOR, equipped))
		tile.add_theme_stylebox_override("hover", _make_style(TILE_HOVER_COLOR, equipped))
		tile.add_theme_stylebox_override("pressed", _make_style(TILE_SELECTED_COLOR, equipped))
		tile.add_theme_stylebox_override("hover_pressed", _make_style(TILE_SELECTED_COLOR, equipped))
		tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		tile.icon = data.sprite
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.pressed.connect(_select.bind(data))
		tile.focus_entered.connect(_select.bind(data))
		options.add_child(tile)
		_tiles[data] = tile
	if not _tiles.has(_selected):
		_selected = BobberManager.get_equipped_bobber()
		if not _tiles.has(_selected):
			_selected = unlocked[0] if not unlocked.is_empty() else null
	if _selected != null:
		_tiles[_selected].set_pressed_no_signal(true)
	_show_details()


func _make_style(fill_color: Color, equipped: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.set_corner_radius_all(20)
	style.set_content_margin_all(16)
	if equipped:
		style.set_border_width_all(6)
		style.border_color = EQUIPPED_BORDER_COLOR
	return style


func _select(data: BobberData) -> void:
	_selected = data
	if _tiles.has(data):
		_tiles[data].set_pressed_no_signal(true)
	_show_details()


func _show_details() -> void:
	if _selected == null:
		bobber_icon.texture = null
		bobber_name.text = "No bobbers"
		equipped_label.hide()
		description_label.text = ""
		equip_button.disabled = true
		return
	var equipped: bool = _selected.bobber_id == BobberManager.equipped_id
	bobber_icon.texture = _selected.sprite
	bobber_name.text = _selected.display_name
	equipped_label.visible = equipped
	description_label.text = "A bobber from Silas." if _selected.source_npc_id == &"test_npc" else "A fishing bobber."
	equip_button.disabled = equipped
	equip_button.text = "Equipped" if equipped else "Equip"


func _equip_selected() -> void:
	if _selected != null:
		BobberManager.equip_bobber(_selected.bobber_id)


func _on_equipped_changed(_bobber: BobberData) -> void:
	if menu.visible:
		_refresh_options()


func interact(_player: Node2D) -> void:
	if not (_player is Player) or menu.visible:
		return
	menu.show()
	_selected = BobberManager.get_equipped_bobber()
	_refresh_options()
	if _selected != null:
		_tiles[_selected].grab_focus()
	else:
		close_button.grab_focus()
	_update_prompt()


func close_menu() -> void:
	menu.hide()
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if menu.visible and event.is_action_pressed(&"ui_cancel"):
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
	if _player_in_range and not menu.visible:
		prompt.pop_in()
	else:
		prompt.pop_out()
