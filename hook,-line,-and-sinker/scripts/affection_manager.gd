extends Node

# Affection (autoload "AffectionManager"). The value itself is NPCManager's
# per-NPC "attraction" (starts at NPCManager.START_ATTRACTION); every change
# should go through change() so the cap, signals and leaving rule apply.
#
# - Dialogue choices: a JSON choice can set "tone": "positive" | "neutral" |
#   "negative" (+5 / 0 / -3), or an exact "attraction" number in its effects.
#   Each choice gives affection only the first time it's picked; after that
#   DialogueUI shows it greyed out (still pickable). Picked choices are
#   remembered per NPC. A choice with "grey_when_picked": false never greys.
# - Dates add DateData.attraction_change (positive by default).
# - Each morning, a recruited NPC Penni didn't finish a conversation (or date)
#   with during the whole previous day loses DAILY_DECAY.
# - Below 0, a recruited NPC jumps back into the ocean: Recruited is cleared
#   (other story flags and picked choices stay), affection resets to the start
#   value, their house is freed and their fish goes back into the catch pool.
# Morning/leaving messages pop up above Penni in the challenge-notice bubble.
# State is in memory only, like the rest of NPC state.

signal affection_changed(npc_id: StringName, value: int, delta: int)
signal npc_left(npc_id: StringName)

const MAX_AFFECTION := 100
const TONE_AMOUNTS := {"positive": 5, "neutral": 0, "negative": -3}
const DAILY_DECAY := 2
const RECRUITED_FLAG := &"Recruited"
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
	DateManager.date_finished.connect(func(_date: DateData) -> void: _check_leaving())
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
	if value < 0:
		_check_leaving.call_deferred()


func set_affection(npc_id: StringName, value: int) -> void:
	change(npc_id, mini(value, MAX_AFFECTION) - get_affection(npc_id))


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
	_check_leaving.call_deferred()


func _on_day_started(day: int) -> void:
	for npc_id: StringName in NPCManager.npc_states.keys():
		var state: Dictionary = NPCManager.npc_states[npc_id]
		if not state.get("flags", {}).get(RECRUITED_FLAG, false):
			continue
		# First check for an NPC never talked to (e.g. dev shortcuts): start counting now.
		if not state.has(LAST_TALK_KEY):
			state[LAST_TALK_KEY] = day - 1
			continue
		if int(state[LAST_TALK_KEY]) >= day - 1:
			continue
		change(npc_id, -DAILY_DECAY)
		show_message("AFFECTION -%d" % DAILY_DECAY, "%s felt ignored yesterday" % _display_name(npc_id))


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
	var npc_name := _display_name(npc_id)
	var actor := _find_actor(npc_id)
	_return_fish(npc_id, actor)
	if actor != null:
		_free_home(actor)
		RecruitmentHandler.waiting_npcs.erase(actor)
		_jump_into_ocean(actor)
	print("[Affection] %s went back to the sea" % npc_name)
	show_message("AFFECTION BELOW 0", "%s went back to the sea" % npc_name)
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
	RecruitmentHandler.register_available_home(home)


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
