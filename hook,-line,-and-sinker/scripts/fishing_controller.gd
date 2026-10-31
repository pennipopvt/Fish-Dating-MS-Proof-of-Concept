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

# Temporary pattern/counter test, independently toggleable in Inspector.
@export var counter_test: bool = true
@export var windup_duration: float = 0.8
@export var counter_window: float = 0.18
@export var stun_duration: float = 1.8
@export var attacks_before_exhaustion: int = 4
var test_phase: int = 0 # 0 rest, 1 windup, 2 pull, 3 stagger, 4 exhausted
var phase_clock: float = 1.5
var attacks_done: int = 0
var recent_scrolls: int = 0
var last_scroll_ms: int = 0


#band-aid fix to avoid accidentally requeueing interact when exiting since exit and interact are the same input
var press_delay: float = 0.10
var delay_time = 0

@export var reel_gain: float = 0.1
@export var starting_progress: float = 0.2
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
		progress -= fish_esc_rate * delta
		progress = clamp(progress,0,1)
		
		recover_tension(delta)
		if counter_test:
			update_counter_test(delta)
		else:
			state_change_countdown(delta)
		
		tension = clamp(tension,0,1)
		fishing_progress.value = progress
		tension_bar.value = tension
		fishing_line.update_line_dist(progress)
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
	
	fish_esc_rate = hooked_fish.states[0].escape_rate
	state_timer = hooked_fish.states[0].state_length
	if counter_test:
		attacks_done = 0
		set_test_phase(0)
	
	#once we actually get it, we will let the fishing manager know what fish we have
	FishingManager.hook_fish(hooked_fish)
	print("Found ", hooked_fish.fish_id)
	print("In ", hooked_fish.states[0].state_name," State.")

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
	hooked_fish = null
	recovery_timer = 0
	fishing_line.set_telegraph(0, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_modal_ui_open():
		return
	if(event.is_action_pressed("Reel") && current_state == Fish_State.FISHING):
		if counter_test and try_counter():
			return
		progress += reel_gain
		progress = clamp(progress,0,1)
		# so if the fish isnt swimming dont apply tension
		tension = tension + tension_gain if fish_esc_rate <= 0 else tension + (tension_gain * tens_bonus_mult)
		tension = clamp(tension, 0, 1)
		
		recovery_timer = recovery_delay
		
		if(progress >= 1):
			catch_fish()
		if(tension >= 1):
			lose_fish()
	
	if(event.is_action_pressed("Interact") && current_state != Fish_State.NOT):
		exit_fishing()

func recover_tension(delta: float) -> void:
	if(recovery_timer <= 0):
			#tension recovery always happens, is higher during desperation phase
			tension = tension - (tension_recovery * delta)
	else:
		recovery_timer -= delta

func state_change_countdown(delta:float) -> void:
	state_timer -= delta
	
	if(state_timer <= 0 && current_state == Fish_State.FISHING):
		change_fish_state()

func change_fish_state() -> void:
	if hooked_fish.states.is_empty():
		return
	for state in hooked_fish.states:
		var probability: float = randf()
		if(probability < state.state_probability):
			fish_esc_rate = state.escape_rate
			state_timer = state.state_length
			print("In ", state.state_name," State.")
			return
	#goes to a non-probability based random pick if none were chosen
	var true_random: int = randi_range(0,hooked_fish.states.size() - 1)
	fish_esc_rate = hooked_fish.states[true_random].escape_rate
	state_timer = hooked_fish.states[true_random].state_length
	print("In ", hooked_fish.states[true_random].state_name," State.")

func set_test_phase(phase: int) -> void:
	test_phase = phase
	match phase:
		0:
			phase_clock = 1.5
			fish_esc_rate = 0.0
		1:
			phase_clock = windup_duration
			fish_esc_rate = 0.0
		2:
			phase_clock = 1.0
			fish_esc_rate = 0.2
		3:
			phase_clock = stun_duration
			fish_esc_rate = 0.0
		4:
			phase_clock = 4.0
			fish_esc_rate = 0.0
	fishing_line.set_telegraph(phase + 1, 0.0)

func update_counter_test(delta: float) -> void:
	phase_clock -= delta
	var total: float = windup_duration if test_phase == 1 else 1.0
	fishing_line.set_telegraph(test_phase + 1, 1.0 - clampf(phase_clock / total, 0.0, 1.0))
	if phase_clock > 0.0:
		return
	match test_phase:
		0: set_test_phase(1)
		1: set_test_phase(2)
		2:
			attacks_done += 1
			set_test_phase(4 if attacks_done >= attacks_before_exhaustion else 0)
			if test_phase == 4:
				attacks_done = 0
		3, 4: set_test_phase(0)

func try_counter() -> bool:
	var now: int = Time.get_ticks_msec()
	if now - last_scroll_ms > 180:
		recent_scrolls = 0
	last_scroll_ms = now
	recent_scrolls += 1
	if recent_scrolls < 3:
		return false
	recent_scrolls = 0
	if test_phase == 2 and phase_clock >= 1.0 - counter_window:
		tension = maxf(0.0, tension - 0.25)
		fishing_line.flash_counter(true)
		set_test_phase(3)
		print("COUNTER! Stunned and tension reduced.")
		return true
	if test_phase == 1 or test_phase == 2:
		tension = minf(1.0, tension + 0.18)
		fishing_line.flash_counter(false)
		print("Missed counter.")
	return false
