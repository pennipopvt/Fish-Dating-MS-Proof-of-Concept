extends Node

# Dates (autoload "DateManager"). Penni asks an NPC out in an ask-out JSON;
# each choice there is gated by the flag "date_ok_<date_id>" (refreshed here
# whenever a conversation starts) and requests the scene "date:<date_id>".
# Date plans are made with the NPC in dialogue. The terminal calendar only
# displays booked dates. Visit the NPC's townhouse room (or existing
# DateLocation) at the FIRST action of the booked period. If several NPCs
# are booked for the same period, the player chooses whose room to visit.
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
# Choices retain their date_style tags (bold, playful, reassure). Each NPCData
# stores its own score for each style at jealousy tiers 0-3 (0-24, 25-49,
# 50-74, 75-100). Jealousy deltas are shared for now; tune independently.
const JEALOUSY_BY_STYLE := {
	"bold": [0, 2, 5, 8],
	"playful": [-3, -5, -6, -8],
	"reassure": [-8, -10, -12, -15],
}
# Apply each completed date once to the same affection score as dialogue/diving.
const OUTCOME_AFFECTION := {"bad": -8, "okay": 8, "good": 20, "great": 28}

# date_id -> DateData
var dates: Dictionary = {}
# date_id -> {"day": int, "period": int}
var bookings: Dictionary = {}

var _active: DateData = null
var _in_dialogue: bool = false
var _date_score: int = 0
var _date_choice_count: int = 0
var _last_reaction: String = ""
var last_date_outcome: String = ""
var last_date_score: int = 0
# Capture when the NPC was asked, so "next afternoon" keeps its meaning
# even when later activities move the clock.
var _conversation_day: int = 1
var _conversation_period: int = 0
# Day/period the date took place in (after any clock jump).
var _date_day: int = 0
var _date_period: int = 0
# Temporary visuals, separate from the persistent townhouse resident.
var _date_actor: Node2D = null
# The date's spawned venue (DateData.venue_scene), removed after the date.
var _venue: Node2D = null
# [[Node2D, Vector2 global position], ...] to put back after the date.
var _restore: Array = []
var _fade: ScreenFade
var _date_player: Player = null
# Some venues (the original opening boat) author their own camera focus.
# DateManager borrows the existing World camera, never spawns another.
var _date_camera: WorldCameraController = null


func _ready() -> void:
	_load_dates()
	_build_fade()
	_connect_sources.call_deferred()


func _connect_sources() -> void:
	DialogueManager.choice_resolved.connect(_on_date_choice)
	DialogueManager.conversation_started.connect(_on_conversation_started)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	DialogueManager.scene_requested.connect(_on_scene_requested)
	GameManager.time_changed.connect(func(_day: int, _period: int) -> void: _expire_bookings())
	GameManager.actions_changed.connect(func(_actions: int) -> void: _expire_bookings())


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


# Flags/affection/repeat rules only (no timing).
func meets_requirements(date: DateData) -> bool:
	if date == null or date.npc == null:
		return false
	var state: Dictionary = NPCManager.get_npc_state(date.npc.npc_id)
	var flags: Dictionary = state.get("flags", {})
	if not date.repeatable and flags.get(date.get_completed_flag(), false):
		return false
	if date.use_min_affection and AffectionManager.get_affection(date.npc.npc_id) < date.min_affection:
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
	for id in bookings:
		var other := get_date(id)
		if other != null and other.npc == date.npc:
			return false
	return true

# Only the first action of a booked period can begin a date.
func is_booking_ready(date: DateData) -> bool:
	if date == null or not is_booked(date):
		return false
	var slot: Dictionary = bookings[date.date_id]
	return int(slot["day"]) == GameManager.get_day() \
		and int(slot["period"]) == GameManager.get_period() \
		and GameManager.get_actions_left() == GameManager.ACTIONS_PER_PERIOD

# Booking is only invoked by NPC dialogue; the calendar is a read-only view.
func can_book_at(date: DateData, day: int, period: int) -> bool:
	if not can_ask(date) or period < 0 or period >= PERIOD_COUNT or not date.allows_period(period):
		return false
	var chosen_slot := _slot_index(day, period)
	var current_slot := _slot_index(GameManager.get_day(), GameManager.get_period())
	if chosen_slot < current_slot:
		return false
	# Booking in the current period requires time-costing activities unused.
	if chosen_slot == current_slot and GameManager.get_actions_left() != GameManager.ACTIONS_PER_PERIOD:
		return false
	# Different NPCs may agree to the same period. Only one can actually
	# happen, because finishing a date consumes the remainder of the
	# period and the other bookings correctly become missed.
	return true

# "Next morning/afternoon/night" means the next occurrence measured from when
# the conversation started, not the time after a later activity.
func book_next_period(date: DateData, period: int, from_day: int, from_period: int) -> bool:
	if period < 0 or period >= PERIOD_COUNT:
		return false
	var day := from_day + (1 if period <= from_period else 0)
	return book_at(date, day, period)


func get_ready_booking_for_npc(npc_id: StringName) -> DateData:
	for date_id in bookings:
		var date := get_date(date_id)
		if date != null and date.npc != null and date.npc.npc_id == npc_id and is_booking_ready(date):
			return date
	return null


func book_at(date: DateData, day: int, period: int) -> bool:
	if not can_book_at(date, day, period):
		return false
	bookings[date.date_id] = {"day": day, "period": period}
	print("[Date] %s booked for %s" % [date.display_name, describe_booking(date)])
	date_booked.emit(date, day, period)
	bookings_changed.emit()
	return true


# The booked date at this location whose period is now, or null.
func get_ready_booking(location_id: StringName) -> DateData:
	for id in bookings:
		var date := get_date(id)
		var slot: Dictionary = bookings[id]
		if date != null and date.location_id == location_id and is_booking_ready(date):
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

# All dates are now planned instead of starting immediately from dialogue.
func accept(date: DateData) -> void:
	book(date)


func book(date: DateData) -> void:
	if date != null:
		var slot := _next_slot(date)
		book_at(date, int(slot["day"]), int(slot["period"]))


func cancel_booking(date: DateData) -> void:
	if date != null and bookings.erase(date.date_id):
		bookings_changed.emit()


# Find the next ALLOWED period after the current one; no same-period booking.
func _next_slot(date: DateData) -> Dictionary:
	var day: int = GameManager.get_day() + maxi(date.days_ahead, 0)
	var period: int = GameManager.get_period() + 1 if date.days_ahead <= 0 else 0
	if period >= PERIOD_COUNT:
		period = 0
		day += 1
	for i in PERIOD_COUNT * 2:
		if date.allows_period(period) and can_book_at(date, day, period):
			return {"day": day, "period": period}
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
		if _slot_index(int(slot["day"]), int(slot["period"])) > now:
			continue
		if _slot_index(int(slot["day"]), int(slot["period"])) == now and GameManager.get_actions_left() == GameManager.ACTIONS_PER_PERIOD:
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
	if NPCManager.has_blocking_relationship_event(date.npc, &"date"):
		return
	# Enforce the first-action rule even when a scene calls this directly.
	if is_booked(date) and not is_booking_ready(date):
		return
	var location := _find_location(date.location_id)
	if date.venue_scene == null and location == null:
		push_warning("No DateLocation '%s' in the world for date %s" % [date.location_id, date.date_id])
		return
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.busy:
		return
	# Lock land movement and other interactions during the date transition.
	_date_player = player
	player.busy = true
	_active = date
	_date_score = 0
	_date_choice_count = 0
	_last_reaction = ""
	last_date_outcome = ""
	date_started.emit(date)
	await _fade_to(1.0)
	# Unbooked developer-only dates may still use legacy time-jump behavior.
	if not is_booked(date) and date.when == DateData.When.NOW and date.jump_clock:
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
	# Match the original intro boat camera composition while we're there.
	# Only venues with a CameraFocus marker override normal follow mode.
	var camera_focus: Marker2D = venue.get_node_or_null("CameraFocus") as Marker2D
	if camera_focus != null:
		_date_camera = player.get_parent().get_node_or_null("CameraController") as WorldCameraController
		if _date_camera != null:
			_date_camera.snap_to(camera_focus.global_position)
	# An authored date venue may specify a shared foreground layer for its
	# characters. Keep them in World (no reparenting), and restore Penni's
	# original draw order along with her position when the date ends.
	var cast_layer: CanvasItem = venue.get_node_or_null("DateCastLayer") as CanvasItem
	var date_z_index: int = -1
	if cast_layer != null:
		date_z_index = cast_layer.z_index
	else:
		# Older cached boat scenes may not carry the optional marker, but
		# the actual animated hull still specifies its draw order.
		var boat_art: IntroBoatSprite = venue.get_node_or_null("Sprite") as IntroBoatSprite
		if boat_art != null:
			date_z_index = boat_art.z_index + 1
	if date_z_index >= 0:
		player.z_index = date_z_index
	# Recruited NPCs are data-only residents, not actors in the island world.
	# Dates and dock cutscenes use the exact same noninteractive land actor.
	_date_actor = NPCTemporaryActor.spawn(date.npc, player.get_parent(),
		_spot(venue, &"NpcSpot") + date.npc_feet_offset)
	if _date_actor != null:
		_date_actor.name = "DateGuest_" + String(date.npc.npc_id)
		if date_z_index >= 0:
			_date_actor.z_index = date_z_index
	await _fade_to(0.0)
	_in_dialogue = true
	DialogueManager.request_conversation(date.npc, date.dialogue_json)
	if not DialogueManager.is_active:
		push_warning("Date dialogue could not start: " + date.dialogue_json)
		_in_dialogue = false
		_finish(false)


# A date exposes the same three choices on every scene and jealousy tier.
# The current tier changes their score/reaction rather than hiding choices.
static func score_for_choice(style: String, tier: int, npc: NPCData = null) -> int:
	# Retain a default profile for older callers that do not pass an NPC.
	var profile := npc if npc != null else NPCData.new()
	return profile.date_score_for_style(style, tier)


static func jealousy_for_choice(style: String, tier: int) -> int:
	var row: Array = JEALOUSY_BY_STYLE.get(style, [])
	return int(row[clampi(tier, 0, 3)]) if not row.is_empty() else 0


static func outcome_for_score(score: int) -> String:
	if score < 0:
		return "bad"
	if score < 5:
		return "okay"
	if score < 10:
		return "good"
	return "great"


func _on_date_choice(npc: NPCData, choice: Dictionary) -> void:
	if not _in_dialogue or _active == null or npc != _active.npc:
		return
	var style := str(choice.get("date_style", ""))
	if not (style in ["bold", "playful", "reassure"]):
		return
	# Dates present authored choices without hidden affection/jealousy scores.
	_date_choice_count += 1
	_last_reaction = ""


func get_placeholder_reaction() -> String:
	return _last_reaction


func get_placeholder_outcome() -> String:
	var outcome := outcome_for_score(_date_score)
	return outcome


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
			node.z_index = entry[2]
	_restore.clear()
	if is_instance_valid(_date_camera):
		_date_camera.snap_to_player()
	_date_camera = null
	if is_instance_valid(_date_actor):
		_date_actor.queue_free()
	_date_actor = null
	if is_instance_valid(_venue):
		_venue.queue_free()
	_venue = null
	if is_instance_valid(_date_player):
		_date_player.busy = false
	_date_player = null
	if completed and date != null:
		var state: Dictionary = NPCManager.get_npc_state(date.npc.npc_id)
		var flags: Dictionary = state["flags"]
		flags[date.get_completed_flag()] = true
		for flag in date.flags_to_set:
			flags[flag] = true
		# Dates are authored scenes, not a scored affection minigame.
		last_date_score = 0
		last_date_outcome = "completed"
		# Repeating a date always scores again, but never farms individual
		# dialogue-choice affection. Successful completion prevents daily decay.
		AffectionManager.mark_date_completed(date.npc.npc_id, _date_day)
		_use_up_period()
	_active = null
	await _fade_to(0.0)
	if completed and date != null:
		date_finished.emit(date)


# Normal dialogue is free; only the date itself consumes the remaining
# period. Avoid double-spending if the clock already advanced.
func _use_up_period() -> void:
	if GameManager.get_day() == _date_day and GameManager.get_period() == _date_period:
		GameManager.spend_actions(GameManager.get_actions_left())


func _spot(venue: Node2D, marker: StringName) -> Vector2:
	var node := venue.get_node_or_null(NodePath(marker)) as Node2D
	return node.global_position if node != null else venue.global_position


func _move(node: Node2D, spot: Vector2) -> void:
	if node == null:
		return
	_restore.append([node, node.global_position, node.z_index])
	node.global_position = spot


func _find_location(location_id: StringName) -> DateLocation:
	for node in get_tree().get_nodes_in_group(LOCATION_GROUP):
		var location := node as DateLocation
		if location != null and location.location_id == location_id:
			return location
	return null


# --- Signals ---

# The ask-out JSON reads these flags when its choices are filtered.
func _on_conversation_started(npc: NPCData) -> void:
	if npc == null:
		return
	_conversation_day = GameManager.get_day()
	_conversation_period = GameManager.get_period()
	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
	for date in get_dates_for(npc.npc_id):
		flags[date.get_available_flag()] = can_ask(date)


func _on_conversation_finished(npc: NPCData) -> void:
	if _in_dialogue and _active != null and npc == _active.npc:
		_in_dialogue = false
		_finish(true)


func _on_scene_requested(npc: NPCData, scene_id: String) -> void:
	if npc == null or not scene_id.begins_with(SCENE_PREFIX):
		return
	# Format "date:<date_id>:<period>" is emitted by ask-out dialogue.
	var parts := scene_id.trim_prefix(SCENE_PREFIX).split(":")
	var date := get_date(StringName(parts[0]))
	if date == null or date.npc == null or date.npc.npc_id != npc.npc_id:
		return
	if parts.size() >= 2 and parts[1].is_valid_int():
		book_next_period(date, int(parts[1]), _conversation_day, _conversation_period)
	else:
		# Legacy ask-out scenes still book the next allowed slot.
		accept(date)


# --- Fade ---

func _build_fade() -> void:
	_fade = ScreenFade.new()
	add_child(_fade)


func _fade_to(alpha: float) -> void:
	await _fade.fade_to(alpha, FADE_DURATION)
