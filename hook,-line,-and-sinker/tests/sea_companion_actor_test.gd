extends SceneTree

# Regressions for the physical Silas actor, while keeping the same
# CompanionBattle health/attack state machine as on main.
# Run via the Godot project test runner with autoloads available.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = MAIN.instantiate()
	get_root().add_child(main)
	await process_frame
	var sea: DivingWorld = main.get_node(
		"SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var player: Player = main.get_node(
		"SubViewportContainer/SubViewport/World/Player") as Player
	var silas: SeaNPC = sea.get_node("NPCs/Silas") as SeaNPC
	var battle: DivingCompanionBattle = sea.get_node("CompanionBattle") as DivingCompanionBattle
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var fish: DivingWildFish
	var data: FishData
	for candidate in sea.get("_wild_fish"):
		var wild: DivingWildFish = candidate as DivingWildFish
		if wild != null and not wild.trapped:
			fish = wild
			break
	if fish != null:
		var lookup: Dictionary = sea.get("_fish_data")
		data = lookup.get(fish) as FishData
	_check(fish != null and data != null, "A free wild fish is available to fight")
	_check(silas.get("_player") == player and silas.get("_battle") == battle,
		"Reusable SeaNPC resolves the one Player and CompanionBattle")
	if fish == null or data == null:
		main.queue_free()
		quit(1)
		return

	# Set up combat only; don't complete dialogue or alter progression in
	# these focused movement/health assertions.
	player.set_swimming(true, sea.call("_sea_bounds"))
	player.position = fish.position + Vector2(45.0, 0.0)
	silas.following = true
	silas.position = fish.position + Vector2(82.0, 0.0)
	var state: Dictionary = NPCManager.get_npc_state(story.silas_data.npc_id)
	var flags: Dictionary = state["flags"]
	flags[&"silas_following"] = true
	_check(sea.call("_try_companion_target", fish.position),
		"Right-clicking a nearby species target starts the shared battle")
	_check(battle.is_active() and battle.target == fish and fish.battling,
		"Target enters normal main-branch CompanionBattle state")
	_check(not silas.can_strike_target(), "Silas cannot damage a distant fish")
	var health_before: float = fish.health
	battle.step(2.0, silas.can_strike_target())
	_check(is_equal_approx(fish.health, health_before),
		"No invisible damage while Silas is still swimming toward the fish")
	var old_distance: float = silas.position.distance_to(fish.position)
	for i in range(30):
		silas._process(0.1)
		if silas.can_strike_target():
			break
	_check(silas.position.distance_to(fish.position) < old_distance,
		"Silas visibly approaches the fish instead of following the player")
	_check(silas.can_strike_target(),
		"Silas eventually reaches the attack range and can strike")
	battle.step(0.55, silas.can_strike_target())
	_check(fish.health < health_before,
		"The unchanged species damage calculation strikes after arrival")
	_check(float(silas.get("_lunge_time")) > 0.0,
		"Hit signal produces a short physical lunge")
	_check(sea.call("_try_companion_target", fish.position),
		"Right-clicking the same target recalls Silas")
	_check(not battle.is_active() and not fish.battling,
		"Recall ends battle and frees the target as on main")

	# Following returns to Penni after the fight, rather than staying
	# glued to the prior target.
	var before_return: float = silas.position.distance_to(
		player.position + Vector2(-24.0, 6.0))
	silas._process(0.1)
	var after_return: float = silas.position.distance_to(
		player.position + Vector2(-24.0, 6.0))
	_check(after_return < before_return, "Silas returns toward Penni on recall")

	main.queue_free()
	await process_frame
	print("FAILED: %d" % failures if failures > 0 else "Sea companion actor tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
