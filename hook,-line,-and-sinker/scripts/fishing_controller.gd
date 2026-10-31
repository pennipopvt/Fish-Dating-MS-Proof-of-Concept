extends Node

enum Fish_State
{
	NOT,
	WAITING,
	FISHING
}

var current_state: Fish_State = Fish_State.NOT
var hooked_fish: FishData = null

var casts: int = 0
var progress: float = 0
var bite_time: float = 0

var tension: float = 0
var state_timer: float = 0
var fish_esc_rate: float = 0
var recovery_timer: float = 0

# The chosen FishEscapeState owns the attack properties.
enum AttackPhase { RECOVERY, WINDUP, ATTACK, STUN }
var attack_phase: AttackPhase = AttackPhase.RECOVERY
var active_attack: FishEscapeState = null
var phase_time: float = 0.0
var attack_elapsed: float = 0.0
var counter_locked: bool = false
var scroll_streak: int = 0
var last_scroll_ms: int = -100000
@export_range(0.02, 0.3, 0.01) var scrolling_threshold: float = 0.12
@export_range(2, 6, 1) var strong_reel_scrolls: int = 3
@export_range(0.05, 0.3, 0.01) var strong_reel_interval: float = 0.15

#band-aid fix to avoid accidentally requeueing interact when exiting since exit and interact are the same input
var press_delay: float = 0.10
var delay_time = 0

@export var reel_gain: float = 0.1
@export var starting_progress: float = 0.2
## Constant gentle resistance outside stun, measured as progress lost per second.
@export_range(0.0, 0.2, 0.001) var passive_escape_rate: float = 0.015
@export var bite_time_min: float = 1
@export var bite_time_max: float = 20

#maybe later these variables can be moved to the manager for shop items to influence dem
@export var tension_gain: float = 0.7
@export var tension_recovery: float = 0.2
##tension multiplier while reeling a fish thats in desperation
@export var tens_bonus_mult: float = 1.2
##delay before recovery starts after reeling ends
@export var recovery_delay: float = 0.1

@onready var fishing_progress: TextureProgressBar = $FishingProgress
@onready var tension_bar: TextureProgressBar = $TensionBar
@onready var fishing_line: Line2D = $FishingLine

func begin_fishing() -> void:
	if(current_state == Fish_State.NOT && delay_time == 0):
		casts = 0
		#set busy first so exit_fishing can clear it if the cast fails right away
		get_parent().busy = true
		cast_rod()
	
func cast_rod() -> void:
	if(casts >= FishingManager.max_casts_per_session):
		exit_fishing()
		return
	casts += 1
	current_state = Fish_State.WAITING
	
	progress = starting_progress
	tension = 0
	fishing_line.set_tension(tension)
	#once a line is cast, set the time itll take for a fish to present itself!!
	bite_time = randf_range(bite_time_min,bite_time_max)
	#fish is decided on rod cast
	hooked_fish = FishingManager.get_random_catch()
	if(hooked_fish == null):
		#empty or malformed catch pool, nothing to hook
		push_warning("No catchable fish in FishingManager.possible_catches")
		exit_fishing()
		return
	fishing_line.send()
	print("Cast #", casts, " will be a ", hooked_fish.fish_id)

func _process(delta: float) -> void:
	if(current_state == Fish_State.WAITING):
		#tick down timer if we still awaiting a glorious fish
		bite_time -= delta
		#if we reach 0 then find a fish and start reelin for it
		if (bite_time <= 0):
			begin_reeling()
	
	elif(current_state == Fish_State.FISHING):
		#we are fishing now
		if(hooked_fish == null):
			#failsafe
			return
		#fish escape rate fights da player
		progress -= (0.0 if attack_phase == AttackPhase.STUN else passive_escape_rate + fish_esc_rate) * delta
		progress = clamp(progress,0,1)
		
		recover_tension(delta)
		update_attack_cycle(delta)
		
		tension = clamp(tension,0,1)
		fishing_line.set_tension(tension)
		fishing_progress.value = progress
		tension_bar.value = tension
		fishing_line.update_line_dist(progress)
		if fishing_line.fish_midpoint_above_water():
			catch_fish()
			return
		if(progress <= 0):
			lose_fish()
	elif(current_state == Fish_State.NOT && delay_time != 0):
		delay_time -= delta
		delay_time = clamp(delay_time,0,1)

func begin_reeling() -> void:
	current_state = Fish_State.FISHING
	#reset progress when finding a fish
	progress = starting_progress
	fishing_progress.value = progress
	tension_bar.value = tension
	
	active_attack = null
	start_recovery(0.3)
	
	#once we actually get it, we will let the fishing manager know what fish we have
	FishingManager.hook_fish(hooked_fish)
	print("Found ", hooked_fish.fish_id)
	print("Fish behavior available: ", hooked_fish.states.size(), " states.")

func lose_fish() -> void:
	if(hooked_fish == null):
		return
	#inform the fishing manager
	print("Lost ", hooked_fish.fish_id)
	FishingManager.lose_fish(hooked_fish)
	finish_cast()
	
func catch_fish() -> void:
	if(hooked_fish == null):
		return
	
	print("Caught ", hooked_fish.fish_id)
	
	FishingManager.catch_fish(hooked_fish)
	finish_cast()
	
func finish_cast() -> void:
	reset_values()
	
	if(casts >= FishingManager.max_casts_per_session):
		exit_fishing()
	else:
		cast_rod()
	
func exit_fishing() -> void:
	if(current_state == Fish_State.FISHING && hooked_fish != null):
		FishingManager.lose_fish(hooked_fish)
	#reset everything upon exit
	reset_values()
	current_state = Fish_State.NOT
	casts = 0
	delay_time = press_delay
	print("finished fishing")
	get_parent().busy = false
	
func reset_values() -> void:
	progress = 0
	bite_time = 0
	fishing_progress.value = 0
	fishing_line.close()
	state_timer = 0
	fish_esc_rate = 0
	tension = 0
	tension_bar.value = tension
	fishing_line.set_tension(tension)
	hooked_fish = null
	recovery_timer = 0
	fishing_line.set_telegraph(0, 0.0)
	active_attack = null
	fishing_line.set_stunned(false)
	attack_phase = AttackPhase.RECOVERY
	counter_locked = false
	scroll_streak = 0

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_modal_ui_open():
		return
	if(event.is_action_pressed("Reel") && current_state == Fish_State.FISHING):
		if attempt_counter():
			return
		progress += reel_gain
		progress = clamp(progress,0,1)
		# A counter grants unrestricted reeling until the stun ends.
		if attack_phase != AttackPhase.STUN:
			tension = tension + tension_gain if fish_esc_rate <= 0 else tension + (tension_gain * tens_bonus_mult)
		tension = clamp(tension, 0, 1)
		fishing_line.set_tension(tension)
		
		recovery_timer = recovery_delay
		
		# Position, not an arbitrary progress threshold, determines landing.
		fishing_line.update_line_dist(progress)
		if fishing_line.fish_midpoint_above_water():
			catch_fish()
			return
		if tension >= 1:
			lose_fish()
	
	if(event.is_action_pressed("Interact") && current_state != Fish_State.NOT):
		exit_fishing()

func recover_tension(delta: float) -> void:
	if(recovery_timer <= 0):
			#tension recovery always happens, is higher during desperation phase
			tension = tension - (tension_recovery * delta)
	else:
		recovery_timer -= delta


# Preserve the fish's authored state selection, using nonnegative weights.
func select_attack() -> FishEscapeState:
	if hooked_fish == null or hooked_fish.states.is_empty():
		return null
	var total: float = 0.0
	for state in hooked_fish.states:
		if state != null:
			total += maxf(0.0, state.state_probability)
	if total <= 0.0:
		return hooked_fish.states.pick_random()
	var roll: float = randf() * total
	for state in hooked_fish.states:
		if state == null:
			continue
		roll -= maxf(0.0, state.state_probability)
		if roll <= 0.0:
			return state
	return hooked_fish.states.back()

func start_recovery(duration: float) -> void:
	fishing_line.set_stunned(false)
	attack_phase = AttackPhase.RECOVERY
	phase_time = duration
	fish_esc_rate = 0.0
	fishing_line.set_telegraph(1, 0.0)

func start_windup() -> void:
	active_attack = select_attack()
	if active_attack == null:
		start_recovery(0.5)
		return
	attack_phase = AttackPhase.WINDUP
	phase_time = active_attack.windup_duration
	fishing_line.set_windup_duration(active_attack.windup_duration)
	counter_locked = false
	scroll_streak = 0
	fish_esc_rate = 0.0
	print("Windup: ", active_attack.state_name)

func begin_attack() -> void:
	attack_phase = AttackPhase.ATTACK
	phase_time = maxf(active_attack.state_length, 0.05)
	attack_elapsed = 0.0
	fish_esc_rate = active_attack.escape_rate

func update_attack_cycle(delta: float) -> void:
	if active_attack == null and attack_phase != AttackPhase.RECOVERY:
		start_recovery(0.3)
	phase_time -= delta
	# Transition before updating the visuals so completed one-shots do not
	# linger for a frame at the end of their gameplay phase.
	if phase_time <= 0.0:
		match attack_phase:
			AttackPhase.RECOVERY: start_windup()
			AttackPhase.WINDUP: begin_attack()
			AttackPhase.ATTACK: start_recovery(active_attack.recovery_duration)
			AttackPhase.STUN: start_recovery(0.25)
	if attack_phase == AttackPhase.WINDUP:
		var elapsed: float = active_attack.windup_duration - phase_time
		# Reeling in early windup is forgiven, but not at the grace boundary.
		if elapsed >= active_attack.grace_start and not counter_locked:
			if Time.get_ticks_msec() - last_scroll_ms < int(scrolling_threshold * 1000.0):
				invalidate_counter()
		fishing_line.set_telegraph(2, clampf(elapsed / maxf(active_attack.windup_duration, 0.01), 0.0, 1.0))
	elif attack_phase == AttackPhase.ATTACK:
		attack_elapsed += delta
		fishing_line.set_telegraph(3, clampf(attack_elapsed / maxf(active_attack.state_length, 0.01), 0.0, 1.0))
	elif attack_phase == AttackPhase.STUN:
		fishing_line.set_telegraph(4, 0.0)
	else:
		fishing_line.set_telegraph(1, 0.0)

func invalidate_counter() -> void:
	if counter_locked:
		return
	counter_locked = true
	scroll_streak = 0
	# A missed counter does not interrupt the current ripple animation.

func attempt_counter() -> bool:
	var now: int = Time.get_ticks_msec()
	var previous: int = last_scroll_ms
	last_scroll_ms = now
	if active_attack == null or counter_locked:
		return false
	if attack_phase == AttackPhase.WINDUP:
		var elapsed: float = active_attack.windup_duration - phase_time
		if elapsed >= active_attack.grace_start:
			invalidate_counter()
		return false
	if attack_phase != AttackPhase.ATTACK:
		return false
	if attack_elapsed > active_attack.counter_window:
		invalidate_counter()
		return false
	# No stored scrolls from before the actual attack.
	if scroll_streak > 0 and now - previous > int(strong_reel_interval * 1000.0):
		invalidate_counter()
		return false
	scroll_streak += 1
	if scroll_streak < strong_reel_scrolls:
		return false
	counter_locked = true
	tension = maxf(0.0, tension - active_attack.counter_tension_relief)
	fishing_line.set_tension(tension)
	fishing_line.flash_counter(true)
	attack_phase = AttackPhase.STUN
	fishing_line.set_stunned(true)
	phase_time = active_attack.stun_duration
	fish_esc_rate = 0.0
	print("COUNTER: ", active_attack.state_name)
	return true
