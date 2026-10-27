class_name NPCInteractable
extends Interactable

@export var npc: NPCData
@export var dialogue_ui: DialogueUI
@export var prompt: InteractPrompt

var _player_in_range := false


func _ready() -> void:
	super()

	if dialogue_ui != null:
		dialogue_ui.visibility_changed.connect(_update_prompt)


func _on_body_entered(body: Node2D) -> void:
	super(body)

	if body is Player:
		_player_in_range = true
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	super(body)

	if body is Player:
		_player_in_range = false
		_update_prompt()


func interact(_player: Node2D) -> void:
	if npc == null or dialogue_ui == null:
		push_warning("NPCInteractable needs both npc and dialogue_ui assigned.")
		return

	dialogue_ui.start(npc)


# Show the key prompt only while the player can start talking.
func _update_prompt() -> void:
	if prompt == null:
		return

	var talking := dialogue_ui != null and dialogue_ui.visible

	if _player_in_range and not talking:
		prompt.pop_in()
	else:
		prompt.pop_out()
