class_name IslandStoryDirector
extends Node

# Island-wide one-time event scheduler. SeaStoryDirector still exclusively
# handles underwater choreography. This director only decides *when* to play
# an authored dialogue and *which* system to notify on completion.
signal story_event_started(event_id: StringName)
signal story_event_completed(event_id: StringName)

@export var events: Array[IslandStoryEventData] = []

var _player: Player
var _transition: SeaDiveTransition
var _opening: FishCoOpeningSequence

var _completed: Dictionary = {}
var _pending: Array[StringName] = []
var _active: IslandStoryEventData


func _ready() -> void:
	set_process(false)


func configure(player: Player, transition: SeaDiveTransition,
		opening: FishCoOpeningSequence) -> void:
	_player = player
	_transition = transition
	_opening = opening
	GameManager.day_started.connect(_on_day_started)
	RecruitmentHandler.resident_assigned.connect(_on_resident_assigned)
	_opening.first_dive_onboarding_finished.connect(_refresh_eligible_events)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	_refresh_eligible_events()


func has_completed(event_id: StringName) -> bool:
	return bool(_completed.get(event_id, false)) or _is_effect_already_applied(_get_event(event_id))


func has_pending(event_id: StringName) -> bool:
	return _pending.has(event_id)


func _on_day_started(_day: int) -> void:
	_refresh_eligible_events()


func _on_resident_assigned(_npc_id: StringName, _room_id: StringName) -> void:
	_refresh_eligible_events()


func _get_event(event_id: StringName) -> IslandStoryEventData:
	for event in events:
		if event != null and event.event_id == event_id:
			return event
	return null


func _is_effect_already_applied(event: IslandStoryEventData) -> bool:
	if event == null:
		return false
	match event.completion_effect:
		&"unlock_gifts":
			return ShopManager.gifts_unlocked
	return false


func _has_eligible_resident(minimum_days: int) -> bool:
	for state in NPCManager.npc_states.values():
		if not state.get("flags", {}).get(&"Recruited", false):
			continue
		if StringName(str(state.get("room_id", ""))) == &"":
			continue
		var moved_in_day: int = int(state.get("room_assigned_day", GameManager.get_day()))
		if GameManager.get_day() - moved_in_day >= minimum_days:
			return true
	return false


func _is_eligible(event: IslandStoryEventData) -> bool:
	if event == null or event.event_id == &"" or event.speaker == null \
			or event.dialogue_json.is_empty() or has_completed(event.event_id):
		return false
	if GameManager.get_day() < event.earliest_day:
		return false
	if event.requires_first_dive_onboarding \
			and (_opening == null or not _opening._first_dive_call_finished):
		return false
	if event.requires_resident and not _has_eligible_resident(event.days_after_resident):
		return false
	return true


func _refresh_eligible_events() -> void:
	if _player == null or _transition == null or _opening == null:
		return
	for event in events:
		if event == null or event == _active or _pending.has(event.event_id):
			continue
		if _is_eligible(event):
			_pending.append(event.event_id)
	# Remain dormant until an eligible event actually needs presenting.
	set_process(not _pending.is_empty())


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	if _active != null or not _world_is_free():
		return
	var event: IslandStoryEventData = _get_event(_pending.pop_front())
	if event == null or has_completed(event.event_id):
		set_process(not _pending.is_empty())
		return
	_active = event
	_player.busy = true
	DialogueManager.request_conversation(event.speaker, event.dialogue_json)
	if not DialogueManager.is_active:
		# A broken dialogue file cannot permanently gate the shop. This matches
		# the pre-refactor onboarding fallback, and surfaces the authoring error.
		push_warning("Island story event failed to open: %s" % event.event_id)
		_finish_event()
		return
	story_event_started.emit(event.event_id)
	set_process(false)


func _world_is_free() -> bool:
	return _player != null and is_instance_valid(_player) \
		and not _player.busy \
		and not _transition.transitioning and not _transition.underwater \
		and not GameManager.diving_session_active \
		and not DialogueManager.is_active \
		and not DateManager.is_active() \
		and not ShopManager.is_shop_open \
		and not GameManager.is_modal_ui_open()


func _on_conversation_finished(npc: NPCData) -> void:
	if _active == null or npc != _active.speaker:
		return
	_finish_event()


func _finish_event() -> void:
	if _active == null:
		return
	var event: IslandStoryEventData = _active
	_active = null
	_completed[event.event_id] = true
	if is_instance_valid(_player):
		_player.busy = false
	_apply_completion_effect(event.completion_effect)
	story_event_completed.emit(event.event_id)
	# Queue other eligible beats after the current dialogue has completely
	# ended. The one-time completion guard prevents repeat calls.
	_refresh_eligible_events.call_deferred()


func _apply_completion_effect(effect: StringName) -> void:
	match effect:
		&"unlock_gifts":
			ShopManager.unlock_gifts()
		&"":
			pass
		_:
			push_warning("Unhandled island story completion effect: %s" % effect)
