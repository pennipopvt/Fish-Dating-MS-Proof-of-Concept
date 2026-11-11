extends Node

# Day/time clock. Time only moves when the player spends actions (a finished
# cast, a finished NPC conversation) or rests. Browsing menus never moves it.
# Each period has ACTIONS_PER_PERIOD actions; spending the last one moves to
# the next period. Once night's actions are gone, the player can only rest.
# Listens to FishingManager/DialogueManager; UI should listen to the signals below.

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

var day: int = 1
var time_of_day : Times = Times.MORNING
var player_actions : int = ACTIONS_PER_PERIOD


func _ready() -> void:
	# Later autoloads may not be ready yet; connect once the tree is set up.
	_connect_sources.call_deferred()


func _connect_sources() -> void:
	FishingManager.fish_caught.connect(func(_fish: FishData) -> void: spend_actions(1))
	FishingManager.fish_lost.connect(func(_fish: FishData) -> void: spend_actions(1))
	DialogueManager.conversation_finished.connect(func(_npc: NPCData) -> void: spend_actions(1))


# False once night's actions are spent. Time-costing interactions (fishing,
# talking to an NPC) check this before starting.
func can_act() -> bool:
	return player_actions > 0


# Use for any time-costing activity (e.g. a future NPC hangout scene could
# cost more than 1). Rolls into the next period when this one runs out;
# never past night (only rest() starts a new day).
func spend_actions(amount: int = 1) -> void:
	if amount <= 0 or not can_act():
		return
	player_actions = maxi(player_actions - amount, 0)
	if player_actions == 0 and time_of_day != Times.NIGHT:
		time_of_day = (time_of_day + 1) as Times
		player_actions = ACTIONS_PER_PERIOD
		actions_changed.emit(player_actions)
		time_changed.emit(day, time_of_day)
		return
	actions_changed.emit(player_actions)
	if player_actions == 0:
		actions_exhausted.emit()


# Sleep until the next morning. Allowed at any time of day.
func rest() -> void:
	day += 1
	time_of_day = Times.MORNING
	player_actions = ACTIONS_PER_PERIOD
	actions_changed.emit(player_actions)
	time_changed.emit(day, time_of_day)
	day_started.emit(day)


# Back to day 1 morning (dev reset).
func reset_clock() -> void:
	day = 1
	time_of_day = Times.MORNING
	player_actions = ACTIONS_PER_PERIOD
	actions_changed.emit(player_actions)
	time_changed.emit(day, time_of_day)


# Menus in this group block player actions, not the running world.
func is_modal_ui_open() -> bool:
	for ui in get_tree().get_nodes_in_group(&"modal_ui"):
		if (ui is CanvasLayer or ui is CanvasItem) and ui.visible:
			return true
	return false
