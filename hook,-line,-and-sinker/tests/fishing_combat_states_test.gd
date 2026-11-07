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
	# Legacy attack tension settings intentionally differ from FishData.
	attack.miss_tension_gain = 0.02
	attack.counter_tension_relief = 0.25

	var test_fish := FishData.new()
	test_fish.fish_id = &"combat_test"
	test_fish.attack_tension_multiplier = 1.0
	test_fish.reel_tension_gain = 0.03
	test_fish.miss_tension_gain = 0.18
	# Deliberately use non-default values to prove combat reads FishData,
	# not old FishingController properties.
	test_fish.miss_dash_duration = 0.25
	test_fish.miss_dash_speed_multiplier = 4.0
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
	combat.set("tension", 0.45)
	combat.call("recover_tension", 0.50)
	_expect(is_equal_approx(combat.get("tension"), 0.45), "tension persists with scrolling locked during pre-windup")
	combat.call("update_attack_cycle", 0.21)
	_expect(int(combat.get("attack_phase")) == 1, "pre-windup advances into WINDUP")
	combat.call("recover_tension", 0.50)
	_expect(is_equal_approx(combat.get("tension"), 0.45), "tension persists while scrolling is locked in windup")
	combat.call("update_attack_cycle", 0.46)
	_expect(int(combat.get("attack_phase")) == 2, "windup advances into ATTACK")

	# A miss: one dash with distance speed * dash boost * duration.
	var before_dash: float = combat.get("progress")
	var before_dash_tension: float = combat.get("tension")
	combat.call("_fail_parry")
	_expect(int(combat.get("attack_phase")) == 3 and not combat.get("reel_open"), "miss locks input in DASH")
	_expect(is_equal_approx(combat.get("phase_time"), test_fish.miss_dash_duration), "dash duration comes from hooked FishData")
	_expect(is_equal_approx(combat.get("tension"), before_dash_tension), "miss does not add all tension instantly")
	var expected_dash: float = before_dash - attack.escape_rate * test_fish.miss_dash_speed_multiplier * test_fish.miss_dash_duration
	var dash_tween: Tween = combat.get("_miss_dash_tween")
	dash_tween.kill()  # Advance deterministically without waiting for wall time.
	var final_dash_tension: float = minf(1.0, before_dash_tension + test_fish.miss_tension_gain * test_fish.attack_tension_multiplier)
	combat.call("_update_miss_dash", (before_dash + expected_dash) * 0.5)
	combat.call("_update_miss_dash_tension", (before_dash_tension + final_dash_tension) * 0.5)
	_expect(combat.get("tension") > before_dash_tension, "tension visibly rises during the dash")
	var halfway_tension: float = combat.get("tension")
	combat.call("recover_tension", 0.50)
	_expect(is_equal_approx(combat.get("tension"), halfway_tension), "tension cannot recover during dash")
	combat.call("_update_miss_dash", expected_dash)
	combat.call("_update_miss_dash_tension", final_dash_tension)
	_expect(is_equal_approx(combat.get("tension"), final_dash_tension), "dash ends with exactly one miss tension penalty")
	combat.call("_on_miss_dash_finished")
	_expect(is_equal_approx(combat.get("progress"), expected_dash), "dash distance equals boosted move speed times dash duration")
	_expect(int(combat.get("attack_phase")) == 0 and not combat.get("reel_open"), "dash immediately returns to locked PRE_WINDUP")
	combat.call("recover_tension", 0.50)
	_expect(is_equal_approx(combat.get("tension"), final_dash_tension), "dash tension carries into next pre-windup")

	# A close parry permits contested reeling and fish movement.
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.call("_close_parry")
	_expect(combat.get("reel_open") and not combat.get("free_reel"), "close parry enables contested reeling")
	var before_fight: float = combat.get("progress")
	combat.call("_process", 0.10)
	_expect(is_equal_approx(combat.get("progress"), before_fight - 0.03), "close-parry fish pulls away at escape speed")
	var before_reeling_tension: float = combat.get("tension")
	combat.call("_reel_during_opening")
	_expect(combat.get("progress") > before_fight - 0.03 and combat.get("tension") > before_reeling_tension, "player can reel against fish and tension builds")
	# In ATTACK the fish's attack multiplier applies to its own reel tension.
	var expected_reel_tension: float = before_reeling_tension + test_fish.reel_tension_gain * test_fish.attack_tension_multiplier
	_expect(is_equal_approx(combat.get("tension"), expected_reel_tension), "reeling uses this fish's own tension gain")
	combat.set("recovery_timer", 0.0)
	combat.call("recover_tension", 0.02)
	_expect(combat.get("tension") < expected_reel_tension, "tension recovers once the player has a reel opening")
	combat.call("update_attack_cycle", 1.1)
	_expect(int(combat.get("attack_phase")) == 0 and not combat.get("reel_open"), "finished close-parry attack immediately restarts PRE_WINDUP")

	# Perfect parry freezes fish movement and makes reeling tension-free.
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.set("tension", 0.30)
	combat.call("_perfect_parry")
	_expect(int(combat.get("attack_phase")) == 4 and combat.get("free_reel"), "perfect parry enters STUN/free reeling")
	_expect(is_zero_approx(combat.get("tension")), "perfect stun immediately clears all tension")
	_expect(is_zero_approx((combat.get_node("TensionBar") as Range).value), "perfect stun clears the displayed tension bar")
	var before_stun: float = combat.get("progress")
	combat.call("_process", 0.10)
	_expect(is_equal_approx(combat.get("progress"), before_stun), "fish cannot pull during STUN")
	var before_free_reel: float = combat.get("tension")
	combat.call("_reel_during_opening")
	_expect(combat.get("progress") > before_stun and is_zero_approx(combat.get("tension")), "perfect reeling adds zero tension")
	combat.call("update_attack_cycle", 0.70)
	_expect(int(combat.get("attack_phase")) == 0 and not combat.get("reel_open"), "stun ends at next locked PRE_WINDUP")

	# The attack MUST dash immediately when its parry grace expires, not
	# several seconds later at the end of its state_length animation.
	combat.call("start_windup")
	combat.call("begin_attack")
	combat.call("update_attack_cycle", 0.15)
	_expect(int(combat.get("attack_phase")) == 2, "still in attack while perfect window is open")
	combat.call("update_attack_cycle", 0.20)
	_expect(int(combat.get("attack_phase")) == 3 and not combat.get("reel_open"), "unparried fish immediately dashes at grace-window expiry")
	var final_dash: Tween = combat.get("_miss_dash_tween")
	final_dash.kill()

	combat.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "All fishing combat state checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
