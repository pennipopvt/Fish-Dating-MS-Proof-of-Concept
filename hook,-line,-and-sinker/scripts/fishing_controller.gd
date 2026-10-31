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

func _unhandled_input(event: InputEvent) -> void:
	if DialogueManager.is_active or ShopManager.is_shop_open:
		return
	if(event.is_action_pressed("Reel") && current_state == Fish_State.FISHING):
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
