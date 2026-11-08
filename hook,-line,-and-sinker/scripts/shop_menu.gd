class_name ShopMenu
extends CanvasLayer

# Player-facing shop UI. All trade logic lives in ShopManager;
# this script only displays trades and forwards purchases.

const UNAFFORDABLE_MODULATE := Color(1, 1, 1, 0.45)
const S := PixelUI.SCALE
const ENOUGH_COLOR := PixelUI.GREEN
const MISSING_COLOR := PixelUI.RED
const TILE_SIZE := Vector2(40 * S, 40 * S)
const TILE_PADDING := 2  # art pixels
const SLOT_ICON_SIZE := Vector2(112, 80)
const REWARD_ICON_SIZE := Vector2(16 * S, 16 * S)
const LOCKED_MODULATE := Color(0.6, 0.6, 0.6, 0.8)
const LOCK_ICON := preload("res://sprites/placeholders/lock.png")
const LOCK_BADGE_SIZE := Vector2(16 * S, 16 * S)
const LOCKED_COLOR := PixelUI.GOLD

enum Tab { SHOP, CHALLENGES }

@onready var _tabs: TabBar = %Tabs
@onready var _shop_body: Control = %Body
@onready var _challenges_panel: ChallengesPanel = %ChallengesPanel
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
	"normal": PixelUI.box(PixelUI.TEAL, PixelUI.CYAN_DARK, TILE_PADDING),
	"hover": PixelUI.box(PixelUI.TEAL_HOVER, PixelUI.CYAN, TILE_PADDING),
	"pressed": PixelUI.box(PixelUI.TEAL_SELECTED, PixelUI.CYAN, TILE_PADDING),
	"hover_pressed": PixelUI.box(PixelUI.TEAL_SELECTED, PixelUI.CYAN, TILE_PADDING),
	"focus": StyleBoxEmpty.new(),
}


func _ready() -> void:
	hide()
	add_to_group(&"modal_ui")
	$Panel.theme = PixelUI.get_theme()
	ChallengeManager.progress_reset.connect(_on_challenge_completed.bind(null))
	_trade_icon_frame.add_theme_stylebox_override("panel", _tile_styles["normal"])
	ShopManager.trade_completed.connect(_on_trade_completed)
	ShopManager.shop_requested.connect(open)
	ChallengeManager.challenge_completed.connect(_on_challenge_completed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_close_button.pressed.connect(close)

	_tabs.add_tab("Shop")
	_tabs.add_tab("Challenges")
	_tabs.tab_changed.connect(_show_tab)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Open the shop without pausing environmental animation.
func open() -> void:
	if visible:
		return

	show()
	ShopManager.set_shop_open(true)
	_selected_trade = null
	_status_label.text = ""
	_tabs.set_current_tab(Tab.SHOP)
	_show_tab(Tab.SHOP)


# Close the shop and return gameplay input.
func close() -> void:
	if not visible:
		return

	hide()
	ShopManager.set_shop_open(false)


func _show_tab(tab: int) -> void:
	_shop_body.visible = tab == Tab.SHOP
	_challenges_panel.visible = tab == Tab.CHALLENGES

	if tab == Tab.SHOP:
		_refresh()
		_focus_selected_trade()
	else:
		_tabs.grab_focus()


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

	if ShopManager.is_trade_locked(trade):
		tile.modulate = LOCKED_MODULATE
		tile.tooltip_text = "%s (Locked)" % trade.display_name

		var badge := TextureRect.new()
		badge.texture = LOCK_ICON
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -LOCK_BADGE_SIZE.x
		badge.offset_top = 0
		badge.offset_right = 0
		badge.offset_bottom = LOCK_BADGE_SIZE.y
		tile.add_child(badge)
	elif not ShopManager.can_trade(trade):
		tile.modulate = UNAFFORDABLE_MODULATE

	return tile


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

	if trade.reward_method != &"" or trade.reward_item != null:
		var arrow := Label.new()
		arrow.text = ">"
		arrow.theme_type_variation = &"HeaderLabel"
		_exchange_row.add_child(arrow)

	if trade.reward_method != &"":
		_exchange_row.add_child(_make_slot(
			trade.icon,
			"+%d" % trade.reward_amount,
			Color.WHITE,
			_describe_reward(trade),
			true
		))

	if trade.reward_item != null:
		_exchange_row.add_child(_make_slot(
			trade.reward_item.sprite,
			"+%d" % trade.reward_item_amount,
			Color.WHITE,
			String(trade.reward_item.item_id).capitalize(),
			true
		))

	var locking := ChallengeManager.get_locking_challenge(trade)
	if locking != null:
		_confirm_button.disabled = true
		_status_label.add_theme_color_override("font_color", LOCKED_COLOR)
		_status_label.text = "Locked: complete \"%s\" in Challenges." % (
			"a hidden challenge" if locking.hidden else locking.display_name
		)
		return

	_status_label.remove_theme_color_override("font_color")
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


func _on_challenge_completed(_challenge: ChallengeData) -> void:
	if visible and _shop_body.visible:
		_refresh()


func _on_trade_completed(trade: TradeData) -> void:
	if not visible:
		return

	_status_label.text = "Purchased %s!" % trade.display_name
	if is_instance_valid(ShopManager.delivery_point):
		_status_label.text += " A drone is on the way."
	_refresh()

	# Keep keyboard focus usable if the trade is no longer affordable.
	if _confirm_button.disabled:
		_focus_selected_trade()
