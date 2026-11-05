extends Node

@export var available_homes: Array[Sprite2D] = []

#Sorry i dont know if this is the most effective way to do it im just so sleepy
#i wanted recruitment handler to be referenced globally
#but idk if its good practice to put a global script in a scene
#so im just having this pass along the info of what homes are free
func _ready() -> void:
	RecruitmentHandler.available_homes = available_homes
