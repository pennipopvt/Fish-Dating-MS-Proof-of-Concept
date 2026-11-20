extends Node

# Relationship values are session-only in NPCManager state.
# Affection may dip below zero, triggering departure at the next morning.
# Jealousy ranges 0-100 with four tiers; only dates lower jealousy.
# After first romance, every day without a completed date incurs tier-based
# affection decay. Casual conversations do NOT prevent that decay.
# Placeholder dates evaluate three response styles against the jealousy tier.

signal affection_changed(npc_id: StringName, value: int, delta: int)
signal jealousy_changed(npc_id: StringName, value: int, delta: int)
signal npc_left(npc_id: StringName)

const MAX_AFFECTION := 100
const MAX_JEALOUSY := 100
const TONE_AMOUNTS := {"positive": 5, "neutral": 0, "negative": -3}
# 0-24, 25-49, 50-74, 75-100. Adjust after playtesting.
const DAILY_DECAY_BY_TIER := [2, 4, 6, 10]
const OTHER_ROMANCE_JEALOUSY := 45
const MISSED_DATE_JEALOUSY := 15
const FIRST_ROMANCE_DEADLINE_DAYS := 5
const RECRUITED_DAY_KEY := "recruited_day"
const RECRUITED_FLAG := &"Recruited"
const LAST_DATE_KEY := "last_date_day"
const JEALOUSY_KEY := "jealousy"
const ROMANCE_KEY := &"romance_complete"
# Keys in NPCManager's per-NPC state.
const PICKED_KEY := "picked_choices"
const LAST_TALK_KEY := "last_talk_day"
const NOTICE_OFFSET := Vector2(0, -44)

# NPC fish from the starting catch pool, to put back when an NPC leaves.
var _npc_fish: Array[FishData] = []
# NPCInteractable instance id -> the house Sprite2D it moved into.
var _homes: Dictionary = {}
var _leaving_checks_pending := false
var _messages: Array[Dictionary] = []
var _showing_message := false


func _ready() -> void:
	_connect_sources.call_deferred()


func _connect_sources() -> void:
	for fish in FishingManager.possible_catches:
		if fish != null and fish.npc_data != null and not _npc_fish.has(fish):
			_npc_fish.append(fish)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	GameManager.day_started.connect(_on_day_started)
	DateManager.date_missed.connect(_on_date_missed)
	RecruitmentHandler.npc_moved_into_home.connect(
		func(actor: NPCInteractable, home: Sprite2D) -> void: _homes[actor.get_instance_id()] = home)


# --- Value ---

func get_affection(npc_id: StringName) -> int:
	return int(NPCManager.get_npc_state(npc_id).get("attraction", NPCManager.START_ATTRACTION))


# Adds delta (capped at MAX_AFFECTION; no floor, below 0 makes a recruited NPC leave).
func change(npc_id: StringName, delta: int) -> void:
	if delta == 0 or npc_id == &"":
		return
	var state: Dictionary = NPCManager.get_npc_state(npc_id)
	var value: int = mini(get_affection(npc_id) + delta, MAX_AFFECTION)
	state["attraction"] = value
	affection_changed.emit(npc_id, value, delta)
	# Never trigger departure in the middle of a date or conversation.
	# _on_day_started() handles it on the following morning.


func set_affection(npc_id: StringName, value: int) -> void:
	change(npc_id, mini(value, MAX_AFFECTION) - get_affection(npc_id))


func get_jealousy(npc_id: StringName) -> int:
	return int(NPCManager.get_npc_state(npc_id).get(JEALOUSY_KEY, 0))


func get_jealousy_tier(npc_id: StringName) -> int:
	return mini(floori(float(get_jealousy(npc_id)) / 25.0), 3)


func change_jealousy(npc_id: StringName, delta: int) -> void:
	if npc_id == &"" or delta == 0:
		return
	var state: Dictionary = NPCManager.get_npc_state(npc_id)
	var prior := get_jealousy(npc_id)
	var next := clampi(prior + delta, 0, MAX_JEALOUSY)
	state[JEALOUSY_KEY] = next
	if next != prior:
		jealousy_changed.emit(npc_id, next, next - prior)


func set_jealousy(npc_id: StringName, value: int) -> void:
	change_jealousy(npc_id, clampi(value, 0, MAX_JEALOUSY) - get_jealousy(npc_id))


func has_completed_romance(npc_id: StringName) -> bool:
	var flags: Dictionary = NPCManager.get_npc_state(npc_id).get("flags", {})
	return bool(flags.get(ROMANCE_KEY, false)
		or flags.get(&"silas_route_complete", false)
		or flags.get(&"barracuda_route_complete", false))


# Called only once, after the first romance route's post-scene dialogue.
func on_romance_completed(npc_id: StringName) -> void:
	var state: Dictionary = NPCManager.get_npc_state(npc_id)
	var flags: Dictionary = state["flags"]
	if flags.get(ROMANCE_KEY, false):
		return
	# Existing romantic partners become jealous, not the new partner.
	for other_id: StringName in NPCManager.npc_states.keys():
		if other_id != npc_id and NPCManager.npc_states[other_id].get("flags", {}).get(RECRUITED_FLAG, false) and has_completed_romance(other_id):
			change_jealousy(other_id, OTHER_ROMANCE_JEALOUSY)
	flags[ROMANCE_KEY] = true


func on_recruited(npc_id: StringName) -> void:
	var state: Dictionary = NPCManager.get_npc_state(npc_id)
	if not has_completed_romance(npc_id):
		state[RECRUITED_DAY_KEY] = GameManager.get_day()


func mark_date_completed(npc_id: StringName, day: int) -> void:
	NPCManager.get_npc_state(npc_id)[LAST_DATE_KEY] = day


func _on_date_missed(date: DateData) -> void:
	if date != null and date.npc != null and has_completed_romance(date.npc.npc_id):
		change_jealousy(date.npc.npc_id, MISSED_DATE_JEALOUSY)


static func tone_amount(tone: String) -> int:
	return int(TONE_AMOUNTS.get(tone.to_lower(), 0))


# --- Dialogue choices ---

static func choice_key(dialogue_path: String, node_id: String, choice_text: String) -> String:
	return "%s#%s#%s" % [dialogue_path.get_file(), node_id, choice_text]


func was_picked(npc_id: StringName, key: String) -> bool:
	var picked: Dictionary = NPCManager.get_npc_state(npc_id).get(PICKED_KEY, {})
	return picked.has(key)


# Grey in the menu: picked before and not opted out.
func is_greyed(npc_id: StringName, key: String, choice: Dictionary) -> bool:
	return bool(choice.get("grey_when_picked", true)) and was_picked(npc_id, key)


# Affection a JSON choice gives: exact effects.attraction, else its tone.
static func choice_amount(choice: Dictionary) -> int:
	var effects: Variant = choice.get("effects", {})
	if effects is Dictionary and effects.has("attraction"):
		return int(effects["attraction"])
	return tone_amount(str(choice.get("tone", "neutral")))


# Called by DialogueManager when a picked choice takes effect. Affection only
# the first time; always remembered as picked.
func on_choice_picked(npc: NPCData, key: String, choice: Dictionary) -> void:
	if npc == null:
		return
	var state: Dictionary = NPCManager.get_npc_state(npc.npc_id)
	var picked: Dictionary = state.get(PICKED_KEY, {})
	state[PICKED_KEY] = picked
	var first_time := not picked.has(key)
	picked[key] = true
	if first_time:
		change(npc.npc_id, choice_amount(choice))


func clear_picked(npc_id: StringName) -> void:
	NPCManager.get_npc_state(npc_id).erase(PICKED_KEY)


# --- Daily decay ---

func _on_conversation_finished(npc: NPCData) -> void:
	if npc != null:
		NPCManager.get_npc_state(npc.npc_id)[LAST_TALK_KEY] = GameManager.get_day()


func _on_day_started(day: int) -> void:
	for npc_id: StringName in NPCManager.npc_states.keys():
		var state: Dictionary = NPCManager.npc_states[npc_id]
		if not state.get("flags", {}).get(RECRUITED_FLAG, false):
			continue
		# There are five days from recruitment to finish the first romance.
		# Recruited on day 1 => must complete it by the end of day 5.
		if not has_completed_romance(npc_id):
			var recruited_day: int = int(state.get(RECRUITED_DAY_KEY, day - 1))
			state[RECRUITED_DAY_KEY] = recruited_day
			if day - recruited_day >= FIRST_ROMANCE_DEADLINE_DAYS:
				leave(npc_id)
			elif day - recruited_day >= FIRST_ROMANCE_DEADLINE_DAYS - 2:
				show_message("ROMANCE DEADLINE", "%s has %d day(s) left" % [
					_display_name(npc_id), FIRST_ROMANCE_DEADLINE_DAYS - (day - recruited_day)
				])
			continue
		# Relationship upkeep starts after first romance. Talking never replaces dates.
		if int(state.get(LAST_DATE_KEY, -1)) == day - 1:
			continue
		var decay: int = DAILY_DECAY_BY_TIER[get_jealousy_tier(npc_id)]
		# Affection changes remain hidden from the player; only the underlying
		# relationship state changes. Don't announce daily decay numerically.
		change(npc_id, -decay)
	# Departures take place at the beginning of a day, never during dialogue.
	_check_leaving()


# --- Leaving ---

# Recruited NPCs below 0 leave, but never mid-conversation or mid-date.
func _check_leaving() -> void:
	if not is_inside_tree() or DialogueManager.is_active or DateManager.is_active():
		return
	for npc_id: StringName in NPCManager.npc_states.keys():
		var state: Dictionary = NPCManager.npc_states[npc_id]
		if state.get("flags", {}).get(RECRUITED_FLAG, false) and get_affection(npc_id) < 0:
			leave(npc_id)


func leave(npc_id: StringName) -> void:
	var state: Dictionary = NPCManager.get_npc_state(npc_id)
	state["flags"][RECRUITED_FLAG] = false
	state["attraction"] = NPCManager.START_ATTRACTION
	state.erase(LAST_TALK_KEY)
	state.erase(LAST_DATE_KEY)
	state.erase(RECRUITED_DAY_KEY)
	state[JEALOUSY_KEY] = 0
	state["flags"].erase(ROMANCE_KEY)
	# A recaught NPC must complete the first-romance route again before dates.
	for flag in [&"silas_route_complete", &"barracuda_route_complete",
		&"house_invitation_accepted", &"barracuda_invitation_accepted"]:
		state["flags"].erase(flag)
	for date: DateData in DateManager.get_dates_for(npc_id):
		DateManager.cancel_booking(date)
	var npc_name := _display_name(npc_id)
	var actor := _find_actor(npc_id)
	_return_fish(npc_id, actor)
	if actor != null:
		_free_home(actor)
		RecruitmentHandler.waiting_npcs.erase(actor)
		_jump_into_ocean(actor)
	print("[Affection] %s went back to the sea" % npc_name)
	show_message("DEPARTURE", "%s went back to the sea" % npc_name)
	npc_left.emit(npc_id)


func _free_home(actor: NPCInteractable) -> void:
	var home := _homes.get(actor.get_instance_id()) as Sprite2D
	_homes.erase(actor.get_instance_id())
	if not is_instance_valid(home):
		return
	# Put the empty-house texture back (from the house's own scene).
	if not home.scene_file_path.is_empty():
		var scene := load(home.scene_file_path) as PackedScene
		var fresh := scene.instantiate() as Sprite2D if scene != null else null
		if fresh != null:
			home.texture = fresh.texture
			fresh.free()
	# RecruitmentHandler.register_available_home(home)


func _return_fish(npc_id: StringName, actor: NPCInteractable) -> void:
	for fish in _npc_fish:
		if FishingManager.possible_catches.has(fish):
			continue
		if _fish_npc_id(fish, actor) == npc_id:
			FishingManager.possible_catches.append(fish)


func _fish_npc_id(fish: FishData, actor: NPCInteractable) -> StringName:
	if actor != null and actor.scene_file_path == fish.npc_data.resource_path:
		return actor.npc.npc_id if actor.npc != null else &""
	var instance := fish.npc_data.instantiate()
	var id: StringName = &""
	if instance is NPCInteractable and instance.npc != null:
		id = instance.npc.npc_id
	instance.free()
	return id


# Placeholder exit: a hop, then fade away while dropping.
func _jump_into_ocean(actor: NPCInteractable) -> void:
	var start := actor.global_position
	var tween := actor.create_tween()
	tween.tween_property(actor, "global_position", start + Vector2(0, -14), 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor, "global_position", start + Vector2(0, 24), 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(actor, "modulate:a", 0.0, 0.4)
	tween.tween_callback(actor.queue_free)


func _find_actor(npc_id: StringName) -> NPCInteractable:
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var actor := node as NPCInteractable
		if actor != null and actor.npc != null and actor.npc.npc_id == npc_id and not actor.is_queued_for_deletion():
			return actor
	return null


func _display_name(npc_id: StringName) -> String:
	var actor := _find_actor(npc_id)
	if actor != null and actor.npc != null and not actor.npc.display_name.is_empty():
		return actor.npc.display_name
	for fish in _npc_fish:
		var instance := fish.npc_data.instantiate()
		var npc: NPCData = instance.npc if instance is NPCInteractable else null
		instance.free()
		if npc != null and npc.npc_id == npc_id and not npc.display_name.is_empty():
			return npc.display_name
	return String(npc_id)


# --- Messages (challenge-notice bubble above Penni, one at a time) ---

func show_message(subtitle: String, text: String) -> void:
	_messages.append({"subtitle": subtitle, "text": text})
	if not _showing_message:
		_show_messages()


func _show_messages() -> void:
	_showing_message = true
	while not _messages.is_empty():
		# Wait out sleep fades, dialogue and menus so the message is seen.
		while is_inside_tree() and GameManager.is_inside_tree() and GameManager.is_modal_ui_open():
			await get_tree().process_frame
		if not is_inside_tree():
			break
		var player := get_tree().get_first_node_in_group(&"player") as Node2D
		var message: Dictionary = _messages.pop_front()
		if player == null:
			continue
		var notice := ChallengeNotice.new()
		notice.subtitle = message["subtitle"]
		notice.title = message["text"]
		notice.position = NOTICE_OFFSET
		player.add_child(notice)
		await notice.tree_exited
	_showing_message = false
