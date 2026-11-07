extends SceneTree

# Regression test for the FISH CO. parry combat state machine.
# Run from the Godot project folder:
# godot --headless --path . -s res://tests/fishing_combat_states_test.gd

const COMBAT_SCENE: PackedScene = preload("res://scenes/fishing_controller.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_test_combat")


func _test_combat() -> void:
	var combat: Node2D = COMBAT_SCENE.instantiate() as Node2D
	get_root().add_child(combat)
	var attack := FishEscapeState.new()
	attack.state_name = "state_machine_test"
	attack.escape_rate = 0.3
	attack.state_length = 1.0
	attack.windup_duration = 0.45
	attack.pre_windup_duration = 0.20
	attack.stun_duration = 0.60
	attack.miss_tension_gain = 0.02
	attack.counter_tension_relief = 0.25

	var test_fish := FishData.new()
	test_fish.fish_id = &"combat_test"
	test_fish.attack_tension_multiplier = 1.0
	test_fish.states.append(attack)
	combat.set("hooked_fish", test_fish)
	# Fish_State.FISHING is 2; bypass FishingManager to isolate combat.
	combat.set("current_state", 2)
	combat.set("progress", 0.60)
	combat.get_node("FishingLine").call("send", 0.60)

	# On hook, the very first phase is pre-windup, with scrolls locked.
	combat.call("start_pre_windup")
	_expect(int(combat.get("attack_phase")) == 0, "fish immediately enters PRE_WINDUP")
	combat.call("attempt_counter")
	_expect(int(combat.get("attack_phase")) == 0 and not combat.get("reel_open"), "pre-windup scroll is ignored")
	combat.call("update_attack_cycle", 0.21)
	_expect(int(combat.get("attack_phase")) == 1, "pre-windup advances into WINDUP")
	combat.call("update_attack_cycle", 0.46)
	_expect(int(combat.get("attack_phase")) == 2, "windup advances into ATTACK")

	# A miss: a single dash with distance exactly speed * duration.
	var before_dash: float = combat.get("progress")
	combat.call("_fail_parry")
	_expect(int(combat.get("attack_phase")) == 3 and not combat.get("reel_open"), "miss locks input in DASH")
	var expected_dash: float = before_dash - attack.escape_rate * combat.get("miss_dash_duration")
	var dash_tween: Tween = combat.get("_miss_dash_tween")
	dash_tween.kill()  # Advance deterministically without waiting for wall time.
	combat.call("_update_miss_dash", expected_dash)
	combat.call("_on_miss_dash_finished")
	_expect(is_equal_approx(combat.get("progress"), expected_dash), "dash distance equals move speed times dash duration")
	_expect(int(combat.get("attack_phase")) == 0 and not combat.get("reel_open"), "dash immediately returns to locked PRE_WINDUP")

	# A close parry permits contested reeling and fish movement.
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.call("_close_parry")
	_expect(combat.get("reel_open") and not combat.get("free_reel"), "close parry enables contested reeling")
	var before_fight: float = combat.get("progress")
	combat.call("_process", 0.10)
	_expect(is_equal_approx(combat.get("progress"), before_fight - 0.03), "close-parry fish pulls away at escape speed")
	combat.call("_reel_during_opening")
	_expect(combat.get("progress") > before_fight - 0.03 and combat.get("tension") > 0.0, "player can reel against fish and tension builds")
	combat.call("update_attack_cycle", 1.1)
	_expect(int(combat.get("attack_phase")) == 0 and not combat.get("reel_open"), "finished close-parry attack immediately restarts PRE_WINDUP")

	# Perfect parry freezes fish movement and makes reeling tension-free.
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.set("tension", 0.30)
	combat.call("_perfect_parry")
	_expect(int(combat.get("attack_phase")) == 4 and combat.get("free_reel"), "perfect parry enters STUN/free reeling")
	var before_stun: float = combat.get("progress")
	combat.call("_process", 0.10)
	_expect(is_equal_approx(combat.get("progress"), before_stun), "fish cannot pull during STUN")
	var before_free_reel: float = combat.get("tension")
	combat.call("_reel_during_opening")
	_expect(combat.get("progress") > before_stun and combat.get("tension") <= before_free_reel, "perfect reeling adds zero tension")
	combat.call("update_attack_cycle", 0.70)
	_expect(int(combat.get("attack_phase")) == 0 and not combat.get("reel_open"), "stun ends at next locked PRE_WINDUP")

	# An attack that expires without a parry also counts as a miss.
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.call("update_attack_cycle", 1.10)
	_expect(int(combat.get("attack_phase")) == 3 and not combat.get("reel_open"), "unparried attack expires into DASH")
	var final_dash: Tween = combat.get("_miss_dash_tween")
	final_dash.kill()

	combat.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "All fishing combat state checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
