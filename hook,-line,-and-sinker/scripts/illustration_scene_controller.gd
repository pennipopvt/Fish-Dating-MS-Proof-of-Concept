extends CanvasLayer

# A reusable illustrated encounter layer. The overworld remains loaded.
# Only the shared DialogueUI changes presentation: its portraits are hidden.
const SCENES := {
	"silas_house": {
		"title": "Silas's House",
		"dialogue": "res://dialogue/garden_eel_house_scene.json"
	}
}
const FADE_DURATION := 0.6

@onready var background: ColorRect = $Background
@onready var placeholder_label: Label = $Background/PlaceholderLabel
@onready var fade_layer: CanvasLayer = $FadeLayer
@onready var fade_rect: ColorRect = $FadeLayer/Fade
@onready var dialogue_ui: DialogueUI = get_parent().get_node("CanvasLayer/DialogueUI")

var _active_npc: NPCData = null
var _transitioning := false
var _scene_dialogue_started := false

func _ready() -> void:
	hide()
	fade_layer.hide()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	add_to_group(&"modal_ui")
	DialogueManager.scene_requested.connect(_on_scene_requested)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)

func _on_scene_requested(npc: NPCData, scene_id: String) -> void:
	if _active_npc != null or not SCENES.has(scene_id) or npc == null:
		return
	_active_npc = npc
	_transitioning = true
	_scene_dialogue_started = false
	_open_scene(scene_id)

func _open_scene(scene_id: String) -> void:
	await _fade_to(1.0)
	var scene_data: Dictionary = SCENES[scene_id]
	placeholder_label.text = str(scene_data.get("title", "Illustration")) + "\n[Placeholder illustration]"
	show()
	dialogue_ui.set_illustration_mode(true)
	await _fade_to(0.0)
	_transitioning = false
	# Start via the existing DialogueUI after the invitation has fully closed.
	_scene_dialogue_started = true
	DialogueManager.request_conversation(_active_npc, str(scene_data["dialogue"]))
	if not DialogueManager.is_active:
		# Missing or invalid placeholder dialogue should never strand the player.
		_finish_scene()

func _on_conversation_finished(npc: NPCData) -> void:
	if _active_npc == null or not _scene_dialogue_started or _transitioning or npc != _active_npc:
		return
	_finish_scene()

func _finish_scene() -> void:
	if _transitioning:
		return
	_transitioning = true
	await _fade_to(1.0)
	# At full black, return to the still-loaded overworld.
	hide()
	dialogue_ui.set_illustration_mode(false)
	_active_npc = null
	_scene_dialogue_started = false
	await _fade_to(0.0)
	_transitioning = false

func _fade_to(alpha: float) -> void:
	fade_layer.show()
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", alpha, FADE_DURATION)
	await tween.finished
	if alpha <= 0.0:
		fade_layer.hide()
