class_name StoragePanel
extends VBoxContainer

# The Terminal's storage view. This is inventory, not Jerry's catch collection.
# Use the same shared pixel UI as Shop, and read the existing live storage.
const S := PixelUI.SCALE
const TILE_SIZE := Vector2(40 * S, 40 * S)

@onready var _summary: Label = %StorageSummary
@onready var _grid: GridContainer = %StorageGrid
@onready var _icon_frame: PanelContainer = %StorageIconFrame
@onready var _icon: TextureRect = %StorageIcon
@onready var _name: Label = %StorageName
@onready var _count: Label = %StorageCount
@onready var _description: Label = %StorageDescription

var _selected_id: StringName = &""
var _counts: Dictionary = {}
var _items: Dictionary = {}
var _tiles: Dictionary = {}
var _button_group := ButtonGroup.new()



# Recount every time this tab opens. Trades and catches modify this same array.
func refresh() -> void:
	_counts.clear()
	_items.clear()

	for item: ItemData in FishingManager.current_storage:
		if item == null or item.item_id == &"":
			continue
		var id: StringName = item.item_id
		_counts[id] = int(_counts.get(id, 0)) + 1
		if not _items.has(id):
			_items[id] = item

	var ids: Array = _counts.keys()
	ids.sort()
	if not _counts.has(_selected_id):
		_selected_id = &"" if ids.is_empty() else ids[0]

	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tiles.clear()

	var total := 0
	for count in _counts.values():
		total += int(count)
	_summary.text = "%d stored  |  %d types" % [total, _counts.size()]

	for id in ids:
		var tile := _make_tile(id)
		_grid.add_child(tile)
		_tiles[id] = tile
		if id == _selected_id:
			tile.set_pressed_no_signal(true)

	_show_details()


func focus_selected() -> void:
	if _tiles.has(_selected_id):
		_tiles[_selected_id].grab_focus()


func _make_tile(id: StringName) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.toggle_mode = true
	tile.button_group = _button_group
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.tooltip_text = _display_name(id)

	var item: ItemData = _items[id]
	if item.sprite != null:
		tile.icon = item.sprite
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		tile.text = _display_name(id)
		tile.clip_text = true

	var badge := Label.new()
	badge.text = "x%d" % _counts[id]
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_color_override("font_color", Color("745600"))
	badge.add_theme_font_size_override("font_size", PixelUI.SMALL_SIZE)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tile.add_child(badge)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -78
	badge.offset_top = -32
	badge.offset_right = -6
	badge.offset_bottom = -3

	tile.pressed.connect(_select.bind(id))
	tile.focus_entered.connect(_select.bind(id))
	return tile


func _select(id: StringName) -> void:
	_selected_id = id
	if _tiles.has(id):
		_tiles[id].set_pressed_no_signal(true)
	_show_details()


func _show_details() -> void:
	if _selected_id == &"" or not _items.has(_selected_id):
		_icon.texture = null
		_name.text = "Storage empty"
		_count.text = ""
		_description.text = "Catch a fish to add it to your storage."
		return

	var item: ItemData = _items[_selected_id]
	_icon.texture = item.sprite
	_name.text = _display_name(_selected_id)
	_count.text = "%d in storage" % _counts[_selected_id]
	_description.text = "Your stored items can be spent on trades or used elsewhere."


func _display_name(id: StringName) -> String:
	return String(id).replace("_", " ").capitalize()
