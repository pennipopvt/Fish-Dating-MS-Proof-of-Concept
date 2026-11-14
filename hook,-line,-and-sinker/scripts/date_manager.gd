extends Node

# Dates (autoload "DateManager"). Penni asks an NPC out in an ask-out JSON;
# each choice there is gated by the flag "date_ok_<date_id>" (refreshed here
# whenever a conversation starts) and requests the scene "date:<date_id>".
# Accepting either starts the date now (skipping the clock forward to an
# allowed period if needed) or books it; a booked date starts when Penni
# interacts with its DateLocation during the booked period, and is missed
# once that period passes.
# A date: fade out, move Penni and the NPC to the location's spots (or to a
# venue spawned just for the date, like the ship out at sea), play the
# date JSON, then fade back and put everyone where they were. A finished date
# uses up the rest of the period's actions, so the clock moves to the next
# period (at night: no actions left, rest only, like any other night).
# Bookings and flags live in memory only, like the rest of NPC state.

signal date_booked(date: DateData, day: int, period: int)
signal date_started(date: DateData)
signal date_finished(date: DateData)
signal date_missed(date: DateData)
signal bookings_changed

const DATES_DIR := "res://resources/dates/"
const SCENE_PREFIX := "date:"
const LOCATION_GROUP := &"date_locations"
const FADE_DURATION := 0.5
const PERIOD_COUNT := 3

# date_id -> DateData
var dates: Dictionary = {}
# date_id -> {"day": int, "period": int}
var bookings: Dictionary = {}

var _active: DateData = null
var _in_dialogue: bool = false
# Day/period the date took place in (after any clock jump).
var _date_day: int = 0
var _date_period: int = 0
# The date's spawned venue (DateData.venue_scene), removed after the date.
var _venue: Node2D = null
# [[Node2D, Vector2 global position], ...] to put back after the date.
var _restore: Array = []
var _fade: ScreenFade


func _ready() -> void:
	_load_dates()
	_build_fade()
	_connect_sources.call_deferred()


func _connect_sources() -> void:
	DialogueManager.conversation_started.connect(_on_conversation_started)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	DialogueManager.scene_requested.connect(_on_scene_requested)
	GameManager.time_changed.connect(func(_day: int, _period: int) -> void: _expire_bookings())


func _load_dates() -> void:
	for file in DirAccess.get_files_at(DATES_DIR):
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var date := load(DATES_DIR + file_name) as DateData
		if date == null or date.date_id == &"":
			continue
		dates[date.date_id] = date


# --- Reading ---

func get_date(date_id: StringName) -> DateData:
	return dates.get(date_id) as DateData


func get_dates_for(npc_id: StringName) -> Array[DateData]:
	var result: Array[DateData] = []
	for date: DateData in dates.values():
		if date.npc != null and date.npc.npc_id == npc_id:
			result.append(date)
	return result


func is_active() -> bool:
	return _active != null


func is_booked(date: DateData) -> bool:
	return date != null and bookings.has(date.date_id)


# Flags/attraction/repeat rules only (no timing).
func meets_requirements(date: DateData) -> bool:
	if date == null or date.npc == null:
		return false
	var state: Dictionary = NPCManager.get_npc_state(date.npc.npc_id)
	var flags: Dictionary = state.get("flags", {})
	if not date.repeatable and flags.get(date.get_completed_flag(), false):
		return false
	if date.use_min_attraction and int(state.get("attraction", 0)) < date.min_attraction:
		return false
	for flag in date.required_flags:
		if not flags.get(flag, false):
			return false
	for flag in date.forbidden_flags:
		if flags.get(flag, false):
			return false
	return true


# True when Penni can ask for this date right now.
func can_ask(date: DateData) -> bool:
	if not meets_requirements(date) or is_booked(date) or _active == date:
		return false
	if date.when == DateData.When.NOW and not date.jump_clock:
		return date.allows_period(GameManager.get_period())
	return true


# The booked date at this location whose period is now, or null.
func get_ready_booking(location_id: StringName) -> DateData:
	for id in bookings:
		var date := get_date(id)
		var slot: Dictionary = bookings[id]
		if date != null and date.location_id == location_id \
				and int(slot["day"]) == GameManager.get_day() and int(slot["period"]) == GameManager.get_period():
			return date
	return null


# The next booking at this location (for its sign), or null.
func get_booking_at(location_id: StringName) -> DateData:
	var best: DateData = null
	var best_slot: int = 0
	for id in bookings:
		var date := get_date(id)
		if date == null or date.location_id != location_id:
			continue
		var slot: int = _slot_index(bookings[id]["day"], bookings[id]["period"])
		if best == null or slot < best_slot:
			best = date
			best_slot = slot
	return best


# "Day 2 Night".
func describe_booking(date: DateData) -> String:
	if not is_booked(date):
		return ""
	var slot: Dictionary = bookings[date.date_id]
	return "Day %d %s" % [int(slot["day"]), GameManager.get_period_name(int(slot["period"]) as GameManager.Times)]


# --- Asking out / booking ---

# What saying yes does: start now or book. Called for "date:<id>" scene requests.
func accept(date: DateData) -> void:
	if date == null:
		return
	if date.when == DateData.When.SCHEDULED:
		book(date)
	else:
		start_date(date)


func book(date: DateData) -> void:
	if date == null:
		return
	var slot := _next_slot(date)
	bookings[date.date_id] = slot
	print("[Date] %s booked for %s" % [date.display_name, describe_booking(date)])
	date_booked.emit(date, int(slot["day"]), int(slot["period"]))
	bookings_changed.emit()


func cancel_booking(date: DateData) -> void:
	if date != null and bookings.erase(date.date_id):
		bookings_changed.emit()


# First allowed period from now (or from the morning days_ahead days later).
func _next_slot(date: DateData) -> Dictionary:
	var day: int = GameManager.get_day() + maxi(date.days_ahead, 0)
	var period: int = GameManager.get_period() if date.days_ahead <= 0 else 0
	for i in PERIOD_COUNT:
		if date.allows_period(period):
			break
		period += 1
		if period >= PERIOD_COUNT:
			period = 0
			day += 1
	return {"day": day, "period": period}


func _slot_index(day: int, period: int) -> int:
	return day * PERIOD_COUNT + period


func _expire_bookings() -> void:
	var now: int = _slot_index(GameManager.get_day(), GameManager.get_period())
	for id in bookings.keys():
		var slot: Dictionary = bookings[id]
		if _slot_index(slot["day"], slot["period"]) >= now:
			continue
		bookings.erase(id)
		var date := get_date(id)
		if date != null and date.npc != null:
			NPCManager.get_npc_state(date.npc.npc_id)["flags"][date.get_missed_flag()] = true
			print("[Date] Missed %s" % date.display_name)
			date_missed.emit(date)
		bookings_changed.emit()


# --- Running a date ---

func start_date(date: DateData) -> void:
	if _active != null or date == null or date.npc == null:
		return
	var location := _find_location(date.location_id)
	if date.venue_scene == null and location == null:
		push_warning("No DateLocation '%s' in the world for date %s" % [date.location_id, date.date_id])
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return
	_active = date
	date_started.emit(date)
	await _fade_to(1.0)
	if date.when == DateData.When.NOW and date.jump_clock:
		_jump_to_allowed_period(date)
	cancel_booking(date)
	_date_day = GameManager.get_day()
	_date_period = GameManager.get_period()
	_restore.clear()
	var venue: Node2D = location
	if date.venue_scene != null:
		_venue = date.venue_scene.instantiate() as Node2D
		player.get_parent().add_child(_venue)
		_venue.global_position = date.venue_position
		venue = _venue
	_move(player, _spot(venue, &"PlayerSpot"))
	_move(_find_actor(date.npc.npc_id), _spot(venue, &"NpcSpot"))
	await _fade_to(0.0)
	_in_dialogue = true
	DialogueManager.request_conversation(date.npc, date.dialogue_json)
	if not DialogueManager.is_active:
		push_warning("Date dialogue could not start: " + date.dialogue_json)
		_in_dialogue = false
		_finish(false)


# Rests period by period until the date's period (at most a day).
func _jump_to_allowed_period(date: DateData) -> void:
	for i in PERIOD_COUNT:
		if date.allows_period(GameManager.get_period()):
			return
		GameManager.rest()


func _finish(completed: bool) -> void:
	var date := _active
	await _fade_to(1.0)
	for entry in _restore:
		var node: Node2D = entry[0]
		if is_instance_valid(node):
			node.global_position = entry[1]
	_restore.clear()
	if is_instance_valid(_venue):
		_venue.queue_free()
	_venue = null
	if completed and date != null:
		var state: Dictionary = NPCManager.get_npc_state(date.npc.npc_id)
		var flags: Dictionary = state["flags"]
		flags[date.get_completed_flag()] = true
		for flag in date.flags_to_set:
			flags[flag] = true
		AffectionManager.change(date.npc.npc_id, date.attraction_change)
		_use_up_period()
	_active = null
	await _fade_to(0.0)
	if completed and date != null:
		date_finished.emit(date)


# The date talk already spent 1 action; if that was the period's last, the
# clock has moved on by itself, so don't skip a second period.
func _use_up_period() -> void:
	if GameManager.get_day() == _date_day and GameManager.get_period() == _date_period:
		GameManager.spend_actions(GameManager.get_actions_left())


func _spot(venue: Node2D, marker: StringName) -> Vector2:
	var node := venue.get_node_or_null(NodePath(marker)) as Node2D
	return node.global_position if node != null else venue.global_position


func _move(node: Node2D, spot: Vector2) -> void:
	if node == null:
		return
	_restore.append([node, node.global_position])
	node.global_position = spot


func _find_location(location_id: StringName) -> DateLocation:
	for node in get_tree().get_nodes_in_group(LOCATION_GROUP):
		var location := node as DateLocation
		if location != null and location.location_id == location_id:
			return location
	return null


# The NPC's body in the world (spawned when caught/recruited), or null.
func _find_actor(npc_id: StringName) -> NPCInteractable:
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var actor := node as NPCInteractable
		if actor != null and actor.npc != null and actor.npc.npc_id == npc_id and not actor.is_queued_for_deletion():
			return actor
	return null


# --- Signals ---

# The ask-out JSON reads these flags when its choices are filtered.
func _on_conversation_started(npc: NPCData) -> void:
	if npc == null:
		return
	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
	for date in get_dates_for(npc.npc_id):
		flags[date.get_available_flag()] = can_ask(date)


func _on_conversation_finished(npc: NPCData) -> void:
	if _in_dialogue and _active != null and npc == _active.npc:
		_in_dialogue = false
		_finish(true)


func _on_scene_requested(_npc: NPCData, scene_id: String) -> void:
	if scene_id.begins_with(SCENE_PREFIX):
		accept(get_date(StringName(scene_id.trim_prefix(SCENE_PREFIX))))


# --- Fade ---

func _build_fade() -> void:
	_fade = ScreenFade.new()
	add_child(_fade)


func _fade_to(alpha: float) -> void:
	await _fade.fade_to(alpha, FADE_DURATION)
