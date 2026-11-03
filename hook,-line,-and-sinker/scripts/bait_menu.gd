class_name BaitMenu
extends CanvasLayer

# Player-facing bait picker: a 3x3 grid of baits on the left, details on the right.
# Bait data and odds live in FishingManager; this script only displays and equips.

const GRID_SLOTS := 9
const TILE_SIZE := Vector2(120, 120)
const TILE_NORMAL_COLOR := Color("2a5f7a")
const TILE_HOVER_COLOR := Color("36789a")
const TILE_SELECTED_COLOR := Color("4f9fca")
const TILE_EMPTY_COLOR := Color("1d3a49")
const EQUIPPED_BORDER_COLOR := Color("f2c14e")
const TILE_PADDING := 16
const TILE_CORNER_RADIUS := 20
const FISH_ICON_SIZE := Vector2(96, 28)
const ODDS_UP_COLOR := Color(0.55, 0.9, 0.55)
const ODDS_DOWN_COLOR := Color(0.95, 0.45, 0.45)

@onready var _bait_grid: GridContainer = %BaitGrid
@onready var _bait_icon_frame: PanelContainer = %BaitIconFrame
@onready var _bait_icon: TextureRect = %BaitIcon
@onready var _name_label: Label = %BaitName
@onready var _equipped_label: Label = %EquippedLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _odds_list: VBoxContainer = %OddsList
@onready var _equip_button: Button = %EquipButton
@onready var _close_button: Button = %CloseButton

var _selected_bait: BaitData = null
var _bait_tiles: Dictionary[BaitData, Button] = {}
var _button_group := ButtonGroup.new()


func _ready() -> void:
	hide()
	add_to_group(&"bait_menu")
	add_to_group(&"modal_ui")
	_bait_icon_frame.add_theme_stylebox_override("panel", _make_tile_style(TILE_NORMAL_COLOR))
	FishingManager.bait_changed.connect(_on_bait_changed)
	_equip_button.pressed.connect(_on_equip_pressed)
	_close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Open the menu while keeping world animation running. Starts on equipped bait.
func open() -> void:
	if visible:
		return

	show()
	
	_selected_bait = FishingManager.equipped_bait
	_refresh()
	_focus_selected_bait()


# Close the menu and allow gameplay input again.
func close() -> void:
	if not visible:
		return

	hide()
	


# Rebuild the 3x3 grid. Slots past the available baits stay as empty tiles.
func _refresh() -> void:
	_clear_children(_bait_grid)
	_bait_tiles.clear()

	var baits: Array[BaitData] = []
	for bait in FishingManager.available_baits:
		if bait != null:
			baits.append(bait)
	if baits.size() > GRID_SLOTS:
		push_warning("BaitMenu shows only the first %d baits" % GRID_SLOTS)

	for i in GRID_SLOTS:
		if i < baits.size():
			var bait: BaitData = baits[i]
			var tile := _make_bait_tile(bait)
			tile.pressed.connect(_select_bait.bind(bait))
			tile.focus_entered.connect(_select_bait.bind(bait))
			_bait_grid.add_child(tile)
			_bait_tiles[bait] = tile
		else:
			_bait_grid.add_child(_make_empty_tile())

	if not _bait_tiles.has(_selected_bait):
		_selected_bait = null if _bait_tiles.is_empty() else _bait_tiles.keys()[0]

	if _selected_bait != null:
		_bait_tiles[_selected_bait].set_pressed_no_signal(true)

	_show_details()


func _make_bait_tile(bait: BaitData) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.toggle_mode = true
	tile.button_group = _button_group
	tile.tooltip_text = _bait_name(bait)

	var equipped: bool = bait == FishingManager.equipped_bait
	tile.add_theme_stylebox_override("normal", _make_tile_style(TILE_NORMAL_COLOR, equipped))
	tile.add_theme_stylebox_override("hover", _make_tile_style(TILE_HOVER_COLOR, equipped))
	tile.add_theme_stylebox_override("pressed", _make_tile_style(TILE_SELECTED_COLOR, equipped))
	tile.add_theme_stylebox_override("hover_pressed", _make_tile_style(TILE_SELECTED_COLOR, equipped))
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if bait.icon != null:
		tile.icon = bait.icon
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		tile.text = _bait_name(bait)
		tile.clip_text = true

	return tile


func _make_empty_tile() -> Panel:
	var tile := Panel.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.add_theme_stylebox_override("panel", _make_tile_style(TILE_EMPTY_COLOR))
	return tile


# A solid rounded background; the equipped bait also gets a gold border.
func _make_tile_style(fill_color: Color, equipped: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.set_corner_radius_all(TILE_CORNER_RADIUS)
	style.set_content_margin_all(TILE_PADDING)
	if equipped:
		style.set_border_width_all(6)
		style.border_color = EQUIPPED_BORDER_COLOR
	return style


func _select_bait(bait: BaitData) -> void:
	if bait == _selected_bait:
		return

	_selected_bait = bait
	_bait_tiles[bait].set_pressed_no_signal(true)
	_show_details()


# Name, description, and the chance of each fish with this bait.
func _show_details() -> void:
	_clear_children(_odds_list)

	var bait := _selected_bait
	if bait == null:
		_bait_icon.texture = null
		_name_label.text = "No bait available"
		_equipped_label.hide()
		_description_label.text = ""
		_equip_button.disabled = true
		_equip_button.text = "Equip"
		return

	var equipped: bool = bait == FishingManager.equipped_bait
	_bait_icon.texture = bait.icon
	_name_label.text = _bait_name(bait)
	_equipped_label.visible = equipped
	_description_label.text = bait.description
	_equip_button.disabled = equipped
	_equip_button.text = "Equipped" if equipped else "Equip"

	var odds: Dictionary[FishData, float] = FishingManager.get_bait_odds(bait)
	var baseline: Dictionary[FishData, float] = FishingManager.get_bait_odds(null)
	if odds.is_empty():
		var none := Label.new()
		none.text = "Nothing bites here."
		_odds_list.add_child(none)
		return

	for fish in odds:
		_odds_list.add_child(_make_odds_row(fish, odds[fish], baseline.get(fish, 0.0)))


# [fish icon] Fish Name ........ 75%   (green if better than no bait, red if worse)
func _make_odds_row(fish: FishData, chance: float, baseline_chance: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var icon := TextureRect.new()
	icon.texture = fish.item_data.sprite if fish.item_data != null else null
	icon.custom_minimum_size = FISH_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = String(fish.fish_id).capitalize()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var chance_label := Label.new()
	chance_label.text = "%d%%" % roundi(chance * 100.0)
	if chance > baseline_chance + 0.005:
		chance_label.add_theme_color_override("font_color", ODDS_UP_COLOR)
	elif chance < baseline_chance - 0.005:
		chance_label.add_theme_color_override("font_color", ODDS_DOWN_COLOR)
	row.add_child(chance_label)

	return row


func _bait_name(bait: BaitData) -> String:
	return bait.display_name if bait.display_name != "" else String(bait.bait_id).capitalize()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _focus_selected_bait() -> void:
	if _selected_bait != null:
		_bait_tiles[_selected_bait].grab_focus()
	else:
		_close_button.grab_focus()


func _on_equip_pressed() -> void:
	if _selected_bait != null:
		FishingManager.equip_bait(_selected_bait)


func _on_bait_changed(_bait: BaitData) -> void:
	if visible:
		_refresh()
		_focus_selected_bait()
