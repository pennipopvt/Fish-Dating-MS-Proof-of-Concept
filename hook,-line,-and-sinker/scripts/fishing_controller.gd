extends Node

enum Fish_State
{
	NOT,
	WAITING,
	FISHING
}

var current_state: Fish_State = Fish_State.NOT
var hooked_fish: ItemData = null

var casts: int = 0
var progress: float = 0
var bite_time: float = 0

#band-aid fix to avoid accidentally requeueing interact when exiting since exit and interact are the same input
var press_delay: float = 0.10
var delay_time = 0

@export var reel_gain: float = 0.1
@export var starting_progress: float = 0.2
@export var bite_time_min: float = 1
@export var bite_time_max: float = 20

func begin_fishing() -> void:
	if(current_state == Fish_State.NOT && delay_time == 0):
		casts = 0
		cast_rod()
		get_parent().busy = true
	
func cast_rod() -> void:
	if(casts >= FishingManager.max_casts_per_session):
		exit_fishing()
		return
	casts += 1
	current_state = Fish_State.WAITING
	
	progress = starting_progress
	#once a line is cast, set the time itll take for a fish to present itself!!
	bite_time = randf_range(bite_time_min,bite_time_max)
	#fish is decided on rod cast
	hooked_fish = FishingManager.possible_catches.pick_random()
	print("Cast #", casts, "will be a ", hooked_fish.item_id)

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
		progress -= hooked_fish.escape_rate * delta
		progress = clamp(progress,0,1)
		if(progress <= 0):
			lose_fish()
	elif(current_state == Fish_State.NOT && delay_time != 0):
		delay_time -= delta
		delay_time = clamp(delay_time,0,1)

func begin_reeling() -> void:
	current_state = Fish_State.FISHING
	#reset progress when finding a fish
	progress = starting_progress
	#once we actually get it, we will let the fishing manager know what fish we have
	FishingManager.hook_fish(hooked_fish)
	print("Found ", hooked_fish.item_id)

func lose_fish() -> void:
	if(hooked_fish == null):
		return
	#inform the fishing manager
	print("Lost ", hooked_fish.item_id)
	FishingManager.lose_fish(hooked_fish)
	finish_cast()
	
func catch_fish() -> void:
	if(hooked_fish == null):
		return
	
	print("Caught ", hooked_fish.item_id)
	
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
	hooked_fish = null

func _unhandled_input(event: InputEvent) -> void:
	if(event.is_action_pressed("Reel") && current_state == Fish_State.FISHING):
		progress += reel_gain
		progress = clamp(progress,0,1)
		
		if(progress >= 1):
			catch_fish()
			
	if(event.is_action_pressed("Interact") && current_state != Fish_State.NOT):
		exit_fishing()
		
