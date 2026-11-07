extends SceneTree

# Regression for ChallengeManager's FishData catch signal and Silas's bobber.
# Run from the Godot project folder:
# godot --headless --path . -s res://tests/challenges_bobber_reward_test.gd
# Uses isolated manager instances; does not alter the player's save files.

const FishingManagerScript = preload("res://scripts/fishing_manager.gd")
const BobberManagerScript = preload("res://scripts/bobber_manager.gd")
const EASY_FISH: FishData = preload("res://resources/fish/easy_test_fish.tres")
const SILAS_FISH: FishData = preload("res://resources/fish/test_silas.tres")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	# A typed FishData catch signal must reach challenge listeners.
	var fish_manager: Variant = FishingManagerScript.new()
	var seen: Array[FishData] = []
	var streak := ChallengeData.new()
	streak.target_amount = 2
	var listener := func(fish: FishData) -> void:
		seen.append(fish)
		streak.record_catch(fish)
	fish_manager.fish_caught.connect(listener)

	fish_manager.catch_fish(EASY_FISH)
	_expect(seen.size() == 1 and seen[0] == EASY_FISH, "ordinary catch emits FishData")
	_expect(streak.progress == 1, "a normal catch advances the streak")
	_expect(fish_manager.current_storage.size() == 1, "ordinary fish goes into storage")

	# An NPC that was successfully landed also counts, but is not an item.
	fish_manager.catch_fish(SILAS_FISH, false)
	_expect(seen.size() == 2 and seen[1] == SILAS_FISH, "NPC catch emits FishData")
	_expect(streak.progress == 2, "an NPC catch advances the streak")
	_expect(fish_manager.current_storage.size() == 1, "NPC catch adds no storage item")
	_expect(fish_manager.catch_dex.has(SILAS_FISH), "NPC catch appears in catch history")
	fish_manager.free()

	# A resource can be registered and even present in a previous save
	# without appearing before Silas completes this playthrough's route.
	const TEMP_SAVE: String = "user://bobber_session_unlock_test.cfg"
	var bobber_manager: Variant = BobberManagerScript.new()
	bobber_manager.save_path = TEMP_SAVE
	var npc_id: StringName = &"test_npc"
	var had_npc_state: bool = NPCManager.npc_states.has(npc_id)
	var original_state: Dictionary = NPCManager.get_npc_state(npc_id).duplicate(true)
	var flags: Dictionary = NPCManager.get_npc_state(npc_id)["flags"]
	flags.erase(&"silas_route_complete")
	var silas: BobberData = bobber_manager.get_bobber(&"silas")
	_expect(silas != null, "Silas's spyglass bobber is registered")
	if silas != null:
		_expect(silas.sprite != null, "Silas's bobber has a texture")
		_expect(not bobber_manager.get_unlocked_bobbers().has(silas), "fresh playthrough starts with Silas bobber locked")
		_expect(not bobber_manager.unlock_bobber(&"silas"), "can't unlock Silas's bobber before story completion")

		var legacy_save := ConfigFile.new()
		legacy_save.set_value("bobbers", "version", 1)
		legacy_save.set_value("bobbers", "unlocked", ["default", "silas"])
		legacy_save.set_value("bobbers", "equipped", "silas")
		bobber_manager._restore_selection(legacy_save, false)
		_expect(not bobber_manager.get_unlocked_bobbers().has(silas), "legacy test save cannot auto-unlock Silas")
		_expect(bobber_manager.equipped_id == &"default", "legacy selection becomes classic bobber")

		var rewarded_save := ConfigFile.new()
		rewarded_save.set_value("bobbers", "version", 2)
		rewarded_save.set_value("bobbers", "unlocked", ["default", "silas"])
		rewarded_save.set_value("bobbers", "silas_reward_claimed", true)
		rewarded_save.set_value("bobbers", "equipped", "silas")
		bobber_manager._restore_selection(rewarded_save, false)
		_expect(not bobber_manager.get_unlocked_bobbers().has(silas), "prior-run reward stays hidden before Silas's new route")
		_expect(bobber_manager.get_equipped_bobber().bobber_id == &"default", "prior-run equipped Spyglass falls back to classic")

		# The actual post-scene gift call only succeeds AFTER route completion.
		flags[&"silas_route_complete"] = true
		bobber_manager.unlock_bobber(&"silas")
		_expect(bobber_manager.get_unlocked_bobbers().has(silas), "reward dialogue reveals the Spyglass on the shelf")
		_expect(bobber_manager.equip_bobber(&"silas"), "earned Spyglass is equipable")

		# Simulate a full restart: restore a v2 file that explicitly says the
		# Spyglass was claimed, but with no Silas story progress in this run.
		flags.erase(&"silas_route_complete")
		var next_run: Variant = BobberManagerScript.new()
		next_run.save_path = TEMP_SAVE
		next_run._load_selection()
		_expect(not next_run.get_unlocked_bobbers().has(silas), "restart with earned save still starts with Silas locked")
		_expect(next_run.get_equipped_bobber().bobber_id == &"default", "restart falls back to classic bobber")
		_expect(not next_run.equip_bobber(&"silas"), "restart cannot equip the old Spyglass")
		next_run.free()

	if had_npc_state:
		NPCManager.npc_states[npc_id] = original_state
	else:
		NPCManager.npc_states.erase(npc_id)
	if FileAccess.file_exists(TEMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	bobber_manager.free()
	print("FAILED: %d" % failures if failures > 0 else "All challenge and bobber checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
