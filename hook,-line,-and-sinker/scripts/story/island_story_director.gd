class_name IslandStoryDirector
extends Node

# Island event scheduler. SeaStoryDirector continues to own underwater beats.
# Morning NPC appearances are authored events, not a second romance scheduler.
signal story_event_started(event_id: StringName)
signal story_event_completed(event_id: StringName)

@export var events: Array[IslandStoryEventData] = []

var _player: Player
var _world: Node2D
var _transition: SeaDiveTransition
var _opening: FishCoOpeningSequence
var _camera: WorldCameraController
var _camera_moment_active: bool = false

var _completed: Dictionary = {}
var _last_played_day: Dictionary = {}
var _pending: Array[StringName] = []
var _active: IslandStoryEventData
var _resolving: bool = false
var _guest_actor: Node2D


func _ready() -> void:
	set_process(false)


func configure(player: Player, transition: SeaDiveTransition,
		opening: FishCoOpeningSequence) -> void:
	_player = player
	_world = player.get_parent() as Node2D
	_transition = transition
	_opening = opening
	_camera = _world.get_node("CameraController") as WorldCameraController
	GameManager.day_started.connect(_on_day_started)
	RecruitmentHandler.resident_assigned.connect(_on_resident_assigned)
	_opening.first_dive_onboarding_finished.connect(_refresh_eligible_events)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	_refresh_eligible_events()


# A story beat can call this with any authored Marker2D or world actor.
# Story owns the input lock; the camera controller only animates framing.
func play_camera_pan(target: Node2D, seconds: float = 0.8,
		hold_seconds: float = 0.0, return_seconds: float = 0.8) -> void:
	if not is_instance_valid(target) or not is_instance_valid(_player) \
			or not is_instance_valid(_camera) or _camera_moment_active:
		return
	_camera_moment_active = true
	var was_busy: bool = _player.busy
	_player.busy = true
	await _camera.pan_to(target.global_position, seconds)
	if hold_seconds > 0.0:
		await get_tree().create_timer(hold_seconds).timeout
	await _camera.return_to_player(return_seconds)
	if is_instance_valid(_player):
		_player.busy = was_busy
	_camera_moment_active = false


func has_completed(event_id: StringName) -> bool:
	return bool(_completed.get(event_id, false)) or _is_effect_already_applied(_get_event(event_id))


func has_pending(event_id: StringName) -> bool:
	return _pending.has(event_id)


# Only a new-day signal may queue morning events. A gift received during the
# afternoon cannot accidentally start an "on waking" conversation that night.
func _on_day_started(_day: int) -> void:
	for id in _pending.duplicate():
		var queued: IslandStoryEventData = _get_event(id)
		if queued != null and queued.morning_only:
			_pending.erase(id)
	var front: int = 0
	for event in events:
		if event != null and event.morning_only and _is_eligible(event):
			_pending.insert(front, event.event_id)
			front += 1
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
	if event.morning_only and not GameManager.is_period(GameManager.Times.MORNING):
		return false
	if event.retry_after_days > 0 and _last_played_day.has(event.event_id):
		if GameManager.get_day() - int(_last_played_day[event.event_id]) < event.retry_after_days:
			return false
	if event.requires_first_dive_onboarding \
			and (_opening == null or not _opening._first_dive_call_finished):
		return false
	if event.requires_resident and not _has_eligible_resident(event.days_after_resident):
		return false
	if event.speaker_must_be_resident and not RecruitmentHandler.is_resident(event.speaker.npc_id):
		return false
	var state: Dictionary = NPCManager.get_npc_state(event.speaker.npc_id)
	var flags: Dictionary = state.get("flags", {})
	for flag in event.required_flags:
		if not flags.get(flag, false):
			return false
	for flag in event.forbidden_flags:
		if flags.get(flag, false):
			return false
	if event.min_days_after_gift > 0:
		if not state.has("gift_received_day") or \
				GameManager.get_day() - int(state["gift_received_day"]) < event.min_days_after_gift:
			return false
	if event.respect_overnight_boundaries \
			and NPCManager.has_blocking_relationship_event(event.speaker, &"overnight"):
		return false
	return true


# Ordinary island events retain their original anytime scheduling.
func _refresh_eligible_events() -> void:
	if _player == null or _transition == null or _opening == null:
		return
	for event in events:
		if event == null or event.morning_only or event == _active \
				or _pending.has(event.event_id):
			continue
		if _is_eligible(event):
			_pending.append(event.event_id)
	set_process(not _pending.is_empty() and _active == null and not _resolving)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	if _active != null or _resolving or not _world_is_free():
		return
	var event: IslandStoryEventData = _get_event(_pending.pop_front())
	if not _is_eligible(event):
		set_process(not _pending.is_empty())
		return
	_active = event
	_player.busy = true
	set_process(false)
	_begin_event(event)


func _begin_event(event: IslandStoryEventData) -> void:
	if event.stage_land_actor:
		_present_guest(event)
	DialogueManager.request_conversation(event.speaker, event.dialogue_json)
	if not DialogueManager.is_active:
		push_warning("Island story event failed to open: %s" % event.event_id)
		_resolving = true
		_complete_event()
		return
	story_event_started.emit(event.event_id)


# Spawn the existing noninteractive land sprite in place beside Penni.
# No approach/exit movement: the morning sleep fade does the transition.
func _present_guest(event: IslandStoryEventData) -> void:
	_guest_actor = NPCTemporaryActor.spawn(event.speaker, _world,
		_player.global_position + event.guest_offset)
	if not is_instance_valid(_guest_actor):
		push_warning("Cannot stage morning story guest: %s" % event.event_id)
		return
	_guest_actor.name = "MorningStoryGuest_" + String(event.speaker.npc_id)
	var face: StringName = &"idle_l" if event.guest_offset.x < 0.0 else &"idle_r"
	if _player.animator.sprite_frames.has_animation(face):
		_player.animator.play(face)

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
	if _active == null or npc != _active.speaker or _resolving:
		return
	_resolving = true
	_complete_event()


func _complete_event() -> void:
	if _active == null:
		_resolving = false
		return
	var event: IslandStoryEventData = _active
	if is_instance_valid(_guest_actor):
		_guest_actor.queue_free()
		_guest_actor = null
	_active = null
	if event.retry_after_days > 0:
		_last_played_day[event.event_id] = GameManager.get_day()
	else:
		_completed[event.event_id] = true
	_apply_completion_effect(event.completion_effect)
	story_event_completed.emit(event.event_id)
	_refresh_eligible_events()
	# Treat simultaneous morning invitations as separate visits. Penni remains
	# input-locked while an actual fade separates their two dialogue scenes.
	if event.morning_only and _has_next_morning_event():
		await _fade_between_morning_events()
	_resolving = false
	if is_instance_valid(_player):
		_player.busy = false
	set_process(not _pending.is_empty())


func _has_next_morning_event() -> bool:
	for event_id in _pending:
		var event: IslandStoryEventData = _get_event(event_id)
		if event != null and event.morning_only and _is_eligible(event):
			return true
	return false


func _fade_between_morning_events() -> void:
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, 0.35)
	await get_tree().create_timer(0.15).timeout
	await fade.fade_to(0.0, 0.35)
	fade.queue_free()


func _apply_completion_effect(effect: StringName) -> void:
	match effect:
		&"unlock_gifts":
			ShopManager.unlock_gifts()
		&"":
			pass
		_:
			push_warning("Unhandled island story completion effect: %s" % effect)
