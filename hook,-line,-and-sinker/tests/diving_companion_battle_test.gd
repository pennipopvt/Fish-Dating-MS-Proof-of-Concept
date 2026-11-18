extends SceneTree

# godot --headless --path . -s res://tests/diving_companion_battle_test.gd
# Combat health prototype tests. These deliberately avoid the overworld
# save/inventory managers so defeat can never masquerade as a catch.
const MULLET: FishData = preload("res://resources/fish/mullet.tres")
const MULLET_ART: Texture2D = preload("res://sprites/fish/mullet.png")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle := DivingCompanionBattle.new()
	get_root().add_child(battle)
	var fish := DivingWildFish.new()
	get_root().add_child(fish)
	fish.setup(&"mullet", MULLET_ART, Vector2(100, 100),
		Rect2(0, 0, 320, 180), 712, MULLET)
	_check(fish.health > 0.0 and is_equal_approx(fish.health_fraction(), 1.0),
		"Wild fish starts with species-scaled health")
	_check(battle.set_target(fish) and battle.target == fish and fish.selected_for_attack,
		"Right-click command selects a fish and marks it in-world")
	_check(battle.set_target(fish) and not battle.has_target(),
		"Right-clicking the same fish cancels the command")
	_check(battle.set_target(fish), "Wild fish can be selected again")
	var original_health: float = fish.health
	battle.tick(0.8, fish.position + Vector2(-15, 0), true, false)
	_check(fish.health < original_health and not fish.defeated,
		"Silas automatically attacks without an additional player button")
	_check(fish.health_fraction() < 1.0, "Fish health drops after companion attack")

	battle._attack_time = 100.0
	battle._retaliation_time = 0.0
	battle.tick(0.1, fish.position + Vector2(-10, 0), true, false)
	_check(battle.companion_health < battle.max_companion_health,
		"Target fish can retaliate and injure Silas")
	battle.companion_health = 20.0
	battle._retaliation_time = 0.0
	battle._cover_cooldown_time = 0.0
	battle.tick(0.1, fish.position + Vector2(-10, 0), true, false)
	_check(battle.cover_time > 0.0 and is_equal_approx(battle.companion_health, 20.0),
		"Silas automatically uses defensive cover at low health")
	battle._cover_cooldown_time = 99.0
	battle.cover_time = 0.0
	battle._retaliation_time = 0.0
	battle.retaliation_damage = 25.0
	battle.tick(0.1, fish.position + Vector2(-10, 0), true, false)
	_check(not battle.is_companion_available() and not battle.has_target(),
		"An injured companion becomes temporarily unable to fight")
	battle.tick(battle.recovery_seconds + 0.1, fish.position, true, true)
	_check(battle.is_companion_available() and battle.companion_health > 0.0,
		"Silas recovers after the out-of-commission period")

	# A weakened target resists the SAME original net combat less; the
	# player still needs to throw and physically reel the net.
	var net_combat := DivingCombat.new()
	get_root().add_child(net_combat)
	_check(net_combat.begin(fish, MULLET, 78.0, 110.0), "Damaged fish can still be hooked")
	_check(net_combat.health_capture_factor < 1.0,
		"Current health reduces the fish's net-pulling resistance")
	_check(net_combat.line_distance > net_combat.catch_distance,
		"Health damage never skips the actual distance-based catch")
	net_combat.release()

	# A companion can kill its target, removing the chance to catch it.
	battle.rest_on_shore()
	battle.auto_attack_damage = fish.health + 10.0
	battle.set_target(fish)
	battle.tick(0.9, fish.position + Vector2(-15, 0), true, false)
	_check(fish.defeated and not battle.has_target(),
		"Overattacking defeats the fish instead of catching it")
	_check(not net_combat.begin(fish, MULLET, 45.0, 110.0),
		"Defeated fish cannot be hooked or captured")

	net_combat.queue_free()
	battle.queue_free()
	fish.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Companion autobattle tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, description: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + description)
	if not ok:
		failures += 1
