extends SceneTree

# Regression checks for flat, additive equipment upgrades.
# From the Godot project folder:
# godot --headless --path . -s res://tests/fishing_upgrade_effects_test.gd

const COMBAT_SCENE: PackedScene = preload("res://scenes/fishing_controller.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var combat: Node2D = COMBAT_SCENE.instantiate() as Node2D
	get_root().add_child(combat)

	var attack := FishEscapeState.new()
	attack.escape_rate = 0.3
	var fish := FishData.new()
	fish.fish_id = &"upgrade_test"
	fish.reel_tension_gain = 0.015
	fish.miss_tension_gain = 0.10
	fish.attack_tension_multiplier = 1.4
	fish.miss_dash_duration = 0.25
	fish.miss_dash_speed_multiplier = 3.0
	fish.states.append(attack)

	combat.set("hooked_fish", fish)
	combat.set("current_state", 2)  # Fish_State.FISHING
	combat.get_node("FishingLine").call("send", 0.25)
	combat.call("_set_reel_open", true, false)
	combat.set("progress", 0.25)
	combat.set("tension", 0.0)
	combat.call("_reel_during_opening")
	_expect(is_equal_approx(float(combat.get("progress")), 0.26), "base reel scroll gives 1% progress")
	_expect(is_equal_approx(float(combat.get("tension")), 0.015), "base reel builds 1.5% tension")

	FishingManager.shop_reward_stronger_reel(1)
	FishingManager.shop_reward_reinforced_line(1)
	_expect(FishingManager.has_upgrade(&"stronger_reel"), "Stronger Reel becomes owned")
	_expect(FishingManager.has_upgrade(&"reinforced_line"), "Reinforced Line becomes owned")
	FishingManager.shop_reward_stronger_reel(1)
	FishingManager.shop_reward_reinforced_line(1)
	_expect(is_equal_approx(FishingManager.reel_progress_bonus, 0.01), "repeat delivery does not stack reel bonus")
	_expect(is_equal_approx(FishingManager.reel_tension_reduction, 0.005), "repeat delivery does not stack line bonus")

	combat.set("progress", 0.25)
	combat.set("tension", 0.0)
	combat.call("_reel_during_opening")
	_expect(is_equal_approx(float(combat.get("progress")), 0.27), "stronger reel gives flat 2% progress total")
	_expect(is_equal_approx(float(combat.get("tension")), 0.01), "reinforced line removes flat 0.5% reel tension")

	combat.set("fish_esc_rate", 0.3)
	combat.set("tension", 0.0)
	combat.call("_reel_during_opening")
	_expect(is_equal_approx(float(combat.get("tension")), 0.016), "line reduction is flat even for multiplied fish attack tension")

	combat.set("active_attack", attack)
	combat.set("progress", 0.60)
	combat.set("tension", 0.20)
	combat.call("_fail_parry")
	var dash: Tween = combat.get("_miss_dash_tween")
	dash.custom_step(fish.miss_dash_duration)
	_expect(is_equal_approx(float(combat.get("tension")), 0.30), "line removes flat 4% from missed dash tension")

	# A fish whose normal reel gain is below the reduction cannot restore tension.
	fish.reel_tension_gain = 0.002
	combat.set("fish_esc_rate", 0.0)
	combat.set("tension", 0.1)
	combat.call("_set_reel_open", true, false)
	combat.call("_reel_during_opening")
	_expect(is_equal_approx(float(combat.get("tension")), 0.1), "reel tension reduction is clamped at zero")

	combat.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "All additive upgrade checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
