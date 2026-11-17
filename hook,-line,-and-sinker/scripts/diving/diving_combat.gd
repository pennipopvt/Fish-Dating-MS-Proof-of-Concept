extends Node
class_name DivingCombat

# The underwater encounter uses the original FishingController's timing,
# species-authored FishEscapeState data, 3-scroll strong parry, tension and
# progress rules. It deliberately has no rod/cast/shore camera dependencies.
signal finished(won: bool, fish: DivingWildFish)
signal parried(result: StringName)

enum Phase { WARNING, WINDUP, ATTACK, DASH, STUN }

const START_PROGRESS := 0.30
const REEL_GAIN := 0.10
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
var progress: float = START_PROGRESS
var tension: float = 0.0
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
var _dash_start_progress: float = 0.0
var _dash_end_progress: float = 0.0
var _dash_start_tension: float = 0.0
var _dash_end_tension: float = 0.0

func is_active() -> bool:
	return target != null and is_instance_valid(target)


func begin(wild: DivingWildFish, data: FishData) -> bool:
	if is_active() or wild == null or not is_instance_valid(wild) or data == null or data.states.is_empty():
		return false
	target = wild
	fish_data = data
	progress = START_PROGRESS
	tension = 0.0
	recovery_timer = 0.0
	reel_open = false
	free_reel = false
	feedback = "Get ready!"
	feedback_time = 0.9
	FishingManager.hook_fish(data)
	_start_warning()
	return true


func step(delta: float) -> void:
	if not is_active():
		return
	feedback_time = maxf(0.0, feedback_time - delta)
	if reel_open and not free_reel and attack != null and (phase == Phase.ATTACK or phase == Phase.WINDUP):
		progress = maxf(0.0, progress - maxf(attack.escape_rate, 0.0) * delta)
	if reel_open:
		if recovery_timer > 0.0:
			recovery_timer = maxf(0.0, recovery_timer - delta)
		else:
			tension = maxf(0.0, tension - TENSION_RECOVERY * delta)
	if phase == Phase.DASH:
		_dash_elapsed += delta
		var t: float = clampf(_dash_elapsed / maxf(_dash_duration, 0.001), 0.0, 1.0)
		progress = lerpf(_dash_start_progress, _dash_end_progress, t)
		tension = lerpf(_dash_start_tension, _dash_end_tension, t)
		if t >= 1.0:
			if progress <= 0.0 or tension >= 1.0:
				_finish(false)
			else:
				_start_warning()
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
		Phase.ATTACK, Phase.STUN:
			_start_warning()
	if is_active() and progress <= 0.0:
		_finish(false)


func reel_scroll() -> void:
	if not is_active() or phase == Phase.WARNING or phase == Phase.DASH:
		return
	if reel_open:
		_reel()
	elif phase == Phase.WINDUP or phase == Phase.ATTACK:
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


func _start_attack() -> void:
	phase = Phase.ATTACK
	phase_time = maxf(attack.state_length, 0.05)
	attack_elapsed = 0.0


func _attempt_parry() -> void:
	if attack == null or counter_locked:
		return
	var perfect: bool = false
	var close: bool = false
	if phase == Phase.WINDUP:
		close = phase_time <= attack.close_early_window
	elif phase == Phase.ATTACK:
		perfect = attack_elapsed <= attack.counter_window
		close = not perfect and attack_elapsed <= attack.counter_window + attack.close_late_window
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
	tension = 0.0
	recovery_timer = 0.0
	phase = Phase.STUN
	phase_time = maxf(attack.stun_duration, 0.1)
	reel_open = true
	free_reel = true
	feedback = "PERFECT PARRY!"
	feedback_time = 0.9
	FishingManager.parry_resolved.emit(&"perfect")
	parried.emit(&"perfect")


func _close_parry() -> void:
	reel_open = true
	free_reel = false
	feedback = "PARRY! REEL NOW"
	feedback_time = 0.9
	FishingManager.parry_resolved.emit(&"close")
	parried.emit(&"close")


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
	_dash_start_progress = progress
	_dash_end_progress = clampf(progress - maxf(attack.escape_rate, 0.0) * fish_data.miss_dash_speed_multiplier * _dash_duration, 0.0, 1.0)
	_dash_start_tension = tension
	_dash_end_tension = clampf(tension + maxf(0.0, fish_data.miss_tension_gain * fish_data.attack_tension_multiplier - FishingManager.miss_tension_reduction), 0.0, 1.0)
	feedback = "MISSED! FISH DASHES"
	feedback_time = 0.75
	FishingManager.parry_resolved.emit(&"miss")
	parried.emit(&"miss")


func _reel() -> void:
	progress = clampf(progress + REEL_GAIN + FishingManager.reel_progress_bonus, 0.0, 1.0)
	if not free_reel:
		var multiplier: float = fish_data.attack_tension_multiplier if phase == Phase.ATTACK else 1.0
		var amount: float = maxf(0.0, fish_data.reel_tension_gain * multiplier - FishingManager.reel_tension_reduction)
		tension = clampf(tension + amount, 0.0, 1.0)
		recovery_timer = RECOVERY_DELAY
	if progress >= 1.0:
		_finish(true)
	elif tension >= 1.0:
		_finish(false)


func phase_title() -> String:
	match phase:
		Phase.WARNING:
			return "Fish preparing to attack"
		Phase.WINDUP:
			return "WINDUP  -  scroll quickly to parry"
		Phase.ATTACK:
			return "ATTACK  -  parry now!"
		Phase.DASH:
			return "FISH DASHES AWAY"
		Phase.STUN:
			return "STUNNED  -  REEL!"
	return ""


func hint() -> String:
	if reel_open:
		return "SCROLL DOWN TO PULL CLOSER" if free_reel else "SCROLL DOWN TO REEL  •  WATCH TENSION"
	if phase == Phase.WARNING or phase == Phase.DASH:
		return "Watch for the windup  •  3 fast scrolls to parry"
	return "Scroll DOWN 3 times quickly  •  Perfect timing stuns"


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
