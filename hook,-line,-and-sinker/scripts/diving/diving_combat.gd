extends Node
class_name DivingCombat

# Uses the original FishingController's species-specific attack phases,
# three-scroll parries, tension and dash rules. Like FishingLine, catch progress
# is derived from actual line distance, not a fixed bar that fills regardless
# of how far away the fish is. No bait, bobber or island camera dependencies.
signal finished(won: bool, fish: DivingWildFish)
signal parried(result: StringName)

enum Phase { WARNING, WINDUP, ATTACK, DASH, RECOVERY, STUN }

# These lengths are in the same world pixels as the diving net and fish.
# A cast reaches ~110px, but a hooked fish gets additional line slack before
# it escapes. Short-range fish require fewer pulls than distant fish.
@export_range(6.0, 40.0, 1.0) var catch_distance: float = 14.0
# Slower, deliberate line retrieval: formerly 7 pixels per scroll.
@export_range(0.5, 20.0, 0.5) var reel_pixels_per_scroll: float = 2.5
@export_range(20.0, 120.0, 1.0) var fight_slack: float = 65.0
# Use each species' passive_escape_rate for its continual tug on the net
# between attacks. Contested parried attacks use the faster authored escape_rate.
@export_range(0.0, 4.0, 0.05) var passive_pull_multiplier: float = 1.5

# Keep the stagger behavior and tuning from revised-fishing.
@export_range(1.0, 100.0, 1.0) var close_stagger_gain: float = 24.0
@export_range(1.0, 100.0, 1.0) var perfect_stagger_gain: float = 48.0
@export_range(0.0, 15.0, 0.5) var stagger_decay_per_second: float = 2.0
@export_range(1.0, 3.0, 0.05) var stun_reel_multiplier: float = 1.5

# Keep upgrade strength proportional as the base reel distance changes.
const ORIGINAL_REEL_PIXELS_PER_SCROLL: float = 7.0

const TENSION_RECOVERY := 0.20
const RECOVERY_DELAY := 0.10
const STRONG_REEL_SCROLLS := 3
const STRONG_REEL_INTERVAL_MS := 150

var target: DivingWildFish
var fish_data: FishData
var phase: Phase = Phase.WARNING
var attack: FishEscapeState
var phase_time: float = 0.0
var attack_elapsed: float = 0.0
# line_distance is authoritative. The HUD progress is derived from it, and
# DivingWorld places the hooked fish at exactly that distance each frame.
var line_distance: float = 0.0
var max_line_distance: float = 175.0
var progress: float = 0.0
var tension: float = 0.0
var stagger: float = 0.0
# Health affects resistance, not whether the projectile can latch. The player
# can still catch a healthy fish, but a weakened one pulls/dashes less.
var health_capture_factor: float = 1.0
var reel_open: bool = false
var free_reel: bool = false
var counter_locked: bool = false
var scroll_streak: int = 0
var last_scroll_ms: int = -100000
var recovery_timer: float = 0.0
var feedback: String = ""
var feedback_time: float = 0.0
var _dash_elapsed: float = 0.0
var _dash_duration: float = 0.0
var _dash_start_distance: float = 0.0
var _dash_end_distance: float = 0.0
var _dash_start_tension: float = 0.0
var _dash_end_tension: float = 0.0

func is_active() -> bool:
	return target != null and is_instance_valid(target)


func begin(wild: DivingWildFish, data: FishData, initial_distance: float, net_range: float) -> bool:
	if is_active() or wild == null or not is_instance_valid(wild) or wild.defeated or data == null or data.states.is_empty():
		return false
	target = wild
	fish_data = data
	health_capture_factor = lerpf(0.4, 1.0, wild.health_fraction())
	max_line_distance = maxf(net_range + fight_slack, catch_distance + 1.0)
	line_distance = clampf(initial_distance, catch_distance, max_line_distance)
	_update_progress_from_distance()
	tension = 0.0
	stagger = 0.0
	recovery_timer = 0.0
	reel_open = false
	free_reel = false
	feedback = "Get ready!"
	feedback_time = 0.9
	# Avoid emitting the island rod's hook signal: its FishingLine is
	# still subscribed even while the player is underwater. Combat works
	# directly from this FishData; the catch signal fires only on victory.
	_start_warning()
	return true


func step(delta: float) -> void:
	if not is_active():
		return
	feedback_time = maxf(0.0, feedback_time - delta)
	if phase != Phase.STUN:
		stagger = maxf(0.0, stagger - stagger_decay_per_second * delta)
	# The hooked fish fights the net between attacks rather than hovering
	# motionless. Its authored escape_rate determines the physical pull speed.
	# It pauses during WINDUP and during the unresolved attack itself. After
	# a parry it resumes pulling, contesting your reels; STUN stops it.
	var pull_rate: float = 0.0
	match phase:
		Phase.WARNING, Phase.RECOVERY:
			pull_rate = maxf(fish_data.passive_escape_rate, 0.0) * passive_pull_multiplier
		Phase.ATTACK:
			if reel_open and not free_reel:
				pull_rate = maxf(attack.escape_rate, 0.0)
	if pull_rate > 0.0 and attack != null:
		pull_rate *= health_capture_factor
		line_distance = minf(
			max_line_distance,
			line_distance + pull_rate * _line_span() * delta
		)
		_update_progress_from_distance()
		# Breaking the maximum length means the fish escaped, regardless
		# of which part of the attack cycle it was in.
		if line_distance >= max_line_distance:
			_finish(false)
			return
	if reel_open:
		if recovery_timer > 0.0:
			recovery_timer = maxf(0.0, recovery_timer - delta)
		else:
			tension = maxf(0.0, tension - TENSION_RECOVERY * delta)
	if phase == Phase.DASH:
		_dash_elapsed += delta
		var t: float = clampf(_dash_elapsed / maxf(_dash_duration, 0.001), 0.0, 1.0)
		line_distance = lerpf(_dash_start_distance, _dash_end_distance, t)
		_update_progress_from_distance()
		tension = lerpf(_dash_start_tension, _dash_end_tension, t)
		if t >= 1.0:
			if line_distance >= max_line_distance or tension >= 1.0:
				_finish(false)
			else:
				_start_recovery()
		return
	if phase == Phase.ATTACK:
		attack_elapsed += delta
		if not reel_open and attack_elapsed > attack.counter_window + attack.close_late_window:
			_fail_parry()
			return
	phase_time -= delta
	if phase_time > 0.0:
		return
	match phase:
		Phase.WARNING:
			_start_windup()
		Phase.WINDUP:
			_start_attack()
		Phase.ATTACK:
			if reel_open:
				_start_recovery()
			else:
				_fail_parry()
		Phase.RECOVERY:
			_start_warning()
		Phase.STUN:
			stagger = 0.0
			_start_warning()
	if is_active() and line_distance >= max_line_distance:
		_finish(false)


func reel_scroll() -> void:
	if not is_active():
		return
	# Prewindup is a locked, resisting phase: scrolling neither reels
	# nor triggers a parry. Once the windup begins, scrolling too soon
	# is a missed parry and immediately causes the fish's dash.
	if phase == Phase.WARNING or phase == Phase.DASH:
		return
	if phase == Phase.WINDUP:
		_fail_parry()
		return
	if reel_open:
		_reel()
	elif phase == Phase.ATTACK:
		_attempt_parry()


func release() -> void:
	if is_active():
		_finish(false)


func _choose_attack() -> FishEscapeState:
	if fish_data == null:
		return null
	var total: float = 0.0
	for state in fish_data.states:
		if state != null:
			total += maxf(0.0, state.state_probability)
	if total <= 0.0:
		for state in fish_data.states:
			if state != null:
				return state
		return null
	var roll: float = randf() * total
	for state in fish_data.states:
		if state == null:
			continue
		roll -= maxf(0.0, state.state_probability)
		if roll <= 0.0:
			return state
	return fish_data.states.back()


func _start_warning() -> void:
	if not is_active():
		return
	attack = _choose_attack()
	if attack == null:
		_finish(false)
		return
	phase = Phase.WARNING
	phase_time = maxf(attack.pre_windup_duration, 0.05)
	reel_open = false
	free_reel = false
	counter_locked = false
	scroll_streak = 0
	last_scroll_ms = -100000


func _start_windup() -> void:
	phase = Phase.WINDUP
	phase_time = maxf(attack.windup_duration, 0.05)
	# The fish braces for the upcoming attack and stops moving outward.
	# Reeling stays locked until the parry actually succeeds.
	reel_open = false
	free_reel = false


func _start_attack() -> void:
	phase = Phase.ATTACK
	phase_time = maxf(attack.state_length, 0.05)
	attack_elapsed = 0.0


func _attempt_parry() -> void:
	if attack == null or counter_locked:
		return
	# Only the actual attack is parryable. Even late windup input is a
	# miss, so the player must read the attack rather than pre-scroll.
	if phase != Phase.ATTACK:
		_fail_parry()
		return
	var perfect: bool = attack_elapsed <= attack.counter_window
	var close: bool = not perfect and attack_elapsed <= attack.counter_window + attack.close_late_window
	if not close and not perfect:
		_fail_parry()
		return
	var now: int = Time.get_ticks_msec()
	if scroll_streak > 0 and now - last_scroll_ms > STRONG_REEL_INTERVAL_MS:
		_fail_parry()
		return
	last_scroll_ms = now
	scroll_streak += 1
	if scroll_streak < STRONG_REEL_SCROLLS:
		feedback = "Parry %d/%d" % [scroll_streak, STRONG_REEL_SCROLLS]
		feedback_time = 0.45
		return
	scroll_streak = 0
	counter_locked = true
	if perfect:
		_perfect_parry()
	else:
		_close_parry()


func _perfect_parry() -> void:
	# Restore the original perfect-parry tension relief while keeping the
	# revised stagger system: this does not immediately stun/catch a fish.
	tension = 0.0
	recovery_timer = 0.0
	reel_open = true
	free_reel = false
	feedback = "PERFECT PARRY  +STAGGER"
	feedback_time = 0.9
	FishingManager.parry_resolved.emit(&"perfect")
	parried.emit(&"perfect")
	_add_stagger(perfect_stagger_gain)


func _close_parry() -> void:
	reel_open = true
	free_reel = false
	feedback = "PARRY  +STAGGER"
	feedback_time = 0.9
	FishingManager.parry_resolved.emit(&"close")
	parried.emit(&"close")
	_add_stagger(close_stagger_gain)


func _add_stagger(amount: float) -> void:
	if not is_active() or phase == Phase.STUN:
		return
	stagger = clampf(stagger + amount / maxf(health_capture_factor, 0.1), 0.0, maxf(fish_data.stagger_resistance, 1.0))
	if stagger >= maxf(fish_data.stagger_resistance, 1.0):
		_start_stagger_break()


func _start_stagger_break() -> void:
	# Only a full meter earns the true stun: clear tension and reel freely.
	phase = Phase.STUN
	phase_time = maxf(attack.stun_duration, 0.2)
	counter_locked = true
	tension = 0.0
	recovery_timer = 0.0
	reel_open = true
	free_reel = true
	feedback = "STAGGER BREAK!  REEL!"
	feedback_time = 1.0


func _start_recovery() -> void:
	# As in revised-fishing, fish briefly rests after an attack or dash.
	# Reeling is allowed, but adds normal tension.
	phase = Phase.RECOVERY
	phase_time = maxf(attack.recovery_duration, 1.0)
	counter_locked = true
	reel_open = true
	free_reel = false


func _fail_parry() -> void:
	if not is_active():
		return
	counter_locked = true
	scroll_streak = 0
	reel_open = false
	free_reel = false
	phase = Phase.DASH
	_dash_elapsed = 0.0
	_dash_duration = maxf(fish_data.miss_dash_duration, 0.05)
	_dash_start_distance = line_distance
	_dash_end_distance = minf(
		max_line_distance,
		line_distance + maxf(attack.escape_rate, 0.0) * fish_data.miss_dash_speed_multiplier * _dash_duration * _line_span() * health_capture_factor
	)
	_dash_start_tension = tension
	_dash_end_tension = clampf(tension + maxf(0.0, fish_data.miss_tension_gain * fish_data.attack_tension_multiplier * health_capture_factor - FishingManager.miss_tension_reduction), 0.0, 1.0)
	feedback = "MISSED! FISH DASHES"
	feedback_time = 0.75
	FishingManager.parry_resolved.emit(&"miss")
	parried.emit(&"miss")


func _line_span() -> float:
	return maxf(max_line_distance - catch_distance, 1.0)


func _update_progress_from_distance() -> void:
	progress = clampf((max_line_distance - line_distance) / _line_span(), 0.0, 1.0)


func _reel() -> void:
	# Each scroll reels a small physical distance. Scale the upgrade bonus
	# with the base pull so an upgrade doesn't undo the slower combat pacing.
	var stun_multiplier: float = stun_reel_multiplier if phase == Phase.STUN else 1.0
	var upgrade_multiplier: float = 1.0 + FishingManager.reel_progress_bonus * _line_span() / ORIGINAL_REEL_PIXELS_PER_SCROLL
	var gain: float = reel_pixels_per_scroll * upgrade_multiplier * stun_multiplier
	line_distance = maxf(catch_distance, line_distance - gain)
	_update_progress_from_distance()
	if not free_reel:
		var tension_multiplier: float = fish_data.attack_tension_multiplier if phase == Phase.ATTACK else 1.0
		var amount: float = maxf(0.0, fish_data.reel_tension_gain * tension_multiplier * health_capture_factor - FishingManager.reel_tension_reduction)
		tension = clampf(tension + amount, 0.0, 1.0)
		recovery_timer = RECOVERY_DELAY
	# The fish must actually reach Penni. A perfect parry opens free
	# reeling but never grants capture on its own, however far away it is.
	if line_distance <= catch_distance:
		_finish(true)
	elif tension >= 1.0:
		_finish(false)

func phase_title() -> String:
	match phase:
		Phase.WARNING:
			return "FISH PULLING AWAY  -  WAIT"
		Phase.WINDUP:
			return "WINDUP  -  DON'T SCROLL"
		Phase.ATTACK:
			return "ATTACK  -  parry now!"
		Phase.DASH:
			return "FISH DASHES AWAY"
		Phase.STUN:
			return "STAGGERED  -  FREE REEL!"
		Phase.RECOVERY:
			return "FISH PULLING  -  REEL!"
	return ""


func hint() -> String:
	if phase == Phase.WARNING:
		return "FISH IS PULLING  •  WAIT FOR THE ATTACK"
	if phase == Phase.WINDUP:
		return "DON'T SCROLL YET  •  EARLY INPUT CAUSES DASH"
	if phase == Phase.DASH:
		return "FISH DASHING  •  WAIT FOR RECOVERY"
	if reel_open:
		return "SCROLL TO REEL FREELY" if free_reel else "SCROLL TO REEL  •  FISH PULLS BACK"
	return "SCROLL DOWN 3x NOW  •  PARRY THE ATTACK"


func telegraph_fraction() -> float:
	if attack == null:
		return 0.0
	if phase == Phase.WINDUP:
		return clampf(1.0 - phase_time / maxf(attack.windup_duration, 0.01), 0.0, 1.0)
	if phase == Phase.ATTACK:
		return clampf(attack_elapsed / maxf(attack.counter_window + attack.close_late_window, 0.01), 0.0, 1.0)
	return 0.0


func _finish(won: bool) -> void:
	var previous: DivingWildFish = target
	var previous_data: FishData = fish_data
	target = null
	fish_data = null
	reel_open = false
	free_reel = false
	if previous_data != null and not won:
		FishingManager.lose_fish(previous_data)
	finished.emit(won, previous)
