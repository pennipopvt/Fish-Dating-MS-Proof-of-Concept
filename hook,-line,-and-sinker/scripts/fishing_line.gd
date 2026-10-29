extends Line2D

#this is kinda temporary im figuring out line2D
#also idk if ur gonna make like, a manually animated fishing rod or not
#so im not putting too much stock into this

@export var max_dist: float
@export var y_line_offset: float
@onready var fish: Sprite2D = $Fish
var line_dist : float = 0
var pos: Vector2

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
func hook(item: ItemData) -> void:
	fish.texture = item.sprite
	fish.show()

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
