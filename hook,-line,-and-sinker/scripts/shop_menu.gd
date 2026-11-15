class_name ShopMenu
extends CanvasLayer

# FISH CO. terminal: shop, inventory and calendar pages share one scene.
# Tabs and borders are laid out in shop_menu.tscn and styled by terminal_theme.tres.
# This script only fills in the grid, item details, and actions.

enum Page { QUOTA, SHOP, STORAGE, COLLECTION, CHALLENGES, SCHEDULE }

const SLOT_SIZE := Vector2(168, 168) # 56 x 56 art pixels at 3x
const MIN_SLOTS := 12                 # Four columns, three visible rows
const LOCKED_TINT := Color(0.533, 0.57, 0.57, 0.82)
const UNAFFORD_TINT := Color(0.564, 0.099, 0.107, 0.82)
const DARK_TEXT := Color("17363b")
const DIM_TEXT := Color("45646a")
const WARNING_TEXT := Color("984b24")
# Art pixels are scaled x3. The visible part of each tab is 72 screen pixels.
# A further 24 screen pixels sit under the terminal panel.
const TAB_VISIBLE_WIDTH := 66.0
const TAB_CLOSED_HEIGHT := 78.0
const TAB_TEXT_PADDING := 12.0
const TAB_TEXT_GAP := 12.0

# Terminal boot sequence: horizontal expansion, vertical expansion, tabs emerge.
const BOOT_LINE := 36.0  # 12 art pixels; fits both 9-slice corner margins
const OPEN_HORIZONTAL_TIME := 0.20
const OPEN_VERTICAL_TIME := 0.26
const TABS_POP_TIME := 0.30
const TABS_HIDDEN_X_OFFSET := 12.0

@onready var _terminal_panel: PanelContainer = $TerminalRoot/Panel
@onready var _opening_frame: NinePatchRect = $TerminalRoot/OpeningFrame
@onready var _nav_tabs: VBoxContainer = $TerminalRoot/NavTabs

@onready var _quota_tab: Button = %QuotaTab
@onready var _shop_tab: Button = %ShopTab
@onready var _shop_categories: HBoxContainer = %ShopCategories
@onready var _shop_upgrades: Button = %ShopUpgrades
@onready var _shop_gifts: Button = %ShopGifts
@onready var _storage_tab: Button = %StorageTab
@onready var _collection_tab: Button = %CollectionTab
@onready var _challenges_tab: Button = %ChallengesTab
@onready var _schedule_tab: Button = %ScheduleTab
@onready var _preview_frame: PanelContainer = $TerminalRoot/Panel/Margin/Layout/Body/Details/PreviewFrame
@onready var _details_panel: VBoxContainer = $TerminalRoot/Panel/Margin/Layout/Body/Details

@onready var _delivery_status: Label = %DeliveryStatus
@onready var _page_title: Label = %PageTitle
@onready var _page_hint: Label = %PageHint
@onready var _grid: GridContainer = %ItemGrid
@onready var _grid_scroll: ScrollContainer = $TerminalRoot/Panel/Margin/Layout/Body/Left/GridScroll
@onready var _schedule_days: HBoxContainer = %ScheduleDays
@onready var _quota_view: VBoxContainer = %QuotaView
@onready var _preview: TextureRect = %PreviewIcon
@onready var _item_name: Label = %ItemName
@onready var _description: Label = %DescriptionLabel
@onready var _costs: VBoxContainer = %Costs
@onready var _status: Label = %StatusLabel
@onready var _order_button: Button = %OrderButton
@onready var _page_indicator: Label = %PageIndicator
@onready var _close_button: Button = %CloseButton

var _nav_buttons: Array[Button] = []
var _page: int = Page.QUOTA
var _entries: Array[Dictionary] = []
var _entry_buttons: Array[Button] = []
var _selected_index: int = 0
var _shop_section: int = 0  # 0 upgrades, 1 gifts
var _button_group := ButtonGroup.new()
var _last_order_message := ""
var _challenge_notification: PanelContainer
var _tab_tween: Tween
var _boot_tween: Tween
var _tabs_pop_tween: Tween
var _nav_rest_x: float = 0.0
const SCHEDULE_DAYS: int = 4
# Calendar-specific whitespace, using multiples of the game's 3x art-pixel grid.
const SCHEDULE_COLUMN_GAP: int = 12
const SCHEDULE_DAY_PADDING: int = 9
const SCHEDULE_SECTION_GAP: int = 15
const SCHEDULE_HEADER_GAP: int = 5
const SCHEDULE_ACTION_HEIGHT: int = 42
const SCHEDULE_TODAY_STRETCH: float = 1.45
const SCHEDULE_ACTION_LINE_COLOR := Color(0.11, 0.35, 0.37, 0.24)
const SCHEDULE_PERIOD_LINE_COLOR := Color(0.11, 0.35, 0.37, 0.48)
const TERMINAL_FRAME: StyleBoxTexture = preload("res://resources/ui/terminal_border.tres")
var _schedule_day: int = -1
var _schedule_period: int = 0
var _schedule_action: int = 0


func _ready() -> void:
	hide()
	add_to_group(&"modal_ui")
	_nav_rest_x = _nav_tabs.position.x
	_terminal_panel.hide()
	_nav_tabs.hide()
	_opening_frame.hide()
	_nav_buttons = [_quota_tab, _shop_tab, _storage_tab, _collection_tab, _challenges_tab, _schedule_tab]
	for i in range(_nav_buttons.size()):
		_nav_buttons[i].pressed.connect(_select_page.bind(i))

	_shop_upgrades.pressed.connect(_select_shop_section.bind(0))
	_shop_gifts.pressed.connect(_select_shop_section.bind(1))
	_order_button.pressed.connect(_on_order_pressed)
	_close_button.pressed.connect(close)
	ShopManager.shop_requested.connect(open)
	ShopManager.trade_completed.connect(_on_trade_completed)
	ShopManager.upgrade_state_changed.connect(_on_upgrade_state_changed)
	ChallengeManager.challenge_progressed.connect(_on_challenge_changed)
	ChallengeManager.challenge_completed.connect(_on_challenge_changed)
	ChallengeManager.challenge_claimed.connect(_on_challenge_changed)
	ChallengeManager.progress_reset.connect(_on_challenge_reset)
	FishingManager.storage_changed.connect(_on_inventory_changed)
	FishingManager.fish_caught.connect(_on_inventory_changed)  # collection/dex, incl. NPC catches
	DateManager.bookings_changed.connect(_on_schedule_changed)
	QuotaManager.quota_changed.connect(_on_quota_changed)
	GameManager.time_changed.connect(func(_day: int, _period: GameManager.Times) -> void: _on_schedule_changed())
	GameManager.actions_changed.connect(func(_actions: int) -> void: _on_schedule_changed())
	_setup_challenge_notification()
	_refresh_page()
	_update_nav_tabs(false)


func _setup_challenge_notification() -> void:
	_challenge_notification = PanelContainer.new()
	_challenge_notification.name = "ChallengeNoticeBubble"
	_challenge_notification.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_challenge_notification.custom_minimum_size = Vector2(36, 36)
	_challenge_notification.position = Vector2(51, 6)
	_challenge_notification.add_theme_stylebox_override("panel", TERMINAL_FRAME)
	var notice_label := Label.new()
	notice_label.text = "!"
	notice_label.theme_type_variation = &"TitleLabel"
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_challenge_notification.add_child(notice_label)
	_challenges_tab.add_child(_challenge_notification)
	_update_challenge_notification()


func _update_challenge_notification() -> void:
	if is_instance_valid(_challenge_notification):
		_challenge_notification.visible = ChallengeManager.get_claimable_count() > 0


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	_page = Page.QUOTA
	_shop_section = 0
	_selected_index = 0
	_last_order_message = ""
	_delivery_status.text = "NO DELIVERIES"
	show()
	ShopManager.set_shop_open(true)
	_refresh_page()
	_update_nav_tabs(false)
	_start_open_animation()


func close() -> void:
	if not visible:
		return
	_cancel_open_animation()
	_terminal_panel.hide()
	_nav_tabs.hide()
	_opening_frame.hide()
	_nav_tabs.position.x = _nav_rest_x
	hide()
	# ShopInteractable dispatches queued deliveries when this fires.
	ShopManager.set_shop_open(false)



# The visible 9-slice frame animates on its own, so item grids/buttons keep
# their real sizes. Only reveal the fully laid out terminal after the frame grows.
func _start_open_animation() -> void:
	_cancel_open_animation()
	_terminal_panel.hide()
	_nav_tabs.hide()
	_opening_frame.show()

	var end_position: Vector2 = _terminal_panel.position
	var end_size: Vector2 = _terminal_panel.size
	var center: Vector2 = end_position + end_size * 0.5

	_opening_frame.size = Vector2(BOOT_LINE, BOOT_LINE)
	_opening_frame.position = center - _opening_frame.size * 0.5

	_boot_tween = create_tween()
	_boot_tween.set_trans(Tween.TRANS_CUBIC)
	_boot_tween.set_ease(Tween.EASE_OUT)
	# 1. Expand from the center to the full horizontal width.
	_boot_tween.tween_property(_opening_frame, "size:x", end_size.x, OPEN_HORIZONTAL_TIME)
	_boot_tween.parallel().tween_property(
		_opening_frame, "position:x", end_position.x, OPEN_HORIZONTAL_TIME
	)
	# 2. Then grow vertically, preserving the top/bottom 9-slice corners.
	_boot_tween.tween_property(_opening_frame, "size:y", end_size.y, OPEN_VERTICAL_TIME)
	_boot_tween.parallel().tween_property(
		_opening_frame, "position:y", end_position.y, OPEN_VERTICAL_TIME
	)
	_boot_tween.tween_callback(_on_frame_opened)


func _on_frame_opened() -> void:
	if not visible:
		return
	_opening_frame.hide()
	_terminal_panel.show()

	# 3. Side tabs slide out from behind the main panel with a little bounce.
	# NavTabs precedes Panel in the scene tree, so the panel covers their
	# right-hand (hidden) portions as they emerge.
	_nav_tabs.position.x = _terminal_panel.position.x + TABS_HIDDEN_X_OFFSET
	_nav_tabs.show()
	_tabs_pop_tween = create_tween()
	_tabs_pop_tween.tween_property(
		_nav_tabs, "position:x", _nav_rest_x, TABS_POP_TIME
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tabs_pop_tween.tween_callback(_on_tabs_opened)


func _on_tabs_opened() -> void:
	if visible:
		_quota_tab.grab_focus()


func _cancel_open_animation() -> void:
	if _boot_tween != null and _boot_tween.is_running():
		_boot_tween.kill()
	if _tabs_pop_tween != null and _tabs_pop_tween.is_running():
		_tabs_pop_tween.kill()


func _has_recruited_npc() -> bool:
	for state in NPCManager.npc_states.values():
		if state.get("flags", {}).get(&"Recruited", false):
			return true
	return false


func _select_shop_section(section: int) -> void:
	if section == 1 and not _has_recruited_npc():
		return
	_shop_section = section
	_selected_index = 0
	_refresh_page()


func _select_page(page: int) -> void:
	_page = page
	_selected_index = 0
	_last_order_message = ""
	if page == Page.SCHEDULE:
		_select_default_schedule_slot()
	_refresh_page()
	_update_nav_tabs(true)
	if not _entry_buttons.is_empty():
		_entry_buttons[0].grab_focus()


# The active icon-tab unfolds downwards to fit its exact caption.
# Rotate the title counterclockwise and center it in the exposed tab area.
# Labels and icons are scene nodes, so their art remains Inspector-editable.
func _update_nav_tabs(animate: bool) -> void:
	if _tab_tween != null and _tab_tween.is_running():
		_tab_tween.kill()

	if animate:
		_tab_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	for i in range(_nav_buttons.size()):
		var tab: Button = _nav_buttons[i]
		var caption: Label = tab.get_node("VerticalTitle") as Label
		var text_width: float = _layout_vertical_caption(caption)
		var padded_height: float = TAB_CLOSED_HEIGHT + TAB_TEXT_GAP + text_width + TAB_TEXT_PADDING
		# Round to the game's 3x pixel-art grid.
		var expanded_height: float = ceil(padded_height / float(PixelUI.SCALE)) * float(PixelUI.SCALE)
		var target_height: float = expanded_height if i == _page else TAB_CLOSED_HEIGHT
		var target_alpha: float = 1.0 if i == _page else 0.0

		if animate:
			_tab_tween.tween_property(tab, "custom_minimum_size:y", target_height, 0.23)
			_tab_tween.tween_property(caption, "modulate:a", target_alpha, 0.15)
		else:
			tab.custom_minimum_size.y = target_height
			caption.modulate.a = target_alpha


func _layout_vertical_caption(caption: Label) -> float:
	var font: Font = caption.get_theme_font("font")
	var font_size: int = caption.get_theme_font_size("font_size")
	var text_width: float = ceil(font.get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var text_height: float = ceil(font.get_height(font_size))

	# A -90 degree rotation displays the word bottom-to-top.
	# Rotating around its top-left means the resulting bounds are:
	# x = [position.x, position.x + text_height]
	# y = [position.y - text_width, position.y]
	caption.rotation = -PI / 2.0
	caption.pivot_offset = Vector2.ZERO
	caption.size = Vector2(text_width, text_height)
	caption.position = Vector2(
		round((TAB_VISIBLE_WIDTH - text_height) / 2.0),
		TAB_CLOSED_HEIGHT + TAB_TEXT_GAP + text_width
	)
	return text_width


func _refresh_page() -> void:
	_entries.clear()
	if _page == Page.SCHEDULE:
		_refresh_schedule_page()
		return
	if _page == Page.QUOTA:
		_refresh_quota_page()
		return
	_quota_view.hide()
	_shop_categories.visible = _page == Page.SHOP
	_shop_gifts.visible = _has_recruited_npc()
	if _shop_section == 1 and not _shop_gifts.visible:
		_shop_section = 0
	_shop_upgrades.set_pressed_no_signal(_shop_section == 0)
	_shop_gifts.set_pressed_no_signal(_shop_section == 1)
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid_scroll.show()
	_schedule_days.hide()
	_page_title.show()
	_page_hint.show()
	_details_panel.custom_minimum_size.x = 500
	_preview_frame.show()
	match _page:
		Page.SHOP:
			_collect_trades()
		Page.STORAGE:
			_collect_storage()
		Page.COLLECTION:
			_collect_fish()
		Page.CHALLENGES:
			_collect_challenges()

	var names := ["QUOTA", "SHOP", "STORAGE", "COLLECTION", "CHALLENGES"]
	var explanations := [
		"Mandatory weekly fish deliveries",
		"Fishing improvements and gifts",
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


# ---- Mandatory weekly fish quota ---------------------------------------

func _refresh_quota_page() -> void:
	_grid_scroll.hide()
	_schedule_days.hide()
	_shop_categories.hide()
	_quota_view.show()
	_entry_buttons.clear()
	_preview_frame.hide()
	_page_title.show()
	_page_hint.show()
	_details_panel.custom_minimum_size.x = 420
	_page_title.text = "WEEK %d QUOTA" % QuotaManager.week
	_page_hint.text = "Deliver fish by the end of Day %d (Night)" % QuotaManager.deadline_day
	_page_indicator.text = "FISH CO.  /  MANDATORY WEEKLY CONTRACT"
	for i in range(_nav_buttons.size()):
		_nav_buttons[i].button_pressed = i == _page
		_nav_buttons[i].self_modulate = Color.WHITE if i == _page else Color(0.88, 0.9, 0.9, 0.9)
	for child in _quota_view.get_children():
		_quota_view.remove_child(child)
		child.queue_free()
	for child in _costs.get_children():
		_costs.remove_child(child)
		child.queue_free()
	_order_button.hide()
	_preview.texture = null
	_item_name.text = "FISH CO. CONTRACT"
	_description.text = "Fish are surrendered as soon as you submit them. They cannot also be used for gifts or upgrades."
	var is_done: bool = QuotaManager.is_complete()
	_status.text = "QUOTA COMPLETE / NEXT CONTRACT STARTS DAY %d" % (QuotaManager.deadline_day + 1) if is_done else (
		"FAILURE TO DELIVER BY DAY %d ENDS THE RUN" % QuotaManager.deadline_day
	)
	if is_done:
		var complete := PixelUI.label("DELIVERY REQUIREMENTS MET", &"TitleLabel")
		complete.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_quota_view.add_child(complete)

	for requirement in QuotaManager.requirements:
		var item_id: StringName = requirement["item_id"]
		var amount: int = int(requirement["target"])
		var current: int = QuotaManager.get_delivered(item_id)
		var available: int = FishingManager.count_in_storage(item_id)
		var remaining: int = QuotaManager.get_remaining(item_id)

		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", TERMINAL_FRAME)
		_quota_view.add_child(frame)
		var padding := MarginContainer.new()
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			padding.add_theme_constant_override(side, 12)
		frame.add_child(padding)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 10)
		padding.add_child(body)
		var header := HBoxContainer.new()
		body.add_child(header)
		var title := PixelUI.label(str(requirement["label"]).to_upper(), &"TitleLabel")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var progress := PixelUI.label("%d / %d" % [current, amount], &"TitleLabel")
		header.add_child(progress)

		var bar := ProgressBar.new()
		bar.max_value = amount
		bar.value = current
		bar.show_percentage = false
		bar.custom_minimum_size.y = 18
		bar.add_theme_stylebox_override("background", PixelUI.box(PixelUI.INSET, PixelUI.ROW_EDGE, 1))
		bar.add_theme_stylebox_override("fill", PixelUI.box(PixelUI.CYAN_DARK, PixelUI.CYAN, 1))
		body.add_child(bar)

		var submit_row := HBoxContainer.new()
		body.add_child(submit_row)
		var available_label := PixelUI.label("%d IN STORAGE" % available, &"DimLabel")
		available_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		submit_row.add_child(available_label)
		var take: int = mini(available, remaining)
		var send := Button.new()
		send.text = "DELIVER %d" % take if take > 0 else ("FULFILLED" if remaining == 0 else "NO FISH")
		send.disabled = take <= 0 or is_done
		send.custom_minimum_size.x = 168
		send.pressed.connect(_submit_quota_fish.bind(item_id))
		submit_row.add_child(send)


func _submit_quota_fish(item_id: StringName) -> void:
	var sent: int = QuotaManager.submit(item_id)
	if sent == 0:
		_status.text = "NO ELIGIBLE FISH TO SUBMIT"
	else:
		_last_order_message = "DELIVERED %d FISH TO FISH CO." % sent
		# Stock removal also signals the shared inventory; rebuild after it.
		_refresh_quota_page.call_deferred()


# ---- Schedule / calendar (view-only; book dates by talking to NPCs) -----

func _on_quota_changed() -> void:
	if not visible:
		return
	if _page == Page.QUOTA:
		_refresh_quota_page.call_deferred()
	elif _page == Page.SCHEDULE:
		_refresh_schedule_page.call_deferred()


func _on_schedule_changed() -> void:
	if visible and _page == Page.SCHEDULE:
		if _schedule_day < GameManager.get_day() or _schedule_day >= GameManager.get_day() + SCHEDULE_DAYS:
			_select_default_schedule_slot()
		_refresh_schedule_page()


func _select_default_schedule_slot() -> void:
	_schedule_day = GameManager.get_day()
	_schedule_period = GameManager.get_period()
	_schedule_action = mini(
		GameManager.ACTIONS_PER_PERIOD - GameManager.get_actions_left(),
		GameManager.ACTIONS_PER_PERIOD - 1
	)


func _get_schedule_booking(day: int, period: int) -> DateData:
	for date_id in DateManager.bookings:
		var slot: Dictionary = DateManager.bookings[date_id]
		if int(slot["day"]) == day and int(slot["period"]) == period:
			return DateManager.get_date(date_id)
	return null


func _select_schedule_slot(day: int, period: int, action: int) -> void:
	_schedule_day = day
	_schedule_period = period
	_schedule_action = action
	_refresh_schedule_page()


func _schedule_action_has_passed(day: int, period: int, action: int) -> bool:
	if day < GameManager.get_day():
		return true
	if day > GameManager.get_day():
		return false
	if period < GameManager.get_period():
		return true
	if period > GameManager.get_period():
		return false
	return action < GameManager.ACTIONS_PER_PERIOD - GameManager.get_actions_left()


func _schedule_action_is_now(day: int, period: int, action: int) -> bool:
	return day == GameManager.get_day() \
		and period == GameManager.get_period() \
		and action == GameManager.ACTIONS_PER_PERIOD - GameManager.get_actions_left() \
		and GameManager.can_act()


func _schedule_slot_is_quota_deadline(day: int, period: int, action: int) -> bool:
	return day == QuotaManager.deadline_day \
		and period == GameManager.Times.NIGHT \
		and action == GameManager.ACTIONS_PER_PERIOD - 1


func _refresh_schedule_page() -> void:
	_quota_view.hide()
	_shop_categories.hide()
	# Four days in a fixed horizontal layout, NOT inside the shop scroll view.
	# Today has extra width; strong nine-slice outlines frame each day, while
	# subtle rules separate actions and periods within the day.
	_grid_scroll.hide()
	_schedule_days.show()
	_schedule_days.add_theme_constant_override("separation", SCHEDULE_COLUMN_GAP)
	_page_title.hide()
	_page_hint.hide()
	_details_panel.custom_minimum_size.x = 420
	_preview_frame.hide()
	_page_indicator.text = "SCHEDULE  /  BOOK DATES BY TALKING TO NPCS"

	for i in range(_nav_buttons.size()):
		_nav_buttons[i].button_pressed = i == _page
		_nav_buttons[i].self_modulate = Color.WHITE if i == _page else Color(0.88, 0.9, 0.9, 0.9)

	for child in _schedule_days.get_children():
		_schedule_days.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()

	var plain_row := StyleBoxEmpty.new()
	var row_hover := StyleBoxFlat.new()
	row_hover.bg_color = Color(0.11, 0.35, 0.37, 0.12)
	var row_pressed := StyleBoxFlat.new()
	row_pressed.bg_color = Color(0.11, 0.35, 0.37, 0.20)

	for day_offset in SCHEDULE_DAYS:
		var day := GameManager.get_day() + day_offset
		var day_panel := PanelContainer.new()
		day_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		day_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		day_panel.size_flags_stretch_ratio = SCHEDULE_TODAY_STRETCH if day_offset == 0 else 1.0
		# Stronger outer border, using the same authored terminal 9-slice.
		day_panel.add_theme_stylebox_override("panel", TERMINAL_FRAME)
		_schedule_days.add_child(day_panel)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", SCHEDULE_DAY_PADDING)
		margin.add_theme_constant_override("margin_right", SCHEDULE_DAY_PADDING)
		margin.add_theme_constant_override("margin_top", SCHEDULE_DAY_PADDING)
		margin.add_theme_constant_override("margin_bottom", SCHEDULE_DAY_PADDING)
		day_panel.add_child(margin)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", SCHEDULE_SECTION_GAP)
		margin.add_child(column)

		var day_title := Label.new()
		day_title.theme_type_variation = &"TitleLabel"
		day_title.text = "DAY %d%s" % [day, "  /  TODAY" if day_offset == 0 else ""]
		day_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if day_offset == 0:
			day_title.add_theme_color_override("font_color", Color("0e666b"))
		column.add_child(day_title)

		for period in GameManager.Times.size():
			var section := VBoxContainer.new()
			section.add_theme_constant_override("separation", SCHEDULE_HEADER_GAP)
			column.add_child(section)

			if period > 0:
				var period_rule := ColorRect.new()
				period_rule.custom_minimum_size.y = 2
				period_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
				period_rule.color = SCHEDULE_PERIOD_LINE_COLOR
				section.add_child(period_rule)

			var heading := Label.new()
			heading.theme_type_variation = &"TitleLabel"
			heading.text = GameManager.get_period_name(period as GameManager.Times).to_upper()
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			section.add_child(heading)

			var actions := VBoxContainer.new()
			actions.add_theme_constant_override("separation", 0)
			section.add_child(actions)
			var booking := _get_schedule_booking(day, period)

			for action in GameManager.ACTIONS_PER_PERIOD:
				if action > 0:
					var action_rule := ColorRect.new()
					action_rule.custom_minimum_size.y = 1
					action_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
					action_rule.color = SCHEDULE_ACTION_LINE_COLOR
					actions.add_child(action_rule)

				var action_tile := Button.new()
				action_tile.custom_minimum_size.y = SCHEDULE_ACTION_HEIGHT
				action_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				action_tile.toggle_mode = true
				action_tile.clip_text = true
				action_tile.alignment = HORIZONTAL_ALIGNMENT_CENTER
				action_tile.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				# No box border on individual actions; their separation is
				# the thin line above each subsequent row.
				action_tile.add_theme_stylebox_override("normal", plain_row)
				action_tile.add_theme_stylebox_override("disabled", plain_row)
				action_tile.add_theme_stylebox_override("focus", plain_row)
				action_tile.add_theme_stylebox_override("hover", row_hover)
				action_tile.add_theme_stylebox_override("pressed", row_pressed)
				action_tile.add_theme_stylebox_override("hover_pressed", row_pressed)

				var is_now := _schedule_action_is_now(day, period, action)
				var is_spent := _schedule_action_has_passed(day, period, action)
				var quota_due := _schedule_slot_is_quota_deadline(day, period, action)
				var marker := ">" if is_now else ("x" if is_spent else " ")
				var event_text := " --"
				if booking != null:
					if action == 0:
						var short_name := booking.npc.display_name.to_upper().substr(0, 7) if booking.npc != null else "DATE"
						event_text = " ♥ " + short_name
					else:
						event_text = " · DATE"
					action_tile.tooltip_text = "%s - Day %d %s (all 3 actions)" % [
						booking.display_name, day, GameManager.get_period_name(period as GameManager.Times)
					]
				if quota_due:
					event_text = " ✓ QUOTA" if QuotaManager.is_complete() else " ! QUOTA"
					action_tile.tooltip_text = (
						"Weekly quota fulfilled" if QuotaManager.is_complete()
						else "FISH CO. quota deadline — end of Day %d" % day
					)
				action_tile.text = "%s %d%s" % [marker, action + 1, event_text]
				if quota_due:
					action_tile.self_modulate = (
						Color(0.78, 1.0, 0.86, 1.0) if QuotaManager.is_complete()
						else Color(1.0, 0.78, 0.62, 1.0)
					)
				elif booking != null:
					action_tile.self_modulate = Color(0.96, 0.78, 0.83, 1.0)
				elif is_spent:
					action_tile.self_modulate = Color(0.65, 0.71, 0.71, 0.82)
				elif is_now:
					action_tile.self_modulate = Color(0.72, 0.98, 0.93, 1.0)
				action_tile.set_pressed_no_signal(
					day == _schedule_day and period == _schedule_period and action == _schedule_action
				)
				action_tile.pressed.connect(_select_schedule_slot.bind(day, period, action))
				actions.add_child(action_tile)

	_refresh_schedule_details()

func _refresh_schedule_details() -> void:
	for child in _costs.get_children():
		_costs.remove_child(child)
		child.queue_free()
	_preview.texture = null
	_order_button.hide()
	_status.text = ""
	var day := _schedule_day
	var period := _schedule_period
	if day < GameManager.get_day() or day >= GameManager.get_day() + SCHEDULE_DAYS:
		_select_default_schedule_slot()
		day = _schedule_day
		period = _schedule_period
	_item_name.text = "DAY %d - %s" % [day, GameManager.get_period_name(period as GameManager.Times).to_upper()]
	var date := _get_schedule_booking(day, period)
	var quota_deadline := _schedule_slot_is_quota_deadline(day, period, _schedule_action)
	var quota_note := "FISH CO. quota fulfilled." if QuotaManager.is_complete() else "FISH CO. quota due tonight."
	if date == null:
		_description.text = quota_note if quota_deadline else "Nothing scheduled."
		return
	var npc_name := date.npc.display_name if date.npc != null else "your date"
	# Date display names currently include the partner (e.g. "Beach date with
	# Silas"), so strip the suffix to avoid saying their name twice.
	var date_type := date.display_name.trim_suffix(" with " + npc_name).to_lower()
	_description.text = "Scheduled a %s with %s." % [date_type, npc_name]
	if quota_deadline:
		_description.text += "\n" + quota_note


func _collect_trades() -> void:
	for trade in ShopManager.trades:
		if trade == null:
			continue
		var is_upgrade := trade.reward_method != &""
		var is_gift := trade.reward_item != null and not is_upgrade
		if _page == Page.SHOP and ((_shop_section == 0 and is_upgrade) or (_shop_section == 1 and is_gift and _has_recruited_npc())):
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
			"locked": hidden,
			"claimable": challenge.completed and not challenge.claimed
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

	if bool(entry.get("claimable", false)):
		var claim_badge := Label.new()
		claim_badge.text = "!"
		claim_badge.theme_type_variation = &"TitleLabel"
		claim_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		claim_badge.position = Vector2(SLOT_SIZE.x - 33, 9)
		tile.add_child(claim_badge)
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
	_description.text = trade.description if not trade.description.is_empty() else ("Fishing equipment upgrade." if trade.reward_method != &"" else "A present for someone in town.")
	_add_detail_line("REQUIRES:", DIM_TEXT)
	# Sprite + actual owned/required counts, one row per required fish.
	for requirement in trade.requirements:
		if requirement == null or requirement.item == null:
			continue
		_costs.add_child(_make_requirement_row(requirement))

	if trade.reward_method != &"":
		if trade.one_time_purchase:
			_add_detail_line("ONE-TIME UPGRADE", DIM_TEXT)
		else:
			_add_detail_line("REWARD: %s +%d" % [
				String(trade.reward_method).trim_prefix("shop_reward_").replace("_", " ").to_upper(),
				trade.reward_amount
			], DIM_TEXT)
	elif trade.reward_item != null:
		_add_detail_line("REWARD: %s x%d" % [
			_human_name(trade.reward_item.item_id), trade.reward_item_amount
		], DIM_TEXT)

	_order_button.show()
	_order_button.self_modulate = Color.WHITE
	_order_button.text = "ORDER"
	var locking: ChallengeData = ChallengeManager.get_locking_challenge(trade)
	_order_button.disabled = locking != null or not ShopManager.can_trade(trade)
	if ShopManager.is_upgrade_owned(trade):
		_status.text = "OWNED"
		_order_button.text = "OWNED"
	elif ShopManager.is_upgrade_ordered(trade):
		_status.text = "DELIVERY ORDERED"
		_order_button.text = "ORDERED"
	elif locking != null:
		_status.text = ("CLAIM CHALLENGE: " if locking.completed else "LOCKED: ") + (
			"Hidden challenge" if locking.hidden and not locking.completed else locking.display_name
		)
		_order_button.self_modulate = UNAFFORD_TINT
	elif _order_button.disabled:
		_status.text = "Not enough items to trade."
		if trade.one_time_purchase and ShopManager.upgrades_today >= ShopManager.max_daily_upgrades:
			_status.text = "Maximum daily upgrades reached."
		_order_button.self_modulate = UNAFFORD_TINT


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
	if challenge.completed and not challenge.claimed:
		_status.text = "READY TO CLAIM"
		_order_button.show()
		_order_button.disabled = false
		_order_button.text = "CLAIM REWARD"
	elif challenge.claimed:
		_status.text = "REWARD CLAIMED"
	else:
		_status.text = "IN PROGRESS"


func _add_detail_line(value: String, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	_costs.add_child(label)


func _human_name(id: StringName) -> String:
	return String(id).replace("_", " ").capitalize()


func _on_order_pressed() -> void:
	if _entries.is_empty():
		return
	if _entries[_selected_index].get("kind") == "challenge":
		var achievement := _entries[_selected_index].get("ref") as ChallengeData
		if ChallengeManager.claim(achievement):
			_last_order_message = "CLAIMED: %s" % achievement.display_name
			_refresh_page()
		return
	if _entries[_selected_index].get("kind") != "trade":
		return
	var trade: TradeData = _entries[_selected_index].get("ref") as TradeData
	if trade == null or not ShopManager.make_trade(trade):
		_refresh_page()
		_status.text = "Unable to place order."


func _on_upgrade_state_changed(_trade: TradeData) -> void:
	if visible and _page == Page.SHOP:
		_refresh_page()


func _on_trade_completed(trade: TradeData) -> void:
	if not visible:
		return
	var delivered_later := ShopManager.has_delivery_point()
	_delivery_status.text = "DELIVERY ORDERED" if delivered_later else "ORDER COMPLETE"
	_last_order_message = "ORDER PLACED: %s" % trade.display_name
	_refresh_page()


func _on_challenge_changed(_challenge: ChallengeData) -> void:
	_update_challenge_notification()
	if visible and (_page == Page.CHALLENGES or _page == Page.SHOP):
		_refresh_page()


func _on_challenge_reset() -> void:
	_update_challenge_notification()
	if visible and (_page == Page.CHALLENGES or _page == Page.SHOP):
		_refresh_page()


func _on_inventory_changed(_fish: Variant = null) -> void:
	if not visible:
		return
	if _page == Page.QUOTA:
		_refresh_quota_page.call_deferred()
	elif _page == Page.SHOP or _page == Page.STORAGE or _page == Page.COLLECTION:
		_refresh_page()
