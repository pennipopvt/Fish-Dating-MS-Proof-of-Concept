extends SceneTree

# Companion auto-battle and fish health for diving.
# Uses autoloads (FishingManager, DialogueManager), so `-s` can't compile it;
# run it from a temporary scene (see AGENTS.md "Tests").
const PROTOTYPE: PackedScene = preload("res://scenes/diving_prototype.tscn")
const GOBY: FishData = preload("res://resources/fish/goby.tres")
const TUNA: FishData = preload("res://resources/fish/tuna.tres")
var failures: int = 0
var _fish_ko: DivingWildFish = null
var _companion_ko: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_unit_checks()
	await _scene_checks()
	print("FAILED: %d" % failures if failures > 0 else "Diving companion battle tests passed")
	quit(1 if failures > 0 else 0)


func _unit_checks() -> void:
	_check(is_equal_approx(DivingCompanionBattle.damage(6.0, 4.0), 4.0)
		and is_equal_approx(DivingCompanionBattle.damage(1.0, 10.0), 1.0),
		"Damage is attack - defense/2, at least 1")
	_check(GOBY.catchable_health >= 1.0 and TUNA.catchable_health < 1.0,
		"Early fish are catchable at full health; later fish need wearing down")

	var battle := DivingCompanionBattle.new()
	get_root().add_child(battle)
	battle.fish_knocked_out.connect(func(f: DivingWildFish) -> void: _fish_ko = f)
	battle.companion_knocked_out.connect(func() -> void: _companion_ko = true)
	var full: float = battle.stats.max_health
	_check(is_equal_approx(battle.health, full), "Companion starts at full health")

	var goby := _make_fish(GOBY)
	_check(battle.start(goby, GOBY) and goby.battling, "Battle starts and holds the fish")
	battle.step(0.5)
	var silas_hit: float = DivingCompanionBattle.damage(battle.stats.attack, GOBY.defense)
	_check(is_equal_approx(goby.health, GOBY.max_health - silas_hit),
		"Companion strikes first, half an interval in")
	battle.step(DivingCompanionBattle.attack_interval(GOBY.speed) - 0.5 + 0.01)
	var goby_hit: float = DivingCompanionBattle.damage(GOBY.attack, battle.stats.defense)
	_check(is_equal_approx(battle.health, full - goby_hit),
		"Fish hits back on its own speed timer")

	var fish_before: float = goby.health
	var silas_before: float = battle.health
	battle.stop()
	_check(not battle.is_active() and not goby.battling, "Recall ends the battle and frees the fish")
	battle.step(1.0)
	_check(is_equal_approx(goby.health, fish_before), "Fish keeps its damage after the battle")
	_check(is_equal_approx(battle.health, minf(full, silas_before + battle.stats.regen_per_second)),
		"Companion regenerates slowly while idle")

	battle.start(goby, GOBY)
	for i in range(200):
		if not battle.is_active():
			break
		battle.step(0.1)
	_check(_fish_ko == goby and goby.health <= 0.0 and not battle.is_active(),
		"Fighting too long knocks the fish out")

	var tuna := _make_fish(TUNA)
	battle.health = 3.0
	battle.start(tuna, TUNA)
	for i in range(200):
		if not battle.is_active():
			break
		battle.step(0.1)
	_check(_companion_ko and battle.exhausted and is_zero_approx(battle.health),
		"Companion at 0 health is exhausted")
	_check(not battle.start(tuna, TUNA), "Exhausted companion can't start a battle")
	battle.step(10.0)
	_check(is_zero_approx(battle.health), "No regen while exhausted")
	battle.rest()
	_check(battle.can_fight() and is_equal_approx(battle.health, full), "Resting restores the companion")

	battle.queue_free()
	goby.queue_free()
	tuna.queue_free()


func _scene_checks() -> void:
	var prototype := PROTOTYPE.instantiate()
	get_root().add_child(prototype)
	await process_frame
	await process_frame
	var world: Node2D = prototype.get_node("SubViewportContainer/SubViewport/Lagoon")
	var player: Sprite2D = world.get_node("Player")
	var combat: DivingCombat = world.get_node("Combat")
	var battle: DivingCompanionBattle = world.get_node("CompanionBattle")
	var wild: Array[DivingWildFish] = world.get("_wild_fish")
	var goby: DivingWildFish = null
	var tuna: DivingWildFish = null
	for fish in wild:
		if fish.fish_name == &"goby":
			goby = fish
		elif fish.fish_name == &"tuna":
			tuna = fish
	_check(goby != null and tuna != null and is_equal_approx(tuna.max_health, TUNA.max_health),
		"Spawned fish take their health from FishData")

	world.call("_on_net_fish_hit", tuna)
	_check(not combat.is_active(), "A full-health tuna is too strong for the net")

	world.set("_silas_following", true)
	player.position = goby.position + Vector2(-30.0, 0.0)
	world.call("_command_battle", goby.position)
	_check(battle.is_active() and battle.target == goby, "Right-clicking a fish sends Silas at it")
	world.call("_command_battle", goby.position)
	_check(not battle.is_active(), "Right-clicking the same fish calls Silas back")

	world.call("_command_battle", goby.position)
	world.call("_on_net_fish_hit", goby)
	_check(combat.is_active() and not battle.is_active(),
		"An early fish is catchable at full health, and netting ends the battle")
	combat.release()

	tuna.health = tuna.max_health * TUNA.catchable_health
	tuna.catch_cooldown = 0.0
	world.call("_on_net_fish_hit", tuna)
	_check(combat.is_active(), "A worn-down tuna can be netted")
	_check(is_equal_approx(combat.strength,
		lerpf(combat.low_health_strength, 1.0, TUNA.catchable_health)),
		"Reel fight strength follows the fish's remaining health")
	combat.release()
	_check(is_equal_approx(tuna.health, tuna.max_health * TUNA.catchable_health),
		"An escaped fish keeps its damage")

	prototype.queue_free()
	await process_frame


func _make_fish(data: FishData) -> DivingWildFish:
	var fish := DivingWildFish.new()
	fish.fish_name = data.fish_id
	fish.set_max_health(data.max_health)
	get_root().add_child(fish)
	return fish


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
