class_name TransferDoor
extends Interactable

# The townhouse transfers within the existing World. Fade instead of moving
# NPCs or requiring an additional world/scene and walking animations.
@export var transfer_loc: Vector2 = Vector2.ZERO
@export var locked: bool = true
@onready var house: Sprite2D = $Sprite
signal fade_to()

var _transferring: bool = false


func interact(who: Node2D) -> void:
	if locked or _transferring:
		return
	var player: Player = who as Player
	if player == null or player.busy:
		return
	_transferring = true
	player.busy = true
	_travel(player)


func _travel(player: Player) -> void:
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, 0.32)
	player.global_position = transfer_loc
	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
		camera.force_update_scroll()
	fade_to.emit()
	await fade.fade_to(0.0, 0.32)
	fade.queue_free()
	player.busy = false
	_transferring = false


func update_door(loc: Vector2, sprite: Texture2D) -> void:
	transfer_loc = loc
	if house != null and sprite != null:
		house.texture = sprite
