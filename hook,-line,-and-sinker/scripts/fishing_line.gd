extends Line2D

#this is kinda temporary im figuring out line2D
#also idk if ur gonna make like, a manually animated fishing rod or not
#so im not putting too much stock into this

@export var max_dist: float
@export var y_line_offset: float
@onready var fish: Sprite2D = $Fish
var line_dist : float = 0
var pos: Vector2

@export var water_surface_y: float = 44.0
var tell_phase: int = 0
var tell_progress: float = 0.0
var flash_timer: float = 0.0
var flash_good: bool = false


func _ready() -> void:
	FishingManager.fish_hooked.connect(hook)
	hide()

func send() -> void:
	#later i wanna add an animation of it being sent into da water
	pos = get_point_position(0)
	var endpos = pos
	endpos.x -= max_dist
	endpos.y += max_dist
	set_point_position(1,endpos)
	show()
	fish.hide()

#idk how to listen for signals in godot tbh but this would trigger by signal ill adjust later
func hook(item: FishData) -> void:
	fish.texture = item.item_data.sprite
	fish.show() # Let the scene's water layer determine visibility.

func close() -> void:
	hide()
	fish.hide()

func update_line_dist(dist_perc: float) -> void:
	#okey so this simple i think
	#basically it just gonna take the progress of the fish encounter
	#then subtract it from one, because u wanna be further from the max distance the more u reel
	line_dist = max_dist * (1 - dist_perc)
	line_dist = clamp(line_dist,0,max_dist)
	var endpos = pos
	endpos.x -= line_dist
	#slight offset to keep the fish in what would be the water
	endpos.y += (line_dist + y_line_offset)
	fish.position = endpos
	var fishrot: float = atan2((pos.y - endpos.y),(pos.x - endpos.x))
	fish.rotation = fishrot
	set_point_position(1,endpos)

func set_telegraph(phase: int, amount: float) -> void:
	tell_phase = phase
	tell_progress = amount
	queue_redraw()

func flash_counter(success: bool) -> void:
	flash_good = success
	flash_timer = 0.3
	queue_redraw()

func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer = maxf(0.0, flash_timer - delta)
		queue_redraw()

func _draw() -> void:
	if not visible or tell_phase == 0:
		return
	var start: Vector2 = get_point_position(0)
	var tip: Vector2 = get_point_position(1)
	var fraction: float = clampf((water_surface_y - start.y) / (tip.y - start.y), 0.0, 1.0) if absf(tip.y - start.y) > 0.01 else 1.0
	var center: Vector2 = start.lerp(tip, fraction)
	if tell_phase == 2: # windup ripple, grows toward attack
		var radius: float = 3.0 + tell_progress * 12.0
		draw_arc(center, radius, 0.0, TAU, 24, Color(0.9, 1.0, 1.0), 2.0)
		draw_arc(center, maxf(2.0, radius - 6.0), 0.0, TAU, 24, Color(0.4, 1.0, 0.96), 1.5)
	elif tell_phase == 3: # sharp splash at attack
		var tint: Color = Color(1.0, 1.0, 0.55) if tell_progress < 0.2 else Color(0.8, 0.95, 1.0)
		draw_line(center + Vector2(-9, 0), center + Vector2(-4, -9), tint, 2.0)
		draw_line(center, center + Vector2(0, -12), tint, 2.0)
		draw_line(center + Vector2(9, 0), center + Vector2(4, -9), tint, 2.0)
	elif tell_phase == 4 or tell_phase == 5:
		draw_arc(center, 7.0, 0.0, TAU, 20, Color(0.5, 1.0, 0.7), 2.0)
	if flash_timer > 0.0:
		var color: Color = Color(0.3, 1.0, 0.5) if flash_good else Color(1.0, 0.25, 0.2)
		draw_arc(center, 15.0 * flash_timer / 0.3 + 3.0, 0.0, TAU, 24, color, 2.5)
