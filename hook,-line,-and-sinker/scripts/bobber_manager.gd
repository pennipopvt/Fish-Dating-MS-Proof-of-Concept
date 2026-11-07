extends Node

signal collection_changed
signal equipped_changed(bobber: BobberData)

const SAVE_PATH := "user://bobbers.cfg"
const DEFAULT_ID: StringName = &"default"
const SILAS_ID: StringName = &"silas"
# V1 removes original development-only grants from existing test saves.
const SAVE_VERSION := 1
const STARTING_UNLOCKS: Array[StringName] = [&"default"]

var bobbers: Array[BobberData] = [
	preload("res://resources/bobbers/default.tres"),
	# The reward already exists on disk, but must be registered to unlock.
	preload("res://resources/bobbers/silas.tres"),
]
var unlocked_ids: Array[StringName] = []
var equipped_id: StringName = DEFAULT_ID


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


func get_unlocked_bobbers() -> Array[BobberData]:
	var result: Array[BobberData] = []
	for entry in bobbers:
		if entry != null and unlocked_ids.has(entry.bobber_id):
			result.append(entry)
	return result


func get_equipped_bobber() -> BobberData:
	return get_bobber(equipped_id)


func unlock_bobber(id: StringName) -> bool:
	if get_bobber(id) == null or unlocked_ids.has(id):
		return false
	unlocked_ids.append(id)
	collection_changed.emit()
	_save_selection()
	return true


func equip_bobber(id: StringName) -> bool:
	if not unlocked_ids.has(id) or get_bobber(id) == null:
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
	config.save(SAVE_PATH)


func _load_selection() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	# Older builds granted Silas and the duplicate bobber for testing.
	# Migrate that test collection once without altering future rewards.
	if int(config.get_value("bobbers", "version", 0)) < SAVE_VERSION:
		unlocked_ids.clear()
		unlocked_ids.append(DEFAULT_ID)
		equipped_id = DEFAULT_ID
		_save_selection()
		return
	for value in config.get_value("bobbers", "unlocked", []):
		var id := StringName(str(value))
		if get_bobber(id) != null and not unlocked_ids.has(id):
			unlocked_ids.append(id)
	var selected := StringName(str(config.get_value("bobbers", "equipped", "default")))
	if unlocked_ids.has(selected) and get_bobber(selected) != null:
		equipped_id = selected
