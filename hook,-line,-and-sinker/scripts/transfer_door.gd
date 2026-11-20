extends Interactable

@export var transfer_loc: Transform2D
@export var locked: bool = true

@onready var house: Sprite2D = $Sprite

func interact(_player: Node2D) -> void:
	if(locked or transfer_loc == null): return
	
	var talker := _player as Player
	
	talker.transform = transfer_loc

func update_door(loc: Transform2D,sprite:Texture2D) -> void:
	transfer_loc = loc
	house.texture = sprite
