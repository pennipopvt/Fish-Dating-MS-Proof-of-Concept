extends CanvasLayer

# Debug-only developer panel (autoload "DevPanel"). Removed in release builds.
#   F9  open / close the panel
#   F5  end the current conversation immediately (no further effects)
# Everything here goes through the managers' public functions or writes their
# runtime state from outside; no gameplay script depends on this panel.

const SILAS_ID: StringName = &"test_npc"
const SILAS_NPC_PATH := "res://resources/npcs/test_npc.tres"
const SILAS_FISH_PATH := "res://resources/fish/test_silas.tres"
const SPYGLASS_PATH := "res://resources/items/spyglass.tres"
const ITEMS_DIR := "res://resources/items/"
const FISH_DIR := "res://resources/fish/"
const DIALOGUE_DIR := "res://dialogue/"
const FISHING_STATES := ["NOT", "WAITING", "FISHING", "CATCHING"]
const REFRESH_INTERVAL := 0.25
const PANEL_WIDTH := 1080.0

var _panel: PanelContainer
var _tabs: TabContainer
var _status: Label
var _info: RichTextLabel
var _progress_box: VBoxContainer
var _flags_box: VBoxContainer
var _flag_npc: OptionButton
var _fishing_status: Label
var _force_fish: OptionButton
var _json_picker: OptionButton
var _reset_all_button: Button

var _refresh_time: float = 0.0
var _defaults: Dictionary = {}
var _fish_options: Array[FishData] = []
var _forced_fish: FishData = null
var _last_fishing_state: int = -1
var _reset_armed: bool = false


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	# While open, GameManager.is_modal_ui_open() pauses player actions.
	add_to_group(&"modal_ui")
	_capture_defaults()
	_build_ui()
	hide()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(&"debug_panel"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_skip_dialogue"):
		skip_dialogue()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_apply_forced_fish()
	if not visible:
		return
	_refresh_time -= delta
	if _refresh_time <= 0.0:
		_refresh_time = REFRESH_INTERVAL
		_refresh_current_tab()


func toggle() -> void:
	visible = not visible
	_reset_armed = false
	_update_reset_button()
	if visible:
		_refresh_time = 0.0
		_rebuild_progress()
		_rebuild_flags()


func skip_dialogue() -> void:
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
		_say("Dialogue ended (F5)")


# ---- Lookups -------------------------------------------------------------

func _player() -> Player:
	return get_tree().get_first_node_in_group(&"player") as Player


func _controller() -> Node:
	var player := _player()
	return player.fishing_controller if player != null else null


func _world() -> Node:
	var player := _player()
	return player.get_parent() if player != null else null


func _silas_data() -> NPCData:
	return load(SILAS_NPC_PATH) as NPCData


func _find_silas() -> NPCInteractable:
	var world := _world()
	if world == null:
		return null
	for node in world.find_children("*", "", true, false):
		var npc := node as NPCInteractable
		if npc != null and npc.npc != null and npc.npc.npc_id == SILAS_ID and not npc.is_queued_for_deletion():
			return npc
	return null


static func _list_resources(dir: String) -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres") and not paths.has(dir + name):
			paths.append(dir + name)
	paths.sort()
	return paths


static func _list_dialogue() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(DIALOGUE_DIR):
		if file.ends_with(".json"):
			paths.append(DIALOGUE_DIR + file)
	paths.sort()
	return paths


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
	print("[DEV] ", text)


# ---- Silas checkpoints ---------------------------------------------------

func _set_npc_flags(npc_id: StringName, flag_ids: Array[StringName]) -> void:
	var flags: Dictionary = NPCManager.get_npc_state(npc_id)["flags"]
	flags.clear()
	for id in flag_ids:
		flags[id] = true


func _spawn_silas(in_house: bool) -> NPCInteractable:
	var world := _world()
	var controller := _controller()
	if world == null or controller == null:
		_say("No player in the scene")
		return null
	var silas := _find_silas()
	if silas == null:
		var fish := load(SILAS_FISH_PATH) as FishData
		if fish == null or fish.npc_data == null:
			_say("Silas fish/NPC scene missing")
			return null
		silas = fish.npc_data.instantiate() as NPCInteractable
		world.add_child(silas)
		silas.global_position = controller.npc_landing_point.global_position
		silas.z_index = 12
		var sprite := silas.get_node_or_null("Sprite") as AnimatedSprite2D
		if sprite != null:
			sprite.play(&"default")
	var on_dock: bool = silas.global_position.distance_to(controller.npc_landing_point.global_position) < 4.0
	if in_house and on_dock:
		if RecruitmentHandler.available_homes.is_empty():
			_say("No free house left; Silas stays on the dock")
		else:
			RecruitmentHandler.npc = silas
			RecruitmentHandler.house_recruit(silas.npc.house)
			RecruitmentHandler.npc = null
	return silas


# Close the panel and any conversation, then talk to Silas as the player would.
func _talk_to(silas: NPCInteractable) -> void:
	hide()
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	# DialogueUI closes itself on its next frame; wait before reopening it.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(silas):
		silas.interact(_player())


func _checkpoint(id: String) -> void:
	RecruitmentHandler.listening = false
	match id:
		"not_caught":
			if DialogueManager.is_active:
				DialogueManager.end_conversation()
			NPCManager.npc_states.erase(SILAS_ID)
			RecruitmentHandler.npc = null
			_say("Silas reset to not caught; reloading the world")
			# A reload restores the houses and removes the spawned Silas.
			get_tree().reload_current_scene()
		"just_caught":
			_set_npc_flags(SILAS_ID, [])
			var silas := _spawn_silas(false)
			if silas == null:
				return
			RecruitmentHandler.engage_listen(silas)
			_say("Silas just caught: recruitment dialogue")
			_talk_to(silas)
		"recruited":
			_set_npc_flags(SILAS_ID, [&"Recruited"])
			var silas := _spawn_silas(true)
			if silas != null:
				_say("Silas recruited: casual dialogue")
				_talk_to(silas)
		"spyglass":
			_set_npc_flags(SILAS_ID, [&"Recruited"])
			var silas := _spawn_silas(true)
			_give_to_hands(load(SPYGLASS_PATH) as ItemData)
			if silas != null:
				_say("Holding the spyglass: gift dialogue")
				_talk_to(silas)
		"invitation":
			_set_npc_flags(SILAS_ID, [&"Recruited", &"spyglass_complete"])
			var silas := _spawn_silas(true)
			if silas != null:
				_say("Spyglass given: invitation dialogue")
				_talk_to(silas)
		"house_scene":
			_set_npc_flags(SILAS_ID, [&"Recruited", &"spyglass_complete", &"house_invitation_accepted"])
			_spawn_silas(true)
			hide()
			if DialogueManager.is_active:
				DialogueManager.end_conversation()
			_say("Starting the silas_house scene")
			DialogueManager.scene_requested.emit(_silas_data(), "silas_house")
		"route_complete":
			_set_npc_flags(SILAS_ID, [&"Recruited", &"spyglass_complete", &"house_invitation_accepted", &"silas_route_complete"])
			_spawn_silas(true)
			BobberManager.unlock_bobber(&"silas")
			_say("Silas route complete; Silas bobber unlocked")


func _play_json(path: String) -> void:
	hide()
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await get_tree().process_frame
	await get_tree().process_frame
	DialogueManager.request_conversation(_silas_data(), path)
	_say(("Playing " if DialogueManager.is_active else "Could not start ") + path.get_file())


# ---- Items ---------------------------------------------------------------

func _give_to_hands(item: ItemData) -> void:
	var player := _player()
	if player == null or item == null:
		return
	if player.held_item != null:
		player.remove_held_item()
	player.take_item(item)
	_say("Holding " + String(item.item_id))


func _add_to_storage(item: ItemData, amount: int) -> void:
	for i in range(amount):
		FishingManager.current_storage.append(item)
	_say("Added %d x %s to storage" % [amount, item.item_id])


# ---- Progress / upgrades ---------------------------------------------------

const _UPGRADE_FIELDS := ["max_casts_per_session", "reel_strength_multiplier", "tension_gain_multiplier"]
const _UPGRADE_LISTS := ["owned_upgrade_ids", "unlocked_bait_ids"]


# Remember FishingManager's starting values so upgrades can be undone.
# Fields that only exist on newer branches are captured when present.
func _capture_defaults() -> void:
	for field in _UPGRADE_FIELDS:
		if field in FishingManager:
			_defaults[field] = FishingManager.get(field)
	for field in _UPGRADE_LISTS:
		if field in FishingManager:
			_defaults[field] = (FishingManager.get(field) as Array).duplicate()
	_defaults["equipped_bait"] = FishingManager.equipped_bait


func _reset_upgrades() -> void:
	for field in _UPGRADE_FIELDS:
		if _defaults.has(field):
			FishingManager.set(field, _defaults[field])
	for field in _UPGRADE_LISTS:
		if _defaults.has(field):
			var list: Array = FishingManager.get(field)
			list.clear()
			list.append_array(_defaults[field])
	if "pending_upgrade_ids" in ShopManager:
		(ShopManager.get("pending_upgrade_ids") as Array).clear()
	FishingManager.equip_bait(_defaults.get("equipped_bait") as BaitData)
	if FishingManager.has_signal(&"upgrades_changed"):
		FishingManager.emit_signal(&"upgrades_changed")
	_say("Upgrades reset")


func _grant_trade(trade: TradeData) -> void:
	if trade.reward_method != &"" and FishingManager.has_method(trade.reward_method):
		FishingManager.call(trade.reward_method, trade.reward_amount)
	if trade.reward_item != null:
		_add_to_storage(trade.reward_item, trade.reward_item_amount)
	_say("Granted " + trade.display_name)


func _reset_bobbers() -> void:
	BobberManager.unlocked_ids.clear()
	BobberManager.unlocked_ids.append(BobberManager.DEFAULT_ID)
	BobberManager.equipped_id = BobberManager.DEFAULT_ID
	if FileAccess.file_exists(BobberManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BobberManager.SAVE_PATH))
	BobberManager.collection_changed.emit()
	BobberManager.equipped_changed.emit(BobberManager.get_equipped_bobber())


func _reset_all() -> void:
	if not _reset_armed:
		_reset_armed = true
		_update_reset_button()
		return
	_reset_armed = false
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	NPCManager.npc_states.clear()
	FishingManager.current_storage.clear()
	FishingManager.catch_dex.clear()
	FishingManager.catch_lifetime.clear()
	_reset_upgrades()
	ChallengeManager.reset_all()
	_reset_bobbers()
	RecruitmentHandler.listening = false
	RecruitmentHandler.npc = null
	_forced_fish = null
	if _force_fish != null:
		_force_fish.select(0)
	hide()
	_say("Everything reset; reloading the world")
	get_tree().reload_current_scene()


func _update_reset_button() -> void:
	if _reset_all_button != null:
		_reset_all_button.text = "CLICK AGAIN to reset everything" if _reset_armed else "Reset ALL progress (reloads world)"


# ---- Fishing cheats ------------------------------------------------------

# Overwrite the controller's decided fish each time a cast starts.
func _apply_forced_fish() -> void:
	var controller := _controller()
	if controller == null:
		_last_fishing_state = -1
		return
	var state: int = controller.get("current_state")
	if state != _last_fishing_state:
		if state == 1 and _forced_fish != null:
			controller.set("hooked_fish", _forced_fish)
			print("[DEV] Forced this cast to ", _forced_fish.fish_id)
		_last_fishing_state = state


func _instant_bite() -> void:
	var controller := _controller()
	if controller != null and int(controller.get("current_state")) == 1:
		controller.set("bite_time", 0.0)
		_say("Bite now")
	else:
		_say("Only while waiting for a bite")


func _instant_catch() -> void:
	var controller := _controller()
	if controller != null and int(controller.get("current_state")) == 2:
		controller.call("start_catch_sequence")
		_say("Caught")
	else:
		_say("Only while reeling a fish")


# ---- Info text -----------------------------------------------------------

func _refresh_current_tab() -> void:
	match String(_tabs.get_current_tab_control().name):
		"Info":
			_info.text = _build_info()
		"Fishing":
			_fishing_status.text = _fishing_summary()


func _h(title: String) -> String:
	return "\n[color=#%s][b]%s[/b][/color]\n" % [PixelUI.GOLD.to_html(false), title]


func _onoff(value: bool) -> String:
	if value:
		return "[color=#%s]true[/color]" % PixelUI.GREEN.to_html(false)
	return "[color=#%s]false[/color]" % PixelUI.RED.to_html(false)


func _build_info() -> String:
	var t := ""
	var player := _player()
	t += _h("Game")
	t += "Time of day: %s   Actions: %d\n" % [GameManager.Times.keys()[GameManager.time_of_day], GameManager.player_actions]
	t += "Modal UI open (besides this): %s\n" % _onoff(_other_modal_open())
	if player != null:
		t += "Player: pos %s  busy %s  holding %s\n" % [player.global_position.round(), _onoff(player.busy), String(player.held_item.item_id) if player.held_item != null else "-"]

	t += _h("Dialogue")
	if DialogueManager.is_active:
		var npc: NPCData = DialogueManager.current_npc
		t += "Active with %s  node [b]%s[/b]  line %d  awaiting choice %s\n" % [npc.display_name if npc != null else "?", str(DialogueManager.get("_node_id")), DialogueManager.line_index, _onoff(DialogueManager.is_awaiting_choice())]
	else:
		t += "No conversation\n"
	t += "Recruitment listening: %s   Free houses: %d\n" % [_onoff(RecruitmentHandler.listening), RecruitmentHandler.available_homes.size()]

	t += _h("NPCs")
	var ids: Array = NPCManager.npc_states.keys()
	if not ids.has(SILAS_ID):
		ids.append(SILAS_ID)
	for id in ids:
		var state: Dictionary = NPCManager.npc_states.get(id, {"attraction": 0, "flags": {}})
		var flags: Dictionary = state.get("flags", {})
		var data: NPCData = _silas_data() if id == SILAS_ID else null
		t += "[b]%s[/b]  attraction %d  in world %s\n" % [id, int(state.get("attraction", 0)), _onoff(id == SILAS_ID and _find_silas() != null)]
		if flags.is_empty():
			t += "   flags: (none)\n"
		for flag in flags:
			t += "   %s = %s\n" % [flag, _onoff(bool(flags[flag]))]
		if data != null:
			t += "   next encounter: %s\n" % _peek_encounter(data)

	t += _h("Fishing")
	t += _fishing_summary() + "\n"
	t += "Storage (%d): %s\n" % [FishingManager.current_storage.size(), _count_items(FishingManager.current_storage)]
	var dex: Array[String] = []
	for fish in FishingManager.catch_dex:
		dex.append("%s x%d" % [fish.fish_id, FishingManager.catch_lifetime.get(fish, 0)])
	t += "Catch dex: %s\n" % (", ".join(dex) if not dex.is_empty() else "-")

	t += _h("Upgrades")
	for field in _UPGRADE_FIELDS + _UPGRADE_LISTS:
		if field in FishingManager:
			t += "%s: %s\n" % [field, str(FishingManager.get(field))]
	if "pending_upgrade_ids" in ShopManager:
		t += "pending deliveries: %s\n" % str(ShopManager.get("pending_upgrade_ids"))

	t += _h("Challenges (%d/%d)  streak %d" % [ChallengeManager.get_completed_count(), ChallengeManager.get_total_count(), ChallengeManager.catch_streak])
	for c in ChallengeManager.challenges:
		if c != null:
			t += "%s  %d/%d  %s\n" % [c.display_name, c.progress, c.target_amount, ("[color=#%s]DONE[/color]" % PixelUI.GREEN.to_html(false)) if c.completed else ""]

	t += _h("Bobbers")
	var unlocked: Array[String] = []
	for id in BobberManager.unlocked_ids:
		unlocked.append(String(id))
	t += "Unlocked: %s   Equipped: %s\n" % [", ".join(unlocked), BobberManager.equipped_id]
	return t


func _fishing_summary() -> String:
	var controller := _controller()
	var t := ""
	if controller != null:
		var state: int = controller.get("current_state")
		var hooked: FishData = controller.get("hooked_fish")
		t += "State %s  casts %d/%d  bite in %.1fs  fish %s\n" % [FISHING_STATES[state] if state < FISHING_STATES.size() else str(state), int(controller.get("casts")), FishingManager.max_casts_per_session, float(controller.get("bite_time")), String(hooked.fish_id) if hooked != null else "-"]
	t += "Bait: %s   Forced species: %s" % [FishingManager.equipped_bait.display_name if FishingManager.equipped_bait != null else "-", String(_forced_fish.fish_id) if _forced_fish != null else "off"]
	return t


# Which encounter would play next, without consuming a random pool pick.
func _peek_encounter(npc: NPCData) -> String:
	var state: Dictionary = NPCManager.npc_states.get(npc.npc_id, {"attraction": 0, "flags": {}})
	var flags: Dictionary = state.get("flags", {})
	for rule in npc.encounter_rules:
		if rule == null:
			continue
		if rule.use_min_attraction and int(state.get("attraction", 0)) < rule.min_attraction:
			continue
		var ok := true
		for f in rule.required_flags:
			if not flags.get(f, false):
				ok = false
		for f in rule.forbidden_flags:
			if flags.get(f, false):
				ok = false
		if ok:
			return rule.json_path.get_file() if rule.json_pool.is_empty() else "pool of %d" % rule.json_pool.size()
	return "(none)"


func _count_items(items: Array[ItemData]) -> String:
	var counts: Dictionary = {}
	for item in items:
		if item != null:
			counts[item.item_id] = int(counts.get(item.item_id, 0)) + 1
	var parts: Array[String] = []
	for id in counts:
		parts.append("%s x%d" % [id, counts[id]])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _other_modal_open() -> bool:
	for ui in get_tree().get_nodes_in_group(&"modal_ui"):
		if ui != self and (ui is CanvasLayer or ui is CanvasItem) and ui.visible:
			return true
	return false


# ---- UI construction -----------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.theme = _build_theme()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH - 16.0
	_panel.offset_right = -16.0
	_panel.offset_top = 16.0
	_panel.offset_bottom = -16.0
	add_child(_panel)

	var root := VBoxContainer.new()
	_panel.add_child(root)
	root.add_theme_constant_override("separation", 2 * PixelUI.SCALE)
	root.add_child(PixelUI.label("DEV PANEL", &"HeaderLabel"))
	root.add_child(PixelUI.label("[F9] close    [F5] end dialogue", &"DimLabel"))
	_status = PixelUI.label("Ready", &"", PixelUI.CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_i: int) -> void: _on_tab_changed())
	root.add_child(_tabs)

	_build_info_tab()
	_build_dialogue_tab()
	_build_items_tab()
	_build_progress_tab()
	_build_flags_tab()
	_build_fishing_tab()
	_build_cosmetics_tab()


# The game's shared pixel theme (PixelUI), extended for the extra controls the
# panel uses. Duplicated so the shared theme itself is never modified.
func _build_theme() -> Theme:
	var t: Theme = PixelUI.get_theme().duplicate()
	var field := PixelUI.box(PixelUI.INSET, PixelUI.ROW_EDGE, 2)
	var field_focus := PixelUI.box(PixelUI.INSET, PixelUI.CYAN, 2)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", PixelUI.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", PixelUI.TEXT_DIM)
	t.set_color("caret_color", "LineEdit", PixelUI.CYAN)
	# Popup lists of OptionButtons.
	t.set_stylebox("panel", "PopupMenu", PixelUI.box(PixelUI.WINDOW, PixelUI.CYAN_DARK, 2))
	t.set_stylebox("hover", "PopupMenu", PixelUI.box(PixelUI.TEAL_HOVER, PixelUI.CYAN, 1))
	t.set_color("font_color", "PopupMenu", PixelUI.TEXT)
	t.set_color("font_hover_color", "PopupMenu", PixelUI.TEXT)
	# Checkboxes read as rows; the tick icon and green text show the state.
	t.set_stylebox("normal", "CheckBox", PixelUI.box(PixelUI.ROW, PixelUI.ROW_EDGE, 2))
	t.set_stylebox("hover", "CheckBox", PixelUI.box(PixelUI.TEAL_HOVER, PixelUI.CYAN, 2))
	t.set_stylebox("pressed", "CheckBox", PixelUI.box(PixelUI.ROW_DONE, PixelUI.CYAN, 2))
	t.set_stylebox("hover_pressed", "CheckBox", PixelUI.box(PixelUI.TEAL_HOVER, PixelUI.CYAN, 2))
	t.set_color("font_pressed_color", "CheckBox", PixelUI.GREEN)
	t.set_color("font_hover_pressed_color", "CheckBox", PixelUI.GREEN)
	# Info text: [b] uses the bold pixel font.
	t.set_font("normal_font", "RichTextLabel", PixelUI.FONT_SMALL)
	t.set_font("bold_font", "RichTextLabel", PixelUI.FONT_SMALL_BOLD)
	t.set_font_size("normal_font_size", "RichTextLabel", PixelUI.SMALL_SIZE)
	t.set_font_size("bold_font_size", "RichTextLabel", PixelUI.SMALL_SIZE)
	t.set_color("default_color", "RichTextLabel", PixelUI.TEXT)
	# PixelOperator8 has no built-in leading; give wrapped lines room.
	t.set_constant("line_separation", "RichTextLabel", 2 * PixelUI.SCALE)
	t.set_constant("line_spacing", "Label", 2 * PixelUI.SCALE)
	t.set_stylebox("panel", "TabContainer", PixelUI.box(PixelUI.INSET, PixelUI.ROW_EDGE, 3))
	# Tighter tabs than the shared theme so all seven fit in one row.
	t.set_stylebox("tab_selected", "TabContainer", PixelUI.box(PixelUI.TEAL, PixelUI.CYAN, 1))
	t.set_stylebox("tab_hovered", "TabContainer", PixelUI.box(PixelUI.TEAL_HOVER, PixelUI.CYAN_DARK, 1))
	t.set_stylebox("tab_unselected", "TabContainer", PixelUI.box(PixelUI.ROW, PixelUI.ROW_EDGE, 1))
	t.set_stylebox("tab_focus", "TabContainer", PixelUI.box(Color(0, 0, 0, 0), PixelUI.CYAN, 1))
	t.set_color("font_selected_color", "TabContainer", PixelUI.TEXT)
	t.set_color("font_hovered_color", "TabContainer", PixelUI.TEXT)
	t.set_color("font_unselected_color", "TabContainer", PixelUI.TEXT_DIM)
	t.set_constant("side_margin", "TabContainer", 0)
	t.set_constant("separation", "VBoxContainer", PixelUI.SCALE)
	t.set_constant("separation", "HBoxContainer", 2 * PixelUI.SCALE)
	return t


func _on_tab_changed() -> void:
	_refresh_time = 0.0
	match String(_tabs.get_current_tab_control().name):
		"Progress":
			_rebuild_progress()
		"Flags":
			_rebuild_flags()


func _add_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _heading(parent: Control, text: String) -> void:
	var label := PixelUI.label(text, &"TitleLabel", PixelUI.GOLD)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	# Full-width buttons trim long labels instead of widening the panel;
	# small buttons in rows keep their natural width.
	if parent is VBoxContainer:
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		button.tooltip_text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row


func _build_info_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Info"
	_tabs.add_child(scroll)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_info)


func _build_dialogue_tab() -> void:
	var box := _add_tab("Talk")
	_heading(box, "Silas story checkpoints (sets flags, spawns Silas, opens the talk)")
	var checkpoints := [
		["Not caught (reset Silas + reload world)", "not_caught"],
		["Just caught: recruitment talk", "just_caught"],
		["Recruited: casual talk", "recruited"],
		["Give spyglass: gift talk", "spyglass"],
		["Spyglass given: invitation", "invitation"],
		["Invitation accepted: house scene", "house_scene"],
		["Route complete (unlocks Silas bobber)", "route_complete"],
	]
	for entry in checkpoints:
		var id: String = entry[1]
		_button(box, entry[0], func() -> void: _checkpoint(id))

	_heading(box, "Play any dialogue JSON as Silas (flags untouched)")
	var row := _row(box)
	_json_picker = OptionButton.new()
	_json_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for path in _list_dialogue():
		_json_picker.add_item(path.get_file())
		_json_picker.set_item_metadata(_json_picker.item_count - 1, path)
	row.add_child(_json_picker)
	_button(row, "Play", func() -> void:
		if _json_picker.selected >= 0:
			_play_json(str(_json_picker.get_item_metadata(_json_picker.selected))))

	_heading(box, "Conversation")
	_button(box, "End current dialogue (F5)", skip_dialogue)


func _build_items_tab() -> void:
	var box := _add_tab("Items")
	var top := _row(box)
	_button(top, "Clear held item", func() -> void:
		var player := _player()
		if player != null:
			player.remove_held_item()
			_say("Hands emptied"))
	_button(top, "Clear storage", func() -> void:
		FishingManager.current_storage.clear()
		_say("Storage cleared"))
	for path in _list_resources(ITEMS_DIR):
		var item := load(path) as ItemData
		if item == null:
			continue
		var row := _row(box)
		var icon := TextureRect.new()
		icon.texture = item.sprite
		icon.custom_minimum_size = Vector2(16, 16) * PixelUI.SCALE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon)
		var label := Label.new()
		label.text = String(item.item_id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_button(row, "Hands", func() -> void: _give_to_hands(item))
		_button(row, "Storage +1", func() -> void: _add_to_storage(item, 1))
		_button(row, "+5", func() -> void: _add_to_storage(item, 5))


func _build_progress_tab() -> void:
	_progress_box = _add_tab("Progress")


func _rebuild_progress() -> void:
	if _progress_box == null:
		return
	for child in _progress_box.get_children():
		child.queue_free()
	var box := _progress_box
	_heading(box, "Challenges (%d/%d done)" % [ChallengeManager.get_completed_count(), ChallengeManager.get_total_count()])
	for c in ChallengeManager.challenges:
		if c == null:
			continue
		var challenge: ChallengeData = c
		var row := _row(box)
		var label := Label.new()
		label.text = "%s  %d/%d%s" % [challenge.display_name, challenge.progress, challenge.target_amount, "  DONE" if challenge.completed else ""]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var complete := _button(row, "Complete", func() -> void:
			ChallengeManager.debug_complete(challenge)
			_say("Completed " + challenge.display_name)
			_rebuild_progress.call_deferred())
		complete.disabled = challenge.completed
	_button(box, "Reset all challenges", func() -> void:
		ChallengeManager.reset_all()
		_say("Challenges reset")
		_rebuild_progress.call_deferred())

	_heading(box, "Upgrades (applies the trade reward directly)")
	for t in ShopManager.trades:
		var trade: TradeData = t
		if trade == null or (trade.reward_method == &"" and trade.reward_item == null):
			continue
		var reward := String(trade.reward_method) if trade.reward_method != &"" else "item " + String(trade.reward_item.item_id)
		var grant := _button(box, "Grant " + trade.display_name, func() -> void: _grant_trade(trade))
		grant.tooltip_text = "%s x%d" % [reward, trade.reward_amount]
	_button(box, "Reset upgrades", _reset_upgrades)

	_heading(box, "Everything")
	_reset_all_button = _button(box, "", _reset_all)
	_update_reset_button()


func _build_flags_tab() -> void:
	_flags_box = _add_tab("Flags")


# Every flag named anywhere in the dialogue JSON or NPC data, plus any set at runtime.
func _known_flags(npc_id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for path in _list_dialogue():
		_collect_flags(JSON.parse_string(FileAccess.get_file_as_string(path)), found)
	if npc_id == SILAS_ID:
		var data := _silas_data()
		for rule in data.encounter_rules:
			for f in rule.required_flags + rule.forbidden_flags:
				if not found.has(f):
					found.append(f)
		if not found.has(data.gift_completed_flag):
			found.append(data.gift_completed_flag)
		if not found.has(&"silas_route_complete"):
			found.append(&"silas_route_complete")
	var flags: Dictionary = NPCManager.npc_states.get(npc_id, {}).get("flags", {})
	for f in flags:
		if not found.has(StringName(f)):
			found.append(StringName(f))
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


func _collect_flags(value: Variant, found: Array[StringName]) -> void:
	if value is Dictionary:
		for key in value:
			if key in ["set_flags", "clear_flags", "required_flags", "forbidden_flags"] and value[key] is Array:
				for f in value[key]:
					var id := StringName(str(f))
					if not found.has(id):
						found.append(id)
			else:
				_collect_flags(value[key], found)
	elif value is Array:
		for entry in value:
			_collect_flags(entry, found)


func _rebuild_flags() -> void:
	if _flags_box == null:
		return
	var selected_id: StringName = SILAS_ID
	if _flag_npc != null and _flag_npc.selected >= 0:
		selected_id = StringName(_flag_npc.get_item_text(_flag_npc.selected))
	for child in _flags_box.get_children():
		child.queue_free()
	var box := _flags_box

	var row := _row(box)
	var label := Label.new()
	label.text = "NPC"
	row.add_child(label)
	_flag_npc = OptionButton.new()
	var ids: Array = NPCManager.npc_states.keys()
	if not ids.has(SILAS_ID):
		ids.append(SILAS_ID)
	for id in ids:
		_flag_npc.add_item(String(id))
		if StringName(id) == selected_id:
			_flag_npc.select(_flag_npc.item_count - 1)
	_flag_npc.item_selected.connect(func(_i: int) -> void: _rebuild_flags.call_deferred())
	row.add_child(_flag_npc)

	var state: Dictionary = NPCManager.get_npc_state(selected_id)
	var attraction_row := _row(box)
	var attraction_label := Label.new()
	attraction_label.text = "Attraction"
	attraction_row.add_child(attraction_label)
	var attraction := SpinBox.new()
	attraction.min_value = -100
	attraction.max_value = 100
	attraction.value = int(state.get("attraction", 0))
	attraction.value_changed.connect(func(v: float) -> void:
		state["attraction"] = int(v)
		_say("%s attraction = %d" % [selected_id, int(v)]))
	attraction_row.add_child(attraction)

	_heading(box, "Flags (toggle to set / clear)")
	var flags: Dictionary = state["flags"]
	for flag in _known_flags(selected_id):
		var check := CheckBox.new()
		check.text = String(flag)
		check.focus_mode = Control.FOCUS_NONE
		check.button_pressed = bool(flags.get(flag, false))
		var id: StringName = flag
		check.toggled.connect(func(on: bool) -> void:
			flags[id] = on
			_say("%s.%s = %s" % [selected_id, id, on]))
		box.add_child(check)

	var add_row := _row(box)
	var field := LineEdit.new()
	field.placeholder_text = "new flag name"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(field)
	_button(add_row, "Set true", func() -> void:
		if field.text.strip_edges().is_empty():
			return
		flags[StringName(field.text.strip_edges())] = true
		_say("Set " + field.text.strip_edges())
		_rebuild_flags.call_deferred())
	_button(box, "Clear all flags for this NPC", func() -> void:
		flags.clear()
		_say("Cleared flags for " + String(selected_id))
		_rebuild_flags.call_deferred())


func _build_fishing_tab() -> void:
	var box := _add_tab("Fishing")
	_fishing_status = Label.new()
	_fishing_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_fishing_status)
	_button(box, "Instant bite (while waiting)", _instant_bite)
	_button(box, "Instant catch (while reeling)", _instant_catch)

	_heading(box, "Force species on every cast")
	_force_fish = OptionButton.new()
	_force_fish.add_item("Off (normal bait odds)")
	_fish_options.clear()
	for path in _list_resources(FISH_DIR):
		var fish := load(path) as FishData
		if fish != null:
			_fish_options.append(fish)
			_force_fish.add_item(String(fish.fish_id))
	_force_fish.item_selected.connect(func(i: int) -> void:
		_forced_fish = null if i == 0 else _fish_options[i - 1]
		_say("Forced species: " + (String(_forced_fish.fish_id) if _forced_fish != null else "off")))
	box.add_child(_force_fish)

	_heading(box, "Casts")
	_button(box, "+1 max casts per session", func() -> void:
		FishingManager.max_casts_per_session += 1
		_say("Max casts = %d" % FishingManager.max_casts_per_session))
	_button(box, "Refill casts this session", func() -> void:
		var controller := _controller()
		if controller != null:
			controller.set("casts", 0)
			_say("Casts refilled"))


func _build_cosmetics_tab() -> void:
	var box := _add_tab("Bobbers")
	_heading(box, "Bobbers")
	_button(box, "Unlock all bobbers", func() -> void:
		for bobber in BobberManager.bobbers:
			if bobber != null:
				BobberManager.unlock_bobber(bobber.bobber_id)
		_say("All bobbers unlocked"))
	_button(box, "Reset bobbers to default", func() -> void:
		_reset_bobbers()
		_say("Bobbers reset"))
	for b in BobberManager.bobbers:
		if b == null:
			continue
		var bobber: BobberData = b
		_button(box, "Equip bobber: " + String(bobber.bobber_id), func() -> void:
			BobberManager.unlock_bobber(bobber.bobber_id)
			BobberManager.equip_bobber(bobber.bobber_id)
			_say("Equipped bobber " + String(bobber.bobber_id)))

	_heading(box, "Bait")
	for b in FishingManager.available_baits:
		if b == null:
			continue
		var bait: BaitData = b
		_button(box, "Equip bait: " + bait.display_name, func() -> void:
			if "unlocked_bait_ids" in FishingManager:
				var unlocked: Array = FishingManager.get("unlocked_bait_ids")
				if not unlocked.has(bait.bait_id):
					unlocked.append(bait.bait_id)
			FishingManager.equip_bait(bait)
			_say("Equipped bait " + bait.display_name))
