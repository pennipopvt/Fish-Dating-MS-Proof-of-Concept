extends Node

# Day/time clock. Conversations are free. Each sea dive occupies one whole
# morning/afternoon/night period when Penni returns to shore. Dates also
# consume their booked period. The bed can skip ahead, and legacy land fishing
# retains its original action-based rules until it is redesigned.
# UI should listen to the signals below.
# Other systems (shop/delivery, fish, NPCs) read the clock with get_day(),
# get_period() and is_period(); there is no event scheduler.
# Clock progression is session-only: every launch starts at day 1 morning.

signal time_changed(day: int, time: Times)
signal day_started(day: int)
signal actions_changed(remaining: int)
# Night's last action was spent: time-costing activities are blocked until rest().
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
# True only while rest emits its existing synchronous time/period signals.
var _rest_clock_update: bool = false
# Casts in the current (not yet charged) fishing action.
var _casts_in_action: int = 0
# Dive catches are recorded normally. A full period is spent on surfacing.
var diving_session_active: bool = false
# The confirmed dive reserves a period; declining the prompt never does.
var _dive_day: int = -1
var _dive_period: Times = Times.MORNING


func _ready() -> void:
	# No disk save/load during prototyping. The initialized clock always starts
	# at day 1, morning, with all actions available on a fresh launch.
	# Later autoloads may not be ready yet; connect once the tree is set up.
	_connect_sources.call_deferred()


func _connect_sources() -> void:
	FishingManager.fish_caught.connect(func(_fish: FishData) -> void: record_fishing_cast())
	FishingManager.fish_lost.connect(func(_fish: FishData) -> void: record_fishing_cast())
	# Conversations never spend time. DateManager consumes its own date period.


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


# Only time-costing activities need this. Ordinary NPC dialogue is free.
func can_act() -> bool:
	return player_actions > 0


# The dock and dive transition share the clock's one-dive-per-period rule.
func can_start_dive() -> bool:
	return can_act() and not diving_session_active \
		and (_dive_day != day or _dive_period != time_of_day)


func begin_dive_period() -> bool:
	if not can_start_dive():
		return false
	_dive_day = day
	_dive_period = time_of_day
	return true


# Completing a dive advances to the next period. Night does not advance
# to the next day automatically; the bed still controls overnight sleep.
func finish_dive_period() -> void:
	diving_session_active = false
	spend_actions(get_actions_left())


# --- Moving the clock ---

# Each completed (or abandoned) cast counts toward the current fishing action.
# Upgrades may allow several casts before one clock action is spent.
func record_fishing_cast() -> void:
	if diving_session_active or not can_act():
		return
	_casts_in_action += 1
	if _casts_in_action >= maxi(FishingManager.casts_per_action, 1):
		_casts_in_action = 0
		spend_actions(1)


# Leaving the fishing session partway through a batch still costs an action:
# cancelling after one cast must not let the player fish for free.
func finish_fishing_session() -> void:
	if _casts_in_action > 0:
		_casts_in_action = 0
		spend_actions(1)



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


# Sleep can skip multiple periods in a single clock change. All clock
# listeners receive their usual signals, but visuals can snap while black.
func is_rest_clock_update() -> bool:
	return _rest_clock_update


# Next-period rest, also used by the existing overnight romance sequence.
func rest() -> void:
	var next: Times = Times.MORNING if time_of_day == Times.NIGHT else (time_of_day + 1) as Times
	rest_until(next)


# A rest never animates intermediate periods or emits extra day-start events.
func rest_until(target: Times) -> void:
	var target_day: int = day + (1 if target <= time_of_day else 0)
	_rest_clock_update = true
	_set_clock(target_day, target, ACTIONS_PER_PERIOD)
	_rest_clock_update = false


# Back to day 1 morning (dev reset); nothing is stored across launches.
func reset_clock() -> void:
	_casts_in_action = 0
	diving_session_active = false
	_dive_day = -1
	_dive_period = Times.MORNING
	_set_clock(1, Times.MORNING, ACTIONS_PER_PERIOD)


# Single place the clock changes: updates values first, then emits signals
# so dependent systems can read the new day and period. No disk writes.
func _set_clock(new_day: int, new_period: Times, new_actions: int) -> void:
	var period_changed: bool = new_day != day or new_period != time_of_day
	var new_morning: bool = new_day != day
	day = new_day
	time_of_day = new_period
	player_actions = new_actions
	actions_changed.emit(player_actions)
	if period_changed:
		time_changed.emit(day, time_of_day)
	if new_morning:
		day_started.emit(day)


# Menus in this group block player actions, not the running world.
func is_modal_ui_open() -> bool:
	for ui in get_tree().get_nodes_in_group(&"modal_ui"):
		if (ui is CanvasLayer or ui is CanvasItem) and ui.visible:
			return true
	return false
