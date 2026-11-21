class_name TransferDoor
extends Interactable

# Each exterior door is a view onto RecruitmentHandler's room assignment.
# No world coordinates or physical NPC movement are involved.
signal room_requested(door: TransferDoor)

@export var room_id: StringName = &""
@export var locked: bool = true
@export var locked_texture: Texture2D = preload("res://sprites/rooms/lockeddoor.png")
@onready var house: Sprite2D = $Sprite # Original scene node name, retained.
var resident: NPCData = null


func get_room_id() -> StringName:
	return room_id if room_id != &"" else StringName(name)


func interact(who: Node2D) -> void:
	if locked or who == null or not who is Player or (who as Player).busy:
		return
	room_requested.emit(self)


func set_resident(data: NPCData) -> void:
	resident = data
	locked = data == null
	if is_node_ready():
		house.texture = (data.door.door if data.door != null and data.door.door != null
			else locked_texture) if data != null else locked_texture


func clear_resident() -> void:
	set_resident(null)
