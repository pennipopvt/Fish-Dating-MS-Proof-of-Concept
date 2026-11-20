extends Node

@export var available_homes: Array[Sprite2D] = []

# The world registers its empty houses with the RecruitmentHandler autoload.
# Future construction / move-out systems should call register_available_home()
# when a house actually becomes free, so queued NPCs move in automatically.
func _ready() -> void:
	RecruitmentHandler.set_available_homes(available_homes)
