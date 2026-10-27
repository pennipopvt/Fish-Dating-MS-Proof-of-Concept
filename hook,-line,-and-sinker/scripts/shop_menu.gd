class_name ShopMenu
extends CanvasLayer

# Player-facing shop UI. All trade logic lives in ShopManager;
# this script only displays trades and forwards purchases.

const UNAFFORDABLE_MODULATE := Color(1, 1, 1, 0.45)
const ENOUGH_COLOR := Color(0.55, 0.9, 0.55)
const MISSING_COLOR := Color(0.95, 0.45, 0.45)
const TILE_SIZE := Vector2(120, 120)
const TILE_NORMAL_COLOR := Color("2a5f7a")
const TILE_HOVER_COLOR := Color("36789a")
const TILE_SELECTED_COLOR := Color("4f9fca")
const TILE_PADDING := 16
const TILE_CORNER_RADIUS := 20
const SLOT_ICON_SIZE := Vector2(112, 80)
const REWARD_ICON_SIZE := Vector2(64, 64)

@onready var _trade_grid: GridContainer = %TradeGrid
@onready var _trade_icon_frame: PanelContainer = %TradeIconFrame
@onready var _trade_icon: TextureRect = %TradeIcon
@onready var _name_label: Label = %TradeName
@onready var _exchange_row: HBoxContainer = %ExchangeRow
@onready var _status_label: Label = %StatusLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _close_button: Button = %CloseButton

var _selected_trade: TradeData = null
var _trade_tiles: Dictionary = {}
var _button_group := ButtonGroup.new()
var _tile_styles := {
	"normal": _make_tile_style(TILE_NORMAL_COLOR),
	"hover": _make_tile_style(TILE_HOVER_COLOR),
	"pressed": _make_tile_style(TILE_SELECTED_COLOR),
	"hover_pressed": _make_tile_style(TILE_SELECTED_COLOR),
	"focus": StyleBoxEmpty.new(),
}


func _ready() -> void:
	hide()
	_trade_icon_frame.add_theme_stylebox_override("panel", _tile_styles["normal"])
	ShopManager.trade_completed.connect(_on_trade_completed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Open the shop and pause the game behind it.
func open() -> void:
	if visible:
		return

	show()
	get_tree().paused = true
	_selected_trade = null
	_status_label.text = ""
	_refresh()
	_focus_selected_trade()


# Close the shop and resume the game.
func close() -> void:
	if not visible:
		return

	hide()
	get_tree().paused = false


# Rebuild the trade tiles from ShopManager.trades.
func _refresh() -> void:
	_clear_children(_trade_grid)
	_trade_tiles.clear()

	for trade in ShopManager.trades:
		if trade == null:
			continue

		var tile := _make_trade_tile(trade)
		tile.pressed.connect(_select_trade.bind(trade))
		tile.focus_entered.connect(_select_trade.bind(trade))

		_trade_grid.add_child(tile)
		_trade_tiles[trade] = tile

	if not _trade_tiles.has(_selected_trade):
		_selected_trade = null

		if not _trade_tiles.is_empty():
			_selected_trade = _trade_tiles.keys()[0]

	if _selected_trade != null:
		_trade_tiles[_selected_trade].set_pressed_no_signal(true)

	_show_details()


func _make_trade_tile(trade: TradeData) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.toggle_mode = true
	tile.button_group = _button_group
	tile.tooltip_text = trade.display_name

	for style_name in _tile_styles:
		tile.add_theme_stylebox_override(style_name, _tile_styles[style_name])

	if trade.icon != null:
		tile.icon = trade.icon
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		tile.text = trade.display_name
		tile.clip_text = true

	if not ShopManager.can_trade(trade):
		tile.modulate = UNAFFORDABLE_MODULATE

	return tile


# A solid rounded background; the item icon sits on top of it.
func _make_tile_style(fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.set_corner_radius_all(TILE_CORNER_RADIUS)
	style.set_content_margin_all(TILE_PADDING)
	return style


func _select_trade(trade: TradeData) -> void:
	if trade == _selected_trade:
		return

	_selected_trade = trade
	_trade_tiles[trade].set_pressed_no_signal(true)
	_status_label.text = ""
	_show_details()


# Show the selected trade as: [fish] have/need ... -> [reward] +amount
func _show_details() -> void:
	_clear_children(_exchange_row)

	var trade := _selected_trade

	if trade == null:
		_trade_icon.texture = null
		_name_label.text = "No trades available"
		_confirm_button.disabled = true
		return

	_trade_icon.texture = trade.icon
	_name_label.text = trade.display_name

	for requirement in trade.requirements:
		if requirement != null and requirement.item != null:
			_exchange_row.add_child(_make_cost_slot(requirement))

	if trade.reward_method != &"":
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 56)
		_exchange_row.add_child(arrow)
		_exchange_row.add_child(_make_slot(
			trade.icon,
			"+%d" % trade.reward_amount,
			Color.WHITE,
			_describe_reward(trade),
			true
		))

	var affordable := ShopManager.can_trade(trade)
	_confirm_button.disabled = not affordable

	if not affordable and _status_label.text == "":
		_status_label.text = "Not enough fish."


func _make_cost_slot(requirement: TradeRequirement) -> Control:
	var item := requirement.item
	var have := ShopManager.count_item(item.item_id)
	var item_name := String(item.item_id).capitalize()

	return _make_slot(
		item.sprite,
		"%d/%d" % [have, requirement.amount],
		ENOUGH_COLOR if have >= requirement.amount else MISSING_COLOR,
		"%dx %s" % [requirement.amount, item_name]
	)


# An icon with a caption underneath; the tooltip carries the full name.
# Framed icons (trade icons) get the same colored background as the tiles.
func _make_slot(
	texture: Texture2D,
	caption: String,
	caption_color: Color,
	tooltip: String,
	framed: bool = false
) -> Control:
	var slot := VBoxContainer.new()
	slot.tooltip_text = tooltip
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = REWARD_ICON_SIZE if framed else SLOT_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if framed:
		var frame := PanelContainer.new()
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", _tile_styles["normal"])
		frame.add_child(icon)
		slot.add_child(frame)
	else:
		slot.add_child(icon)

	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", caption_color)
	slot.add_child(label)

	return slot


func _describe_reward(trade: TradeData) -> String:
	var reward_name := (
		String(trade.reward_method).trim_prefix("shop_reward_").capitalize()
	)

	return "%s +%d" % [reward_name, trade.reward_amount]


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _focus_selected_trade() -> void:
	if _selected_trade != null:
		_trade_tiles[_selected_trade].grab_focus()
	else:
		_close_button.grab_focus()


func _on_confirm_pressed() -> void:
	if _selected_trade == null:
		return

	if not ShopManager.make_trade(_selected_trade):
		_status_label.text = "Trade failed."
		_refresh()


func _on_trade_completed(trade: TradeData) -> void:
	if not visible:
		return

	_status_label.text = "Purchased %s!" % trade.display_name
	_refresh()

	# Keep keyboard focus usable if the trade is no longer affordable.
	if _confirm_button.disabled:
		_focus_selected_trade()
