class_name BobberMenu
extends CanvasLayer

# Uses the same full-resolution UI structure and styling as BaitMenu.
const GRID_SLOTS := 9
const TILE_SIZE := Vector2(120, 120)
const TILE_NORMAL_COLOR := Color("2a5f7a")
const TILE_HOVER_COLOR := Color("36789a")
const TILE_SELECTED_COLOR := Color("4f9fca")
const TILE_EMPTY_COLOR := Color("1d3a49")
const EQUIPPED_BORDER_COLOR := Color("f2c14e")

@onready var _grid: GridContainer = %BobberGrid
@onready var _icon_frame: PanelContainer = %BobberIconFrame
@onready var _icon: TextureRect = %BobberIcon
@onready var _name_label: Label = %BobberName
@onready var _equipped_label: Label = %EquippedLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _info_list: VBoxContainer = %InfoList
@onready var _equip_button: Button = %EquipButton
@onready var _close_button: Button = %CloseButton

var _selected: BobberData
var _tiles: Dictionary = {}
var _button_group := ButtonGroup.new()


func _ready() -> void:
	hide()
	add_to_group(&"bobber_menu")
	add_to_group(&"modal_ui")
	BobberManager.equipped_changed.connect(_on_equipped_changed)
	BobberManager.collection_changed.connect(_on_collection_changed)
	_equip_button.pressed.connect(_on_equip_pressed)
	_close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	show()
	_selected = BobberManager.get_equipped_bobber()
	_refresh()
	if _selected != null:
		_tiles[_selected].grab_focus()
	else:
		_close_button.grab_focus()


func close() -> void:
	hide()


func _refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tiles.clear()
	var unlocked: Array[BobberData] = BobberManager.get_unlocked_bobbers()
	for i in range(GRID_SLOTS):
		if i >= unlocked.size():
			_grid.add_child(_make_empty_tile())
			continue
		var data: BobberData = unlocked[i]
		var tile := Button.new()
		tile.custom_minimum_size = TILE_SIZE
		tile.toggle_mode = true
		tile.button_group = _button_group
		tile.tooltip_text = data.display_name
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var equipped := data.bobber_id == BobberManager.equipped_id
		tile.self_modulate = Color("fff5d3") if equipped else Color.WHITE
		tile.icon = data.sprite
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.pressed.connect(_select.bind(data))
		tile.focus_entered.connect(_select.bind(data))
		_grid.add_child(tile)
		_tiles[data] = tile
	if not _tiles.has(_selected):
		_selected = unlocked[0] if not unlocked.is_empty() else null
	if _selected != null:
		_tiles[_selected].set_pressed_no_signal(true)
	_show_details()


func _make_empty_tile() -> Panel:
	var tile := Panel.new()
	tile.custom_minimum_size = TILE_SIZE
	return tile


func _select(data: BobberData) -> void:
	_selected = data
	if _tiles.has(data):
		_tiles[data].set_pressed_no_signal(true)
	_show_details()


func _show_details() -> void:
	for child in _info_list.get_children():
		_info_list.remove_child(child)
		child.queue_free()
	if _selected == null:
		_icon.texture = null
		_name_label.text = "No bobbers unlocked"
		_equipped_label.hide()
		_description_label.text = ""
		_equip_button.disabled = true
		return
	var equipped := _selected.bobber_id == BobberManager.equipped_id
	_icon.texture = _selected.sprite
	_name_label.text = _selected.display_name
	_equipped_label.visible = equipped
	_description_label.text = _selected.ability_description if not _selected.ability_description.is_empty() else "Choose this bobber for your fishing line."
	var info := Label.new()
	info.text = "%d bobbers collected" % BobberManager.get_unlocked_bobbers().size()
	_info_list.add_child(info)
	_equip_button.disabled = equipped
	_equip_button.text = "Equipped" if equipped else "Equip"


func _on_equip_pressed() -> void:
	if _selected != null:
		BobberManager.equip_bobber(_selected.bobber_id)


func _on_equipped_changed(_data: BobberData) -> void:
	if visible:
		_refresh()


func _on_collection_changed() -> void:
	if visible:
		_refresh()
