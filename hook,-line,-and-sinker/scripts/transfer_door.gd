extends Interactable

@export var transfer_loc: Vector2
@export var locked: bool = true

@onready var house: Sprite2D = $Sprite
signal fade_to()

func interact(_player: Node2D) -> void:
	if(locked or transfer_loc == null): return
	
	var talker := _player as Player
	
	talker.global_position = transfer_loc
	fade_to.emit()
	

func update_door(loc: Vector2,sprite:Texture2D) -> void:
	transfer_loc = loc
	house.texture = sprite
