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

	# The Silas reward must be registered or unlock_bobber() returns false.
	# Test in isolation without writing to bobbers.cfg.
	var bobber_manager: Variant = BobberManagerScript.new()
	var silas: BobberData = bobber_manager.get_bobber(&"silas")
	_expect(silas != null, "Silas's spyglass bobber is registered")
	if silas != null:
		_expect(silas.sprite != null, "Silas's bobber has its own texture")
		bobber_manager.unlocked_ids.append(&"silas")
		_expect(bobber_manager.get_unlocked_bobbers().has(silas), "unlock appears in shelf and selection list")
	bobber_manager.free()

	print("FAILED: %d" % failures if failures > 0 else "All challenge and bobber checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
