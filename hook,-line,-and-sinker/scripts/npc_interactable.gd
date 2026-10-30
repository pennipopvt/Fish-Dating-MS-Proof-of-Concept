class_name NPCInteractable
extends Interactable

@export var npc: NPCData
@export var prompt: InteractPrompt

var _player_in_range := false


func _ready() -> void:
	super()
	DialogueManager.conversation_started.connect(_on_conversation_changed)
	DialogueManager.conversation_finished.connect(_on_conversation_changed)


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
	if npc == null:
	    push_warning("NPCInteractable needs npc assigned.")
	    return
	DialogueManager.request_conversation(npc)


func _on_conversation_changed(_npc: NPCData) -> void:
	_update_prompt()


func _update_prompt() -> void:
	if prompt == null:
	    return

	if _player_in_range and not DialogueManager.is_active:
	    prompt.pop_in()
	else:
	    prompt.pop_out()
