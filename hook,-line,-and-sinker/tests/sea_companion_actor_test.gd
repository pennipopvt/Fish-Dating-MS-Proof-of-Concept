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
	var battle: DivingCompanionBattle = silas.get_node("CompanionBattle") as DivingCompanionBattle
	var behavior: SilasCombatBehavior = silas.get_node("CombatBehavior") as SilasCombatBehavior
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	_check(behavior != null and behavior.battle == battle and battle.behavior == behavior
		and is_equal_approx(behavior.safety_health_ratio, 0.5),
		"Silas has his own battle, behavior subclass and editable 50% limit")
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
	var fish_sprite: Sprite2D = silas.get_node("Sprite") as Sprite2D
	_check(is_equal_approx(silas.fish_sprite_width, 30.0)
		and is_equal_approx(fish_sprite.scale.x
			* float(fish_sprite.texture.get_width() / fish_sprite.hframes), 30.0)
		and silas.scale == Vector2.ONE,
		"Silas renders larger using Sprite2D only, not the encounter node")
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
	_check(is_equal_approx(fish.health, health_before) and not fish.companion_weakened,
		"Just commanding Silas does not mark a fish as assisted")

	# Regression: the previous 22px chase destination matched the inclusive
	# strike boundary, but movement stops within 1px of its destination.
	# Silas could settle at 22.5px and never enable either attack timer.
	silas.position = fish.position + Vector2(silas.combat_attack_range + 4.5, 0.0)
	_check(not silas.can_strike_target(),
		"At 0.5px outside strike range, a fight has not started landing hits")
	silas._process(0.1)
	_check(silas.can_strike_target(),
		"Companion advances inside the strike range instead of stalling at its edge")

	# Keep the separate long-distance chase test independent of the boundary case.
	silas.position = fish.position + Vector2(82.0, 0.0)
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
	_check(fish.health < health_before and fish.companion_weakened,
		"A real companion hit flags the fish as assisted without changing damage")
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

	# Silas's attacks stop exactly at half health, even if the final hit
	# would otherwise overshoot or kill. The shared battle never KOs the fish.
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	fish.health = fish.max_health * 0.5 + 0.5
	var spared_events: Array[DivingWildFish] = []
	var refused_events: Array[DivingWildFish] = []
	behavior.fish_spared.connect(func(f: DivingWildFish) -> void: spared_events.append(f))
	behavior.attack_refused.connect(func(f: DivingWildFish) -> void: refused_events.append(f))
	_check(sea.call("_try_companion_target", fish.position),
		"Penni can ask Silas to weaken a healthy fish")
	battle.step(DivingCompanionBattle.attack_interval(battle.stats.speed), true)
	_check(is_equal_approx(fish.health, fish.max_health * 0.5)
		and fish.health > 0.0,
		"Silas's hit cannot take a fish below his 50% safety threshold")
	_check(not battle.is_active() and not fish.battling and spared_events.size() == 1,
		"Silas automatically disengages after reaching the threshold")
	_check((sea.get("_wild_fish") as Array).has(fish),
		"Spared fish stays in the sea instead of being knocked out")

	# Reordering Silas to attack a weak fish uses the established dialogue UI.
	_check(sea.call("_try_companion_target", fish.position),
		"Repeated orders against a hurt fish are consumed by the behavior")
	var opening_line: DialogueLineData = DialogueManager.get_current_line()
	_check(refused_events.size() == 1 and not battle.is_active()
		and DialogueManager.is_active and DialogueManager.current_npc == story.silas_data
		and opening_line != null and opening_line.text == "Penni? N-no, not that one...",
		"Silas refuses and starts a conversation rather than attacking")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	fish.health = 1.0
	_check(sea.call("_try_companion_target", fish.position)
		and refused_events.size() == 2 and is_equal_approx(fish.health, 1.0)
		and DialogueManager.is_active and DialogueManager.current_npc == story.silas_data,
		"Repeated deliberate orders still start Silas dialogue and never injure fish")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()

	main.queue_free()
	await process_frame
	print("FAILED: %d" % failures if failures > 0 else "Sea companion actor tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
