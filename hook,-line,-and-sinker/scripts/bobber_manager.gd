extends Node

signal collection_changed
signal equipped_changed(bobber: BobberData)

const DEFAULT_ID: StringName = &"default"
const SILAS_ID: StringName = &"silas"
const BARRACUDA_ID: StringName = &"barracuda"
const BARRACUDA_ROUTE_FLAG: StringName = &"barracuda_route_complete"
const STARTING_UNLOCKS: Array[StringName] = [&"default"]
# NPC routes and bobber rewards are session-only in this prototype.
const SILAS_ROUTE_FLAG: StringName = &"silas_route_complete"

var bobbers: Array[BobberData] = [
	preload("res://resources/bobbers/default.tres"),
	# Registered for future rewards, but starts locked.
	preload("res://resources/bobbers/silas.tres"),
	preload("res://resources/bobbers/barracuda.tres"),
]
var unlocked_ids: Array[StringName] = []
var equipped_id: StringName = DEFAULT_ID
# True only after Silas's post-scene gift dialogue in this session.
var silas_reward_claimed: bool = false
var barracuda_reward_claimed: bool = false


func _ready() -> void:
	unlocked_ids.clear()
	for id in STARTING_UNLOCKS:
		unlocked_ids.append(id)
	equipped_id = DEFAULT_ID
	silas_reward_claimed = false
	barracuda_reward_claimed = false


func get_bobber(id: StringName) -> BobberData:
	for entry in bobbers:
		if entry != null and entry.bobber_id == id:
			return entry
	return null


func _silas_route_completed() -> bool:
	var flags: Dictionary = NPCManager.get_npc_state(&"test_npc").get("flags", {})
	return bool(flags.get(SILAS_ROUTE_FLAG, false))


func _silas_available() -> bool:
	return silas_reward_claimed and unlocked_ids.has(SILAS_ID) and _silas_route_completed()


func _barracuda_route_completed() -> bool:
	var flags: Dictionary = NPCManager.get_npc_state(&"barracuda").get("flags", {})
	return bool(flags.get(BARRACUDA_ROUTE_FLAG, false))


func _barracuda_available() -> bool:
	return barracuda_reward_claimed and unlocked_ids.has(BARRACUDA_ID) and _barracuda_route_completed()


func get_unlocked_bobbers() -> Array[BobberData]:
	var result: Array[BobberData] = []
	for entry in bobbers:
		if entry != null and unlocked_ids.has(entry.bobber_id):
			if entry.bobber_id == SILAS_ID and not _silas_available():
				continue
			if entry.bobber_id == BARRACUDA_ID and not _barracuda_available():
				continue
			result.append(entry)
	return result


func get_equipped_bobber() -> BobberData:
	# Use the classic bobber until Silas's reward has been earned
	# in this playthrough.
	if equipped_id == SILAS_ID and not _silas_available():
		return get_bobber(DEFAULT_ID)
	if equipped_id == BARRACUDA_ID and not _barracuda_available():
		return get_bobber(DEFAULT_ID)
	return get_bobber(equipped_id)


func unlock_bobber(id: StringName) -> bool:
	if get_bobber(id) == null:
		return false
	# Only Silas's completed gift dialogue may make his bobber usable.
	if id == SILAS_ID:
		if not _silas_route_completed():
			return false
		var newly_earned := not silas_reward_claimed or not unlocked_ids.has(id)
		silas_reward_claimed = true
		if not unlocked_ids.has(id):
			unlocked_ids.append(id)
		collection_changed.emit()
		return newly_earned
	if id == BARRACUDA_ID:
		if not _barracuda_route_completed():
			return false
		var newly_earned := not barracuda_reward_claimed or not unlocked_ids.has(id)
		barracuda_reward_claimed = true
		if not unlocked_ids.has(id):
			unlocked_ids.append(id)
		collection_changed.emit()
		return newly_earned
	if unlocked_ids.has(id):
		return false
	unlocked_ids.append(id)
	collection_changed.emit()
	return true


func equip_bobber(id: StringName) -> bool:
	if not unlocked_ids.has(id) or get_bobber(id) == null:
		return false
	if id == SILAS_ID and not _silas_available():
		return false
	if id == BARRACUDA_ID and not _barracuda_available():
		return false
	if equipped_id == id:
		return true
	equipped_id = id
	equipped_changed.emit(get_equipped_bobber())
	return true
