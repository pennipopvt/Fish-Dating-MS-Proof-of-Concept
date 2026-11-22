class_name TransferDoor
extends Interactable

# Doors share interaction prompts and forward their room ID. RecruitmentHandler
# controls which resident rooms are available; Penni's own door is permanent.
signal room_requested(door: TransferDoor)

@export var room_id: StringName = &""
@export var locked: bool = true
@export var locked_texture: Texture2D = preload("res://sprites/rooms/lockeddoor.png")
# Optional scene-authored art for a door whose access changes via story.
# Other resident doors continue using their own NPCData.door texture.
@export var accessible_texture: Texture2D
@export var prompt: InteractPrompt
@onready var house: Sprite2D = $Sprite # Original scene node name, retained.
var resident: NPCData = null
var _nearby_player: Player


func _ready() -> void:
	super()
	_update_prompt()


func _process(_delta: float) -> void:
	# A player may become busy/free without crossing the door's area again.
	if _nearby_player != null:
		_update_prompt()


func _on_body_entered(body: Node2D) -> void:
	super(body)
	if body is Player:
		_nearby_player = body as Player
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	super(body)
	if body == _nearby_player:
		_nearby_player = null
		_update_prompt()


func _update_prompt() -> void:
	if prompt == null:
		return
	if not locked and is_instance_valid(_nearby_player) and not _nearby_player.busy \
			and not DialogueManager.is_active and not GameManager.is_modal_ui_open():
		prompt.pop_in()
	else:
		prompt.pop_out()


# The first-dive story unlocks Penni's reserved room via this method.
# Only the access state changes here; textures are authored in the editor.
func set_room_access_enabled(enabled: bool) -> void:
	locked = not enabled
	if is_node_ready():
		if accessible_texture != null:
			house.texture = accessible_texture if enabled else locked_texture
		_update_prompt()


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
		_update_prompt()


func clear_resident() -> void:
	set_resident(null)
