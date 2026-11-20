extends SceneTree

# Companion auto-battle and fish health for diving.
# Uses autoloads (FishingManager, DialogueManager), so `-s` can't compile it;
# run it from a temporary scene (see AGENTS.md "Tests").
const PROTOTYPE: PackedScene = preload("res://scenes/diving_prototype.tscn")
const GOBY: FishData = preload("res://resources/fish/goby.tres")
const TUNA: FishData = preload("res://resources/fish/tuna.tres")
const SILAS_STATS: CompanionStats = preload("res://resources/companions/silas_battle.tres")
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
	_check(GOBY.min_strength * GOBY.force_range <= 1.0 and TUNA.min_strength * TUNA.force_range > 2.0,
		"Early fish fight at or below normal strength; later fish are far stronger when fresh")

	var battle := DivingCompanionBattle.new()
	battle.stats = SILAS_STATS
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
	var sea: DivingWorld = prototype.get_node("Sea") as DivingWorld
	var silas: SeaNPC = sea.get_node("NPCs/Silas") as SeaNPC
	var battle: DivingCompanionBattle = silas.get_node("CompanionBattle") as DivingCompanionBattle
	var behavior: SilasCombatBehavior = silas.get_node("CombatBehavior") as SilasCombatBehavior
	_check(battle != null and battle.stats == SILAS_STATS
		and behavior != null and battle.behavior == behavior,
		"Silas owns a configured battle instance and specialized behavior")
	var wild: Array = sea.get("_wild_fish")
	var fish: DivingWildFish
	for candidate in wild:
		if candidate is DivingWildFish and not candidate.trapped:
			fish = candidate
			break
	_check(fish != null, "Sea still spawns fish after combat composition")
	if fish != null:
		var data: FishData = (sea.get("_fish_data") as Dictionary).get(fish)
		_check(data != null and behavior.on_command(fish, data),
			"Generic command hook starts the existing companion battle")
		_check(battle.is_active() and battle.target == fish,
			"Per-NPC battle owns its own target")
		battle.stop()
		_check(not battle.is_active() and not fish.battling,
			"Stopping that NPC's battle clears its fish target")
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
