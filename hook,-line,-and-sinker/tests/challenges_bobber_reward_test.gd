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

	# Regression for the #39 merge, which changed ChallengeData's helper
	# to ItemData and the manager's listener to a mismatched parameter.
	var catch_challenge := ChallengeData.new()
	catch_challenge.target_amount = 3
	_expect(catch_challenge.counts_fish(EASY_FISH), "challenge recognizes a caught FishData")
	_expect(catch_challenge.counts_fish(SILAS_FISH), "challenge recognizes NPC FishData too")
	var restricted_challenge := ChallengeData.new()
	var restricted: Array[FishData] = [EASY_FISH]
	restricted_challenge.counted_fish = restricted
	_expect(restricted_challenge.counts_fish(EASY_FISH), "restricted challenge accepts matching fish")
	_expect(not restricted_challenge.counts_fish(SILAS_FISH), "restricted challenge rejects other fish")
	var manager: Variant = preload("res://scripts/challenge_manager.gd").new()
	var challenges: Array[ChallengeData] = [catch_challenge]
	manager.challenges = challenges
	manager._on_fish_caught(EASY_FISH)
	_expect(catch_challenge.progress == 1, "catch listener advances challenge from FishData")
	manager._on_fish_caught(SILAS_FISH)
	_expect(catch_challenge.progress == 2, "NPC catch advances challenge without an item")
	manager.free()
	fish_manager.free()

	# Bobbers have no save file now. Every launch starts with the default,
	# and Silas's reward is earned only during his post-scene dialogue.
	var bobber_manager: Variant = BobberManagerScript.new()
	bobber_manager._ready()
	var npc_id: StringName = &"test_npc"
	var had_npc_state: bool = NPCManager.npc_states.has(npc_id)
	var original_state: Dictionary = NPCManager.get_npc_state(npc_id).duplicate(true)
	var flags: Dictionary = NPCManager.get_npc_state(npc_id)["flags"]
	flags.erase(&"silas_route_complete")
	var silas: BobberData = bobber_manager.get_bobber(&"silas")
	_expect(silas != null, "Silas's spyglass is registered but starts locked")
	_expect(bobber_manager.equipped_id == &"default", "classic bobber starts equipped")
	_expect(bobber_manager.get_unlocked_bobbers().size() == 1, "only classic bobber starts available")
	_expect(not bobber_manager.unlock_bobber(&"silas"), "Silas can't unlock before reward dialogue")
	if silas != null:
		_expect(not bobber_manager.get_unlocked_bobbers().has(silas), "Silas is hidden from the shelf before gift")
		flags[&"silas_route_complete"] = true
		_expect(bobber_manager.unlock_bobber(&"silas"), "Silas reward can unlock after dialogue")
		_expect(bobber_manager.get_unlocked_bobbers().has(silas), "earned Spyglass appears on shelf")
		_expect(bobber_manager.equip_bobber(&"silas"), "earned Spyglass can be equipped")
		# A new play session resets NPC state and builds a fresh manager.
		flags.erase(&"silas_route_complete")
		var fresh: Variant = BobberManagerScript.new()
		fresh._ready()
		_expect(not fresh.get_unlocked_bobbers().has(silas), "relaunch hides Silas again")
		_expect(fresh.equipped_id == &"default", "relaunch equips classic bobber")
		_expect(not fresh.equip_bobber(&"silas"), "relaunch cannot equip Silas")
		fresh.free()

	# Barracuda's Knife starts locked, is earned from his post-scene
	# dialogue, and has a half-length opening stun with no parry event.
	var barracuda_id: StringName = &"barracuda"
	var had_barracuda_state := NPCManager.npc_states.has(barracuda_id)
	var prior_barracuda_state: Dictionary = NPCManager.get_npc_state(barracuda_id).duplicate(true)
	var barracuda_flags: Dictionary = NPCManager.get_npc_state(barracuda_id)["flags"]
	barracuda_flags.erase(&"barracuda_route_complete")
	var knife: BobberData = bobber_manager.get_bobber(&"barracuda")
	_expect(knife != null, "Barracuda's Knife bobber is registered")
	if knife != null:
		_expect(is_equal_approx(knife.opening_stun_fraction, 0.5), "Knife stuns for half the selected fish's stun time")
		_expect(not bobber_manager.unlock_bobber(&"barracuda"), "Knife cannot unlock before Barracuda route completes")
		barracuda_flags[&"barracuda_route_complete"] = true
		_expect(bobber_manager.unlock_bobber(&"barracuda"), "Knife unlocks when Barracuda route completes")
		_expect(bobber_manager.equip_bobber(&"barracuda"), "Knife can be equipped after reward")
		_expect(bobber_manager.get_equipped_bobber() == knife, "Equipped bobber uses Knife ability")
		barracuda_flags.erase(&"barracuda_route_complete")
		_expect(bobber_manager.get_equipped_bobber() != knife, "An unearned Knife cannot remain active")
	if had_barracuda_state:
		NPCManager.npc_states[barracuda_id] = prior_barracuda_state
	else:
		NPCManager.npc_states.erase(barracuda_id)

	if had_npc_state:
		NPCManager.npc_states[npc_id] = original_state
	else:
		NPCManager.npc_states.erase(npc_id)
	bobber_manager.free()
	print("FAILED: %d" % failures if failures > 0 else "All challenge and bobber checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
