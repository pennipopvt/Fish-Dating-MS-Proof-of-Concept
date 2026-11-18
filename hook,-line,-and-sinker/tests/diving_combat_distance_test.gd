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
	_check(is_equal_approx(combat.reel_pixels_per_scroll, 2.5),
		"Each scroll now reels only 2.5 world pixels instead of seven")
	_check(is_equal_approx(combat.max_line_distance, 175.0), "Fish has authored escape slack beyond cast range")
	_check(is_equal_approx(TUNA.stagger_resistance, 150.0), "Tuna uses its revised-fishing stagger resistance")
	combat.tension = 0.6
	_perfect_parry(combat)
	_check(is_zero_approx(combat.tension),
		"Perfect parry clears built-up tension even without staggering the fish")
	_check(combat.is_active() and not combat.free_reel and combat.phase == DivingCombat.Phase.ATTACK,
		"One perfect parry does NOT stun or automatically catch distant fish")
	_check(is_equal_approx(combat.line_distance, 105.0) and combat.progress == far_progress,
		"Parry alone does not shorten the net or advance catch progress")
	_check(is_equal_approx(combat.stagger, combat.perfect_stagger_gain),
		"Perfect parry builds stagger toward a later true break")

	for i in range(5):
		combat.reel_scroll()
	_check(is_equal_approx(combat.line_distance, 92.5),
		"Five normal scrolls pull a far fish only 12.5 world pixels")
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
	_check(not combat.is_active() and pulls >= 6 and pulls <= 8,
		"Even a nearby fish now needs several slower reel scrolls")

	# Phase behavior: the fish constantly pulls away between attacks.
	_check(combat.begin(fish, TUNA, 80.0, 110.0),
		"New fight starts with a resisting prewindup")
	var warning_start: float = combat.line_distance
	var expected_passive_pull: float = TUNA.passive_escape_rate * combat.passive_pull_multiplier * (
		combat.max_line_distance - combat.catch_distance
	)
	combat.step(0.10)
	_check(combat.phase == DivingCombat.Phase.WARNING and combat.line_distance > warning_start,
		"Fish pulls away even while prewindup reeling is locked")
	_check(is_equal_approx(combat.line_distance - warning_start, expected_passive_pull * 0.10),
		"Passive pull uses this fish's authored passive escape rate")
	var prewindup_distance: float = combat.line_distance
	combat.reel_scroll()
	_check(combat.phase == DivingCombat.Phase.WARNING
		and is_equal_approx(combat.line_distance, prewindup_distance),
		"Scrolling during prewindup does not reel or parry")

	# Windup is a short pause, but scrolling too early triggers a dash.
	combat.call("_start_windup")
	var windup_distance: float = combat.line_distance
	combat.step(0.08)
	_check(combat.phase == DivingCombat.Phase.WINDUP
		and is_equal_approx(combat.line_distance, windup_distance),
		"Fish stops pulling while preparing its attack")
	combat.reel_scroll()
	_check(combat.phase == DivingCombat.Phase.DASH and not combat.reel_open,
		"Any scroll during windup fails the parry and starts the dash")
	combat.step(TUNA.miss_dash_duration)
	_check(combat.phase == DivingCombat.Phase.RECOVERY and combat.tension > 0.0,
		"After the missed dash, combat returns to a reeling recovery")
	var recovery_distance: float = combat.line_distance
	combat.step(0.10)
	_check(combat.line_distance > recovery_distance,
		"Fish keeps pulling away while player can reel during recovery")
	var after_recovery_pull: float = combat.line_distance
	combat.reel_scroll()
	_check(combat.line_distance < after_recovery_pull,
		"Recovery still allows contested reeling")

	# The actual attack is a deliberate stationary parry moment, then
	# the fish resumes resisting immediately once parried.
	combat.call("_start_warning")
	combat.call("_start_windup")
	combat.call("_start_attack")
	var attack_distance: float = combat.line_distance
	combat.step(0.03)
	_check(is_equal_approx(combat.line_distance, attack_distance),
		"Fish holds steady during unresolved attack/parry timing")
	for i in range(3):
		combat.reel_scroll()
	_check(combat.reel_open and combat.phase == DivingCombat.Phase.ATTACK,
		"Successful attack parry opens contested reeling")
	var parried_distance: float = combat.line_distance
	combat.step(0.03)
	_check(combat.line_distance > parried_distance,
		"Fish pulls again after successful parry rather than waiting motionless")
	combat.release()

	# A fish worn down by the companion battle pulls and strains less.
	_check(combat.begin(fish, TUNA, 80.0, 110.0, 0.0) and is_equal_approx(combat.strength, combat.low_health_strength),
		"A fish at 0 health fights at low_health_strength")
	var span: float = combat.max_line_distance - combat.catch_distance
	var weak_start: float = combat.line_distance
	combat.step(0.10)
	_check(is_equal_approx(combat.line_distance - weak_start,
		TUNA.passive_escape_rate * combat.passive_pull_multiplier * span * 0.10 * combat.strength),
		"Low health weakens the passive pull")
	combat.call("_start_recovery")
	var weak_tension: float = combat.tension
	combat.reel_scroll()
	_check(is_equal_approx(combat.tension - weak_tension, TUNA.reel_tension_gain * combat.strength),
		"Low health lowers reel tension")
	combat.call("_start_warning")
	combat.call("_start_windup")
	combat.reel_scroll()
	_check(combat.phase == DivingCombat.Phase.DASH and is_equal_approx(
		combat._dash_end_distance - combat._dash_start_distance,
		combat.attack.escape_rate * TUNA.miss_dash_speed_multiplier * TUNA.miss_dash_duration * span * combat.strength),
		"Low health shortens the miss dash")
	_check(is_equal_approx(combat._dash_end_tension - combat._dash_start_tension,
		TUNA.miss_tension_gain * TUNA.attack_tension_multiplier * combat.strength),
		"Low health lowers miss tension")
	combat.release()
	_check(combat.begin(fish, TUNA, 80.0, 110.0) and is_equal_approx(combat.strength, 1.0),
		"Full health (the default) keeps full strength")
	combat.release()

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
