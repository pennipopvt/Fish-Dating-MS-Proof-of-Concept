extends Node

# Day/time clock. Time only moves when the player spends actions (a finished
# cast, a finished NPC conversation) or rests at the bed. Browsing menus never
# moves it. Each period has ACTIONS_PER_PERIOD actions; spending the last one
# moves to the next period. Once night's actions are gone, the player can only rest.
# Listens to FishingManager/DialogueManager; UI should listen to the signals below.
# Other systems (shop/delivery, fish, NPCs) read the clock with get_day(),
# get_period() and is_period(); there is no event scheduler.
# The clock is saved to save_path on every change and loaded on start.

signal time_changed(day: int, time: Times)
signal day_started(day: int)
signal actions_changed(remaining: int)
# Night's last action was spent: fishing and talking are blocked until rest().
signal actions_exhausted

enum Times {
	MORNING,
	AFTERNOON,
	NIGHT
}

const ACTIONS_PER_PERIOD: int = 3
const SAVE_PATH: String = "user://save.cfg"
const SAVE_SECTION: String = "clock"

# Tests point this somewhere else so they never touch the player's save.
var save_path: String = SAVE_PATH

var day: int = 1
var time_of_day : Times = Times.MORNING
var player_actions : int = ACTIONS_PER_PERIOD


func _ready() -> void:
	load_from_disk()
	# Later autoloads may not be ready yet; connect once the tree is set up.
	_connect_sources.call_deferred()


func _connect_sources() -> void:
	FishingManager.fish_caught.connect(func(_fish: FishData) -> void: spend_actions(1))
	FishingManager.fish_lost.connect(func(_fish: FishData) -> void: spend_actions(1))
	DialogueManager.conversation_finished.connect(func(_npc: NPCData) -> void: spend_actions(1))


# --- Reading the clock (for shop/delivery, fish and NPC rules) ---

func get_day() -> int:
	return day


func get_period() -> Times:
	return time_of_day


func is_period(period: Times) -> bool:
	return time_of_day == period


# "Morning", "Afternoon", "Night".
func get_period_name(period: Times = time_of_day) -> String:
	return String(Times.keys()[period]).capitalize()


func get_actions_left() -> int:
	return player_actions


# False once night's actions are spent. Time-costing interactions (fishing,
# talking to an NPC) check this before starting.
func can_act() -> bool:
	return player_actions > 0


# --- Moving the clock ---

# Use for any time-costing activity (e.g. a future NPC hangout scene could
# cost more than 1). Rolls into the next period when this one runs out;
# never past night (only rest() starts a new day).
func spend_actions(amount: int = 1) -> void:
	if amount <= 0 or not can_act():
		return
	var left: int = maxi(player_actions - amount, 0)
	if left == 0 and time_of_day != Times.NIGHT:
		_set_clock(day, (time_of_day + 1) as Times, ACTIONS_PER_PERIOD)
		return
	_set_clock(day, time_of_day, left)
	if player_actions == 0:
		actions_exhausted.emit()


# Bed: skip to the next period with fresh actions. Night rolls over to the next
# day's morning. Free, and allowed any time.
func rest() -> void:
	if time_of_day == Times.NIGHT:
		_set_clock(day + 1, Times.MORNING, ACTIONS_PER_PERIOD)
	else:
		_set_clock(day, (time_of_day + 1) as Times, ACTIONS_PER_PERIOD)


# Back to day 1 morning (dev reset). Also overwrites the saved clock.
func reset_clock() -> void:
	_set_clock(1, Times.MORNING, ACTIONS_PER_PERIOD)


# Single place the clock changes: updates the values first, so listeners read
# the new day/period, then emits and saves.
func _set_clock(new_day: int, new_period: Times, new_actions: int) -> void:
	var period_changed: bool = new_day != day or new_period != time_of_day
	var new_morning: bool = new_day != day
	day = new_day
	time_of_day = new_period
	player_actions = new_actions
	save_to_disk()
	actions_changed.emit(player_actions)
	if period_changed:
		time_changed.emit(day, time_of_day)
	if new_morning:
		day_started.emit(day)


# --- Save/load ---

# For a future game-wide save system.
func get_save_data() -> Dictionary:
	return {"day": day, "period": int(time_of_day), "actions": player_actions}


# Applies saved values (invalid ones fall back to defaults) and notifies
# listeners as if the clock had moved. Doesn't write to disk.
func load_save_data(data: Dictionary) -> void:
	day = maxi(int(data.get("day", 1)), 1)
	time_of_day = clampi(int(data.get("period", Times.MORNING)), Times.MORNING, Times.NIGHT) as Times
	player_actions = clampi(int(data.get("actions", ACTIONS_PER_PERIOD)), 0, ACTIONS_PER_PERIOD)
	actions_changed.emit(player_actions)
	time_changed.emit(day, time_of_day)


func save_to_disk() -> void:
	var config := ConfigFile.new()
	# Keep other sections if a later system shares this file.
	config.load(save_path)
	var data: Dictionary = get_save_data()
	for key in data:
		config.set_value(SAVE_SECTION, key, data[key])
	var error: Error = config.save(save_path)
	if error != OK:
		push_warning("Couldn't save the day clock to %s (error %d)" % [save_path, error])


# Returns false if there was no saved clock.
func load_from_disk() -> bool:
	var config := ConfigFile.new()
	if config.load(save_path) != OK or not config.has_section(SAVE_SECTION):
		return false
	var data: Dictionary = {}
	for key in config.get_section_keys(SAVE_SECTION):
		data[key] = config.get_value(SAVE_SECTION, key)
	load_save_data(data)
	return true


# Menus in this group block player actions, not the running world.
func is_modal_ui_open() -> bool:
	for ui in get_tree().get_nodes_in_group(&"modal_ui"):
		if (ui is CanvasLayer or ui is CanvasItem) and ui.visible:
			return true
	return false
