extends Node

# The acceptance and housing boundary. NPCManager holds the sole authoritative
# assignment (room_id -> NPC identity is derived from per-NPC state).
# No ordinary resident actor exists in World, and no actor is teleported.
signal fade_to() # Retained for existing illustration/cutscene listeners.
signal resident_assigned(npc_id: StringName, room_id: StringName)
signal resident_vacated(npc_id: StringName, room_id: StringName)
# Legacy hooks retained for catch and dev callers during migration.
signal npc_waiting_for_home(actor: NPCInteractable)
signal npc_moved_into_home(actor: NPCInteractable, home: Area2D)

var listening: bool = false
var npc: NPCInteractable = null
var pending_fish: FishData = null
var available_homes: Array[Area2D] = []
var waiting_npcs: Array[NPCInteractable] = [] # Deprecated: never keep actors on shore.
var time_to_transfer: float = 0.0 # Deprecated; actor moves are removed.

var _all_doors: Array[TransferDoor] = []
var _waiting_residents: Array[NPCData] = []


func _ready() -> void:
	DialogueManager.conversation_finished.connect(check_for_recruitment)


# A catch-scene actor only exists long enough to show its initial dialogue.
func engage_listen(actor: NPCInteractable, caught_fish: FishData = null) -> void:
	npc = actor
	pending_fish = caught_fish
	listening = _actor_valid(actor)


func check_for_recruitment(finished_npc: NPCData) -> void:
	if not listening:
		return
	listening = false
	var actor: NPCInteractable = npc
	var fish: FishData = pending_fish
	npc = null
	pending_fish = null
	if not _actor_valid(actor) or actor.npc != finished_npc:
		return
	if not NPCManager.get_npc_state(finished_npc.npc_id)["flags"].get(&"Recruited", false):
		if finished_npc.npc_id == &"barracuda":
			_barracuda_return_to_water(actor)
		else:
			actor.queue_free()
		return
	_finalize_recruitment(actor, fish)


func recruit_actor_for_debug(actor: NPCInteractable, fish: FishData) -> bool:
	if not _actor_valid(actor) or actor.npc == null or fish == null or fish.npc_data == null:
		return false
	if actor.scene_file_path != fish.npc_data.resource_path:
		return false
	var flags: Dictionary = NPCManager.get_npc_state(actor.npc.npc_id)["flags"]
	if flags.get(&"Recruited", false):
		return false
	flags[&"Recruited"] = true
	if npc == actor:
		npc = null
		pending_fish = null
		listening = false
	_finalize_recruitment(actor, fish)
	return true


func _finalize_recruitment(actor: NPCInteractable, fish: FishData) -> void:
	if not _actor_valid(actor) or actor.npc == null:
		return
	var data: NPCData = actor.npc
	NPCManager.get_npc_state(data.npc_id)["flags"][&"Recruited"] = true
	FishingManager.remove_recruited_catch(fish)
	ShopManager.gifts_unlocked = true
	# Deliberately do not call AffectionManager.on_recruited here:
	# housing isn't a romantic commitment or a romance deadline.
	assign_home(data)
	actor.queue_free()


func _barracuda_return_to_water(actor: NPCInteractable) -> void:
	if not _actor_valid(actor):
		return
	var start: Vector2 = actor.global_position
	var water: ColorRect = actor.get_parent().get_node_or_null("Water") as ColorRect
	var y: float = water.global_position.y if water != null else start.y + 40.0
	var landing: Vector2 = Vector2(start.x - 20.0, maxf(y + 18.0, start.y + 38.0))
	var tween: Tween = actor.create_tween()
	tween.tween_property(actor, "global_position", start + Vector2(-11.0, -13.0), 0.16)
	tween.tween_property(actor, "global_position", landing, 0.28)
	tween.tween_callback(actor.queue_free)


# Called once from the existing AvailableHomeInfo node.
func set_available_homes(homes: Array[Area2D]) -> void:
	_all_doors.clear()
	available_homes.clear()
	for home in homes:
		var door: TransferDoor = home as TransferDoor
		if door == null or _all_doors.has(door):
			continue
		_all_doors.append(door)
		_sync_door(door)
	_try_place_waiting_residents()


func register_available_home(home: Area2D) -> void:
	var door: TransferDoor = home as TransferDoor
	if door == null:
		return
	if not _all_doors.has(door):
		_all_doors.append(door)
	_sync_door(door)
	_try_place_waiting_residents()


func _sync_door(door: TransferDoor) -> void:
	if not is_instance_valid(door):
		return
	var resident: NPCData = get_resident(door.get_room_id())
	if resident != null:
		door.set_resident(resident)
		available_homes.erase(door)
	else:
		door.clear_resident()
		if not available_homes.has(door):
			available_homes.append(door)


func get_resident(room_id: StringName) -> NPCData:
	for id: StringName in NPCManager.npc_states.keys():
		var state: Dictionary = NPCManager.npc_states[id]
		if StringName(str(state.get("room_id", ""))) == room_id:
			return state.get("resident_data") as NPCData
	return null


func get_room_id(npc_id: StringName) -> StringName:
	return StringName(str(NPCManager.get_npc_state(npc_id).get("room_id", "")))


func is_resident(npc_id: StringName) -> bool:
	return get_room_id(npc_id) != &""


# Used by story cutscenes or accepted catches. Room selection is data-only.
func assign_home(resident: NPCData, preferred_room_id: StringName = &"") -> bool:
	if resident == null or resident.npc_id == &"":
		return false
	if is_resident(resident.npc_id):
		return true
	var chosen: TransferDoor = null
	for home in available_homes:
		var door: TransferDoor = home as TransferDoor
		if is_instance_valid(door) and (preferred_room_id == &"" or door.get_room_id() == preferred_room_id):
			chosen = door
			break
	if chosen == null:
		if not _waiting_residents.has(resident):
			_waiting_residents.append(resident)
		return false
	var state: Dictionary = NPCManager.get_npc_state(resident.npc_id)
	state["room_id"] = chosen.get_room_id()
	state["resident_data"] = resident
	# Existing encounter JSON uses Recruited as its eligibility flag. Keep
	# that compatibility until content is migrated; do not start romance.
	state["flags"][&"Recruited"] = true
	_waiting_residents.erase(resident)
	# A resident NPC can no longer appear as a wild catch. Other fish stay.
	for fish in FishingManager.possible_catches.duplicate():
		if fish == null or fish.npc_data == null:
			continue
		var preview: NPCInteractable = fish.npc_data.instantiate() as NPCInteractable
		var match_id: bool = preview != null and preview.npc != null and preview.npc.npc_id == resident.npc_id
		if preview != null:
			preview.free()
		if match_id:
			FishingManager.remove_recruited_catch(fish)
			break
	_sync_door(chosen)
	resident_assigned.emit(resident.npc_id, chosen.get_room_id())
	return true


func vacate_home(npc_id: StringName) -> void:
	var room_id: StringName = get_room_id(npc_id)
	if room_id == &"":
		for data in _waiting_residents.duplicate():
			if data.npc_id == npc_id:
				_waiting_residents.erase(data)
		return
	var state: Dictionary = NPCManager.get_npc_state(npc_id)
	state.erase("room_id")
	state.erase("resident_data")
	state["flags"][&"Recruited"] = false
	for door in _all_doors:
		if is_instance_valid(door) and door.get_room_id() == room_id:
			_sync_door(door)
	resident_vacated.emit(npc_id, room_id)
	_try_place_waiting_residents()


func _try_place_waiting_residents() -> void:
	for resident in _waiting_residents.duplicate():
		if available_homes.is_empty():
			break
		assign_home(resident)


# Dev panel compatibility: the captured NPC actor is not moved anywhere.
func house_recruit(_house_art: Texture2D) -> void:
	if _actor_valid(npc):
		_finalize_recruitment(npc, pending_fish)
		npc = null
		pending_fish = null
		listening = false


func reset_runtime_state() -> void:
	listening = false
	npc = null
	pending_fish = null
	waiting_npcs.clear()
	_waiting_residents.clear()
	for door in _all_doors:
		if is_instance_valid(door):
			_sync_door(door)


func _actor_valid(actor: NPCInteractable) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion()
