class_name ShopMenu
extends CanvasLayer

# FISH CO. terminal: five pages share one scene and one set of controls.
# Tabs and borders are laid out in shop_menu.tscn and styled by terminal_theme.tres.
# This script only fills in the grid, item details, and actions.

enum Page { UPGRADES, GIFTS, STORAGE, COLLECTION, CHALLENGES }

const SLOT_SIZE := Vector2(168, 168) # 56 x 56 art pixels at 3x
const MIN_SLOTS := 12                 # Four columns, three visible rows
const LOCKED_TINT := Color(0.72, 0.75, 0.75, 0.82)
const DARK_TEXT := Color("17363b")
const DIM_TEXT := Color("45646a")
const WARNING_TEXT := Color("984b24")
const TAB_CLOSED_HEIGHT := 72.0
const TAB_OPEN_HEIGHT := 252.0

@onready var _upgrades_tab: Button = %UpgradesTab
@onready var _gifts_tab: Button = %GiftsTab
@onready var _storage_tab: Button = %StorageTab
@onready var _collection_tab: Button = %CollectionTab
@onready var _challenges_tab: Button = %ChallengesTab

@onready var _delivery_status: Label = %DeliveryStatus
@onready var _page_title: Label = %PageTitle
@onready var _page_hint: Label = %PageHint
@onready var _grid: GridContainer = %ItemGrid
@onready var _preview: TextureRect = %PreviewIcon
@onready var _item_name: Label = %ItemName
@onready var _description: Label = %DescriptionLabel
@onready var _costs: VBoxContainer = %Costs
@onready var _status: Label = %StatusLabel
@onready var _order_button: Button = %OrderButton
@onready var _page_indicator: Label = %PageIndicator
@onready var _close_button: Button = %CloseButton

var _nav_buttons: Array[Button] = []
var _page: int = Page.UPGRADES
var _entries: Array[Dictionary] = []
var _entry_buttons: Array[Button] = []
var _selected_index: int = 0
var _button_group := ButtonGroup.new()
var _last_order_message := ""
var _tab_tween: Tween


func _ready() -> void:
	hide()
	add_to_group(&"modal_ui")
	_nav_buttons = [_upgrades_tab, _gifts_tab, _storage_tab, _collection_tab, _challenges_tab]
	for i in range(_nav_buttons.size()):
		_nav_buttons[i].pressed.connect(_select_page.bind(i))

	_order_button.pressed.connect(_on_order_pressed)
	_close_button.pressed.connect(close)
	ShopManager.shop_requested.connect(open)
	ShopManager.trade_completed.connect(_on_trade_completed)
	ChallengeManager.challenge_progressed.connect(_on_challenge_changed)
	ChallengeManager.challenge_completed.connect(_on_challenge_changed)
	ChallengeManager.progress_reset.connect(_on_challenge_reset)
	FishingManager.fish_caught.connect(_on_inventory_changed)
	_refresh_page()
	_update_nav_tabs(false)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	_page = Page.UPGRADES
	_selected_index = 0
	_last_order_message = ""
	_delivery_status.text = "NO DELIVERIES"
	show()
	ShopManager.set_shop_open(true)
	_refresh_page()
	_update_nav_tabs(false)
	_upgrades_tab.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	# ShopInteractable dispatches queued deliveries when this fires.
	ShopManager.set_shop_open(false)


func _select_page(page: int) -> void:
	_page = page
	_selected_index = 0
	_last_order_message = ""
	_refresh_page()
	_update_nav_tabs(true)
	if not _entry_buttons.is_empty():
		_entry_buttons[0].grab_focus()


# The active icon-tab unfolds downwards to show its sideways title.
# The labels and icons themselves are editable child nodes in shop_menu.tscn.
func _update_nav_tabs(animate: bool) -> void:
	if _tab_tween != null and _tab_tween.is_running():
		_tab_tween.kill()
	if animate:
		_tab_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(_nav_buttons.size()):
		var tab: Button = _nav_buttons[i]
		var caption: Label = tab.get_node("VerticalTitle") as Label
		var new_height := TAB_OPEN_HEIGHT if i == _page else TAB_CLOSED_HEIGHT
		var new_alpha := 1.0 if i == _page else 0.0
		if animate:
			_tab_tween.tween_property(tab, "custom_minimum_size:y", new_height, 0.23)
			_tab_tween.tween_property(caption, "modulate:a", new_alpha, 0.16)
		else:
			tab.custom_minimum_size.y = new_height
			caption.modulate.a = new_alpha


func _refresh_page() -> void:
	_entries.clear()
	match _page:
		Page.UPGRADES, Page.GIFTS:
			_collect_trades()
		Page.STORAGE:
			_collect_storage()
		Page.COLLECTION:
			_collect_fish()
		Page.CHALLENGES:
			_collect_challenges()

	var names := ["UPGRADES", "GIFTS", "STORAGE", "COLLECTION", "CHALLENGES"]
	var explanations := [
		"Permanent fishing improvements",
		"Things to give your new friends",
		"Fish and items you currently own",
		"Fish you have discovered",
		"Objectives and unlocks"
	]
	_page_title.text = names[_page]
	_page_hint.text = explanations[_page]
	_page_indicator.text = "%s  /  %d ENTRIES" % [names[_page], _entries.size()]

	for i in range(_nav_buttons.size()):
		_nav_buttons[i].button_pressed = i == _page
		_nav_buttons[i].self_modulate = Color.WHITE if i == _page else Color(0.88, 0.9, 0.9, 0.9)

	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()

	_selected_index = mini(_selected_index, maxi(_entries.size() - 1, 0))
	for i in range(maxi(MIN_SLOTS, _entries.size())):
		if i < _entries.size():
			var button := _make_tile(_entries[i], i)
			_grid.add_child(button)
			_entry_buttons.append(button)
		else:
			var empty := PanelContainer.new()
			empty.custom_minimum_size = SLOT_SIZE
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty.self_modulate = Color(1, 1, 1, 0.55)
			_grid.add_child(empty)

	_show_details()
	if _last_order_message != "":
		_status.text = _last_order_message


func _collect_trades() -> void:
	for trade in ShopManager.trades:
		if trade == null:
			continue
		var is_upgrade := trade.reward_method != &""
		var is_gift := trade.reward_item != null and not is_upgrade
		if (_page == Page.UPGRADES and is_upgrade) or (_page == Page.GIFTS and is_gift):
			var icon: Texture2D = trade.icon
			if icon == null and trade.reward_item != null:
				icon = trade.reward_item.sprite
			_entries.append({
				"kind": "trade",
				"ref": trade,
				"name": trade.display_name,
				"icon": icon,
				"locked": ShopManager.is_trade_locked(trade)
			})


func _collect_storage() -> void:
	var counts: Dictionary = {}
	var items: Dictionary = {}
	for item in FishingManager.current_storage:
		if item == null or item.item_id == &"":
			continue
		counts[item.item_id] = int(counts.get(item.item_id, 0)) + 1
		items[item.item_id] = item

	var keys: Array = counts.keys()
	keys.sort()
	for key in keys:
		var item: ItemData = items[key]
		_entries.append({
			"kind": "storage",
			"ref": item,
			"name": _human_name(item.item_id),
			"icon": item.sprite,
			"quantity": counts[key]
		})


func _collect_fish() -> void:
	# Known fish are shown normally; fish not yet caught have mystery cards.
	var fish_list: Array[FishData] = []
	for fish in FishingManager.possible_catches:
		if fish != null and not _contains_fish_id(fish_list, fish.fish_id):
			fish_list.append(fish)
	for fish in FishingManager.catch_dex:
		if fish != null and not _contains_fish_id(fish_list, fish.fish_id):
			fish_list.append(fish)

	for fish in fish_list:
		var discovered := _has_discovered_fish(fish)
		var fish_icon: Texture2D = null
		if discovered and fish.item_data != null:
			fish_icon = fish.item_data.sprite
		_entries.append({
			"kind": "fish",
			"ref": fish,
			"name": _human_name(fish.fish_id) if discovered else "???",
			"icon": fish_icon,
			"locked": not discovered
		})


func _contains_fish_id(list: Array[FishData], id: StringName) -> bool:
	for fish in list:
		if fish.fish_id == id:
			return true
	return false


func _has_discovered_fish(fish: FishData) -> bool:
	for known in FishingManager.catch_dex:
		if known != null and known.fish_id == fish.fish_id:
			return true
	return false


func _collect_challenges() -> void:
	for challenge in ChallengeManager.challenges:
		if challenge == null:
			continue
		var hidden := challenge.hidden and not challenge.completed
		var art: Texture2D = challenge.icon
		if not challenge.completed and challenge.locked_icon != null:
			art = challenge.locked_icon
		if hidden:
			art = challenge.locked_icon
		_entries.append({
			"kind": "challenge",
			"ref": challenge,
			"name": "???" if hidden else challenge.display_name,
			"icon": art,
			"locked": hidden
		})


func _make_tile(entry: Dictionary, index: int) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = SLOT_SIZE
	tile.toggle_mode = true
	tile.button_group = _button_group
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.tooltip_text = String(entry.get("name", ""))
	tile.clip_text = true

	var icon: Texture2D = entry.get("icon") as Texture2D
	if icon != null:
		tile.icon = icon
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		tile.text = "?" if bool(entry.get("locked", false)) else String(entry.get("name", ""))
	if bool(entry.get("locked", false)):
		tile.self_modulate = LOCKED_TINT

	var amount: int = int(entry.get("quantity", 0))
	if amount > 0:
		var badge := Label.new()
		badge.text = "x%d" % amount
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_color_override("font_color", DARK_TEXT)
		tile.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -108
		badge.offset_top = -36
		badge.offset_right = -9
		badge.offset_bottom = -6

	tile.pressed.connect(_choose_tile.bind(index))
	tile.focus_entered.connect(_choose_tile.bind(index))
	if index == _selected_index:
		tile.set_pressed_no_signal(true)
	return tile


func _choose_tile(index: int) -> void:
	_selected_index = index
	for i in range(_entry_buttons.size()):
		_entry_buttons[i].set_pressed_no_signal(i == index)
	_last_order_message = ""
	_show_details()


func _show_details() -> void:
	for child in _costs.get_children():
		_costs.remove_child(child)
		child.queue_free()
	_status.text = ""
	_order_button.hide()
	_preview.texture = null

	if _entries.is_empty():
		_item_name.text = "NOTHING HERE YET"
		_description.text = "No entries are available for this page."
		return

	var entry: Dictionary = _entries[_selected_index]
	_item_name.text = String(entry.get("name", ""))
	_preview.texture = entry.get("icon") as Texture2D

	match String(entry.get("kind", "")):
		"trade":
			_show_trade_details(entry.get("ref") as TradeData)
		"storage":
			_show_storage_details(entry)
		"fish":
			_show_fish_details(entry.get("ref") as FishData)
		"challenge":
			_show_challenge_details(entry.get("ref") as ChallengeData)


func _show_trade_details(trade: TradeData) -> void:
	_description.text = "Fishing equipment upgrade." if _page == Page.UPGRADES else "A present for someone in town."
	_add_detail_line("REQUIRES:", DIM_TEXT)
	# Sprite + actual owned/required counts, one row per required fish.
	for requirement in trade.requirements:
		if requirement == null or requirement.item == null:
			continue
		_costs.add_child(_make_requirement_row(requirement))

	if trade.reward_method != &"":
		_add_detail_line("REWARD: %s +%d" % [
			String(trade.reward_method).trim_prefix("shop_reward_").replace("_", " ").to_upper(),
			trade.reward_amount
		], DIM_TEXT)
	elif trade.reward_item != null:
		_add_detail_line("REWARD: %s x%d" % [
			_human_name(trade.reward_item.item_id), trade.reward_item_amount
		], DIM_TEXT)

	_order_button.show()
	_order_button.text = "ORDER"
	var locking: ChallengeData = ChallengeManager.get_locking_challenge(trade)
	_order_button.disabled = locking != null or not ShopManager.can_trade(trade)
	if locking != null:
		_status.text = "LOCKED: %s" % ("Complete a hidden challenge" if locking.hidden else locking.display_name)
	elif _order_button.disabled:
		_status.text = "Not enough items to trade."


# Use the real ItemData sprite and the count from the existing inventory.
# Keep the readable name as a tooltip, rather than crowding the details panel.
func _make_requirement_row(requirement: TradeRequirement) -> Control:
	var have: int = ShopManager.count_item(requirement.item.item_id)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 60.0
	row.add_theme_constant_override("separation", 12)
	row.tooltip_text = _human_name(requirement.item.item_id)

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(60, 60)
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_frame)

	var icon := TextureRect.new()
	icon.texture = requirement.item.sprite
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(icon)

	var count := Label.new()
	count.theme_type_variation = &"TitleLabel"
	count.text = "%d / %d" % [have, requirement.amount]
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count.add_theme_color_override("font_color", DARK_TEXT if have >= requirement.amount else WARNING_TEXT)
	row.add_child(count)
	return row


func _show_storage_details(entry: Dictionary) -> void:
	var amount: int = int(entry.get("quantity", 0))
	_description.text = "In your storage. You can use these items for trades and gifts."
	_add_detail_line("IN STORAGE: %d" % amount, DARK_TEXT)


func _show_fish_details(fish: FishData) -> void:
	if not _has_discovered_fish(fish):
		_description.text = "Catch this fish to reveal its entry."
		_status.text = "NOT YET DISCOVERED"
		return
	_description.text = "A fish you have discovered."
	var total := 0
	for known in FishingManager.catch_lifetime:
		if known != null and known.fish_id == fish.fish_id:
			total += int(FishingManager.catch_lifetime[known])
	_add_detail_line("LIFETIME CATCHES: %d" % total, DARK_TEXT)


func _show_challenge_details(challenge: ChallengeData) -> void:
	var hidden := challenge.hidden and not challenge.completed
	if hidden:
		_description.text = "Keep fishing to reveal this challenge."
		_status.text = "HIDDEN CHALLENGE"
		return
	_description.text = challenge.description
	_add_detail_line("PROGRESS: %d / %d" % [challenge.progress, challenge.target_amount], DARK_TEXT)
	if challenge.reward_text != "":
		_add_detail_line("UNLOCK: " + challenge.reward_text, DIM_TEXT)
	_status.text = "COMPLETED" if challenge.completed else "IN PROGRESS"


func _add_detail_line(value: String, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	_costs.add_child(label)


func _human_name(id: StringName) -> String:
	return String(id).replace("_", " ").capitalize()


func _on_order_pressed() -> void:
	if _entries.is_empty() or _entries[_selected_index].get("kind") != "trade":
		return
	var trade: TradeData = _entries[_selected_index].get("ref") as TradeData
	if trade == null or not ShopManager.make_trade(trade):
		_refresh_page()
		_status.text = "Unable to place order."


func _on_trade_completed(trade: TradeData) -> void:
	if not visible:
		return
	var delivered_later := is_instance_valid(ShopManager.delivery_point)
	_delivery_status.text = "DELIVERY ORDERED" if delivered_later else "ORDER COMPLETE"
	_last_order_message = "ORDER PLACED: %s" % trade.display_name
	_refresh_page()


func _on_challenge_changed(_challenge: ChallengeData) -> void:
	if visible and _page == Page.CHALLENGES:
		_refresh_page()


func _on_challenge_reset() -> void:
	if visible and _page == Page.CHALLENGES:
		_refresh_page()


func _on_inventory_changed(_fish: Variant) -> void:
	if visible and (_page == Page.STORAGE or _page == Page.COLLECTION):
		_refresh_page()
