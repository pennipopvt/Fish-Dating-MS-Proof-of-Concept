extends SceneTree

# Revised fishing smoke/regression tests:
# godot --headless --path . -s res://tests/fishing_combat_states_test.gd

const COMBAT_SCENE: PackedScene = preload("res://scenes/fishing_controller.tscn")
const SILAS: FishData = preload("res://resources/fish/silas.tres")
const KUDA: FishData = preload("res://resources/fish/kuda.tres")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Back up autoload state; all fish-party state is session-only.
	var original_pool: Array[FishData] = FishingManager.possible_catches.duplicate()
	var original_dex: Array[FishData] = FishingManager.catch_dex.duplicate()
	var original_party: Array[FishData] = FishingManager.party.duplicate()
	var original_lure: StringName = FishingManager.lure_fish_id
	var original_casts: int = FishingManager.total_casts
	FishingManager.party.clear()
	FishingManager.lure_fish_id = &""
	FishingManager.catch_dex.clear()
	FishingManager.total_casts = 1
	_expect(FishingManager.get_random_catch() != SILAS, "Silas cannot appear before introductory cast")
	FishingManager.total_casts = 6
	_expect(FishingManager.get_random_catch() == SILAS, "Sixth cast guarantees Silas")
	FishingManager.register_recruited_companion(SILAS)
	_expect(FishingManager.has_spyglass(), "Recruited Silas grants passive spyglass")
	_expect(FishingManager.get_lure_companion() == SILAS, "First recruited fish is active lure")
	FishingManager.register_recruited_companion(KUDA)
	FishingManager.set_lure_companion(KUDA.fish_id)
	_expect(FishingManager.get_lure_companion() == KUDA and FishingManager.has_spyglass(),
		"Spyglass persists with Silas in reserve")
	FishingManager.set_lure_companion(SILAS.fish_id)

	var combat := COMBAT_SCENE.instantiate()
	get_root().add_child(combat)
	var line := combat.get_node("FishingLine")
	_expect(line.has_node("LureFish") and line.has_node("StaggerBar"), "Line shows active lure and stagger meter")
	line.call("send", 0.70)
	_expect((line.get_node("LureFish") as Sprite2D).texture == SILAS.item_data.sprite,
		"Silas's fish sprite replaces the bobber on the line")

	var attack := FishEscapeState.new()
	attack.state_name = "test"
	attack.escape_rate = 0.12
	attack.pre_windup_duration = 0.20
	attack.windup_duration = 0.45
	attack.counter_window = 0.16
	attack.close_late_window = 0.18
	attack.recovery_duration = 0.40
	attack.stun_duration = 0.60
	var fish := FishData.new()
	fish.fish_id = &"combat_test"
	fish.stagger_resistance = 100.0
	fish.miss_tension_gain = 0.12
	fish.states.append(attack)
	combat.set("hooked_fish", fish)
	combat.set("current_state", 2) # Fish_State.FISHING
	combat.set("progress", 0.80)
	combat.call("start_pre_windup")
	_expect(int(combat.get("attack_phase")) == 0, "Starts in PRE_WINDUP")
	combat.call("update_attack_cycle", 0.21)
	_expect(int(combat.get("attack_phase")) == 1, "Transitions to WINDUP")
	combat.call("begin_attack")
	combat.set("tension", 0.45)
	combat.call("_perfect_parry")
	_expect(int(combat.get("attack_phase")) == 2 and not combat.get("free_reel"),
		"One perfect parry no longer automatically stuns")
	_expect(is_equal_approx(combat.get("stagger"), 48.0),
		"Perfect parry builds substantial stagger")
	_expect(is_equal_approx(combat.get("tension"), 0.45),
		"Perfect parry does not instantly erase line tension")
	combat.call("update_attack_cycle", 0.40)
	_expect(int(combat.get("attack_phase")) == 4 and combat.get("reel_open"),
		"Successful parry leads to standard reeling during RECOVERY")

	combat.call("start_pre_windup")
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.call("_close_parry")
	_expect(combat.get("stagger") > 70.0 and int(combat.get("attack_phase")) == 2,
		"Normal parry adds smaller stagger, without stunning")
	combat.call("start_pre_windup")
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.call("_perfect_parry")
	_expect(int(combat.get("attack_phase")) == 5 and combat.get("free_reel"),
		"Full stagger meter triggers a stun and free reeling")
	_expect(is_zero_approx(combat.get("tension")), "Stagger break clears tension")
	var progress_before: float = combat.get("progress")
	combat.call("_reel_during_opening")
	_expect(combat.get("progress") > progress_before + float(combat.get("reel_gain")),
		"Stunned reeling gains more distance per scroll")
	combat.call("update_attack_cycle", 0.61)
	_expect(int(combat.get("attack_phase")) == 0 and is_zero_approx(combat.get("stagger")),
		"Stun ends by resetting stagger and restarting windup")

	# Failed attacks still dash, but lead to a brief reeling opportunity.
	combat.set("progress", 0.80)
	combat.set("tension", 0.10)
	combat.call("start_pre_windup")
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.call("_fail_parry")
	_expect(int(combat.get("attack_phase")) == 3 and not combat.get("reel_open"),
		"Miss starts the short locked dash")
	(combat.get("_miss_dash_tween") as Tween).kill()
	combat.call("_on_miss_dash_finished")
	_expect(int(combat.get("attack_phase")) == 4 and combat.get("reel_open"),
		"Dash returns to normal reeling instead of immediately relocking")

	# Silas's command replaces a parry and relieves tension without stagger.
	combat.call("start_pre_windup")
	combat.call("start_windup")
	combat.set("tension", 0.60)
	combat.set("stagger", 0.0)
	combat.call("_command_lure")
	_expect(is_equal_approx(combat.get("tension"), 0.30),
		"Silas's Hide reduces tension")
	_expect(is_zero_approx(combat.get("stagger")) and combat.get("reel_open"),
		"Command resolves the attack but earns no parry stagger")
	_expect(combat.get("counter_locked"), "Command and parry are mutually exclusive")

	combat.queue_free()
	FishingManager.possible_catches = original_pool
	FishingManager.catch_dex = original_dex
	FishingManager.party = original_party
	FishingManager.lure_fish_id = original_lure
	FishingManager.total_casts = original_casts
	FishingManager.team_changed.emit()
	print("FAILED: %d" % failures if failures > 0 else "Revised fishing combat checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
