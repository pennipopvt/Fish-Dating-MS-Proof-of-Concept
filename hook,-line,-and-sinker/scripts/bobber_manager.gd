extends Node

signal collection_changed
signal equipped_changed(bobber: BobberData)

const SAVE_PATH := "user://bobbers.cfg"
const DEFAULT_ID: StringName = &"default"
const SILAS_ID: StringName = &"silas"
# V2 fixes old test saves that silently retained the Silas bobber unlock.
# Future real rewards carry explicit provenance and survive restarts.
const SAVE_VERSION := 2
const STARTING_UNLOCKS: Array[StringName] = [&"default"]
# The NPC story is currently session-local. Do not let a persisted bobber
# unlock appear in a new run before Silas's reward dialogue has finished.
const SILAS_ROUTE_FLAG: StringName = &"silas_route_complete"

# Can be overridden by isolated tests; production uses the normal save.
var save_path: String = SAVE_PATH

var bobbers: Array[BobberData] = [
	preload("res://resources/bobbers/default.tres"),
	# The reward already exists on disk, but must be registered to unlock.
	preload("res://resources/bobbers/silas.tres"),
]
var unlocked_ids: Array[StringName] = []
var equipped_id: StringName = DEFAULT_ID
# True only after Silas's actual reward is granted, never just because
# his bobber resource is registered or listed in an old test save.
var silas_reward_claimed: bool = false


func _ready() -> void:
	for id in STARTING_UNLOCKS:
		if not unlocked_ids.has(id):
			unlocked_ids.append(id)
	_load_selection()


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


func get_unlocked_bobbers() -> Array[BobberData]:
	var result: Array[BobberData] = []
	for entry in bobbers:
		if entry != null and unlocked_ids.has(entry.bobber_id):
			if entry.bobber_id == SILAS_ID and not _silas_available():
				continue
			result.append(entry)
	return result


func get_equipped_bobber() -> BobberData:
	# A previous save may have Silas equipped. Always use the classic
	# bobber until his reward has been earned in this playthrough.
	if equipped_id == SILAS_ID and not _silas_available():
		return get_bobber(DEFAULT_ID)
	return get_bobber(equipped_id)


func unlock_bobber(id: StringName) -> bool:
	if get_bobber(id) == null:
		return false
	# Only Silas's actual completed gift dialogue is allowed to make the
	# bobber usable. A stale saved unlock isn't enough on its own.
	if id == SILAS_ID:
		if not _silas_route_completed():
			return false
		var newly_earned := not silas_reward_claimed or not unlocked_ids.has(id)
		silas_reward_claimed = true
		if not unlocked_ids.has(id):
			unlocked_ids.append(id)
		# Emit even for previously saved rewards, so the shelf refreshes
		# after the completion flag is restored for this playthrough.
		collection_changed.emit()
		_save_selection()
		return newly_earned
	if unlocked_ids.has(id):
		return false
	unlocked_ids.append(id)
	collection_changed.emit()
	_save_selection()
	return true


func equip_bobber(id: StringName) -> bool:
	if not unlocked_ids.has(id) or get_bobber(id) == null:
		return false
	if id == SILAS_ID and not _silas_available():
		return false
	if equipped_id == id:
		return true
	equipped_id = id
	_save_selection()
	equipped_changed.emit(get_equipped_bobber())
	return true


func _save_selection() -> void:
	var config := ConfigFile.new()
	config.set_value("bobbers", "version", SAVE_VERSION)
	config.set_value("bobbers", "equipped", String(equipped_id))
	config.set_value("bobbers", "unlocked", Array(unlocked_ids).map(func(id): return String(id)))
	config.set_value("bobbers", "silas_reward_claimed", silas_reward_claimed)
	config.save(save_path)


func _load_selection() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	_restore_selection(config)


# Separate parsing so tests can simulate old and new saves without touching
# the player's user://bobbers.cfg.
func _restore_selection(config: ConfigFile, persist_migration: bool = true) -> void:
	unlocked_ids.clear()
	unlocked_ids.append(DEFAULT_ID)
	equipped_id = DEFAULT_ID
	silas_reward_claimed = false

	# Previous builds had a development-only Silas unlock saved under v1.
	# There is no way to distinguish those from actual rewards in that save
	# format, so retire the old grants once. New earned rewards are recorded
	# explicitly with silas_reward_claimed in v2.
	if int(config.get_value("bobbers", "version", 0)) < SAVE_VERSION:
		if persist_migration:
			_save_selection()
		return

	silas_reward_claimed = bool(config.get_value("bobbers", "silas_reward_claimed", false))
	for value in config.get_value("bobbers", "unlocked", []):
		var id := StringName(str(value))
		if id == SILAS_ID and not silas_reward_claimed:
			continue
		if get_bobber(id) != null and not unlocked_ids.has(id):
			unlocked_ids.append(id)

	# Don't leave Silas's bobber equipped if a legacy save had it selected.
	var selected := StringName(str(config.get_value("bobbers", "equipped", "default")))
	if unlocked_ids.has(selected) and get_bobber(selected) != null:
		if selected != SILAS_ID or _silas_available():
			equipped_id = selected
