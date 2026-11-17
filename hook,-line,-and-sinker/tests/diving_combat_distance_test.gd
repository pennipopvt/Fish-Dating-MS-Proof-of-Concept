extends SceneTree

# Regression for the old diving bug: an arbitrary progress bar made fish
# disappear after one parry even when they were still far from Penni.
# godot --headless --path . -s res://tests/diving_combat_distance_test.gd
const TUNA: FishData = preload("res://resources/fish/tuna.tres")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var combat := DivingCombat.new()
	get_root().add_child(combat)
	var fish := DivingWildFish.new()
	get_root().add_child(fish)

	# Hooked at 105 world pixels: a perfect parry builds stagger, but must
	# never skip the actual work of moving the fish physically closer.
	_check(combat.begin(fish, TUNA, 105.0, 110.0), "Tuna engages at a distant net impact")
	var far_progress: float = combat.progress
	_check(is_equal_approx(combat.line_distance, 105.0), "Real distance comes from net impact")
	_check(is_equal_approx(combat.max_line_distance, 175.0), "Fish has authored escape slack beyond cast range")
	_check(is_equal_approx(TUNA.stagger_resistance, 150.0), "Tuna uses its revised-fishing stagger resistance")
	_perfect_parry(combat)
	_check(combat.is_active() and not combat.free_reel and combat.phase == DivingCombat.Phase.ATTACK,
		"One perfect parry does NOT stun or automatically catch distant fish")
	_check(is_equal_approx(combat.line_distance, 105.0) and combat.progress == far_progress,
		"Parry alone does not shorten the net or advance catch progress")
	_check(is_equal_approx(combat.stagger, combat.perfect_stagger_gain),
		"Perfect parry builds stagger toward a later true break")

	for i in range(5):
		combat.reel_scroll()
	_check(combat.is_active() and combat.line_distance > combat.catch_distance,
		"Five actual reel pulls still cannot catch a far-away tuna")
	_check(combat.progress > far_progress and combat.progress < 1.0,
		"Progress bar advances only as physical line distance shrinks")
	combat.release()

	# The same fish hooked at 30 pixels starts substantially nearer;
	# distance-based progression requires fewer reels to bring it in.
	_check(combat.begin(fish, TUNA, 30.0, 110.0), "Tuna can be hooked nearby")
	_check(combat.progress > far_progress, "A nearby fish starts closer to the capture threshold")
	_check(combat.stagger == 0.0, "Starting another fight resets stagger")
	_perfect_parry(combat)
	_check(combat.is_active(), "Even a close fish is not caught by parrying alone")
	var pulls: int = 0
	while combat.is_active() and pulls < 12:
		combat.reel_scroll()
		pulls += 1
	_check(not combat.is_active() and pulls >= 2 and pulls <= 4,
		"Close fish requires physically reeling the remaining distance")

	combat.queue_free()
	fish.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Diving physical catch progression tests passed")
	quit(1 if failures > 0 else 0)


func _perfect_parry(combat: DivingCombat) -> void:
	combat.call("_start_windup")
	combat.call("_start_attack")
	for i in range(3):
		combat.reel_scroll()


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
