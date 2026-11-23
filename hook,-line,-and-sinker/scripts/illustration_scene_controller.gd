class_name IllustrationSceneController
extends CanvasLayer

# Presentation for any NPCData-authored illustrated encounter.
# Room progression, passage of time and morning dialogue belong to NPCRoomView.
signal scene_finished(npc: NPCData, scene_id: StringName, completed: bool)

const FADE_DURATION := 0.75
const MUSIC_FADE_DURATION := 0.75

@onready var background: ColorRect = $Background
@onready var warning_screen: ColorRect = $WarningScreen
@onready var skip_button: Button = $WarningScreen/Center/Choices/SkipButton
@onready var show_button: Button = $WarningScreen/Center/Choices/ShowButton
@onready var placeholder_label: Label = $Background/PlaceholderLabel
@onready var placeholder_image: TextureRect = $Background/PlaceholderImage
@onready var fade_layer: CanvasLayer = $FadeLayer
@onready var fade_rect: ColorRect = $FadeLayer/Fade
@onready var overnight_interlude: CenterContainer = $FadeLayer/OvernightInterlude
@onready var sleep_text: Label = $FadeLayer/OvernightInterlude/Content/SleepText
@onready var interlude_continue: Button = $FadeLayer/OvernightInterlude/Content/ContinueButton
@onready var dialogue_ui: DialogueUI = get_parent().get_node("CanvasLayer/DialogueUI")
@onready var overworld_music: AudioStreamPlayer2D = get_parent().get_node("AudioStreamPlayer2D")

var _active_npc: NPCData
var _active_scene_id: StringName = &""
var _transitioning: bool = false
var _scene_dialogue_started: bool = false
var _music_stopped_for_scene: bool = false
var _music_normal_volume_db: float = 0.0
var _interlude_active: bool = false


func _ready() -> void:
	_music_normal_volume_db = overworld_music.volume_db
	background.hide()
	placeholder_image.texture = null
	placeholder_image.hide()
	warning_screen.hide()
	fade_layer.hide()
	overnight_interlude.hide()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	background.add_to_group(&"modal_ui")
	warning_screen.add_to_group(&"modal_ui")
	skip_button.pressed.connect(_on_skip_pressed)
	show_button.pressed.connect(_on_show_pressed)
	fade_layer.add_to_group(&"modal_ui")
	DialogueManager.scene_requested.connect(_on_scene_requested)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	RecruitmentHandler.fade_to.connect(_basic_fade)


# Preserve existing dialogue scene requests for any future scripted scenes.
# The standard romance route now calls start_scene from its nighttime room entry.
func _on_scene_requested(npc: NPCData, scene_id: String) -> void:
	if npc != null and StringName(scene_id) == npc.intimacy_scene_id:
		start_scene(npc)


func start_scene(npc: NPCData) -> bool:
	if npc == null or _active_npc != null or _transitioning \
			or npc.intimacy_scene_id == &"" or npc.intimacy_dialogue_json.is_empty() \
			or DialogueManager.is_active:
		return false
	_active_npc = npc
	_active_scene_id = npc.intimacy_scene_id
	_transitioning = true
	_scene_dialogue_started = false
	_open_scene()
	return true


func _open_scene() -> void:
	await _fade_to(1.0)
	# The opt-in warning always appears BEFORE any adult illustration.
	warning_screen.show()
	await _fade_to(0.0)
	_transitioning = false
	skip_button.grab_focus()


func _basic_fade() -> void:
	if _active_npc != null or _transitioning:
		return
	_transitioning = true
	await _fade_to(1.0)
	await _fade_to(0.0)
	_transitioning = false


func _on_skip_pressed() -> void:
	if _active_npc == null or _transitioning:
		return
	# Skipping affects only presentation, never the eventual morning outcome.
	_finish_scene(true)


func _on_show_pressed() -> void:
	if _active_npc == null or _transitioning:
		return
	_transitioning = true
	_start_illustration()


func _start_illustration() -> void:
	var music_tween: Tween = create_tween()
	music_tween.tween_property(overworld_music, "volume_db", -80.0, MUSIC_FADE_DURATION)
	await _fade_to(1.0)
	music_tween.kill()
	overworld_music.stop()
	overworld_music.volume_db = _music_normal_volume_db
	_music_stopped_for_scene = true
	warning_screen.hide()
	background.color = Color.BLACK
	placeholder_label.hide()
	placeholder_image.texture = _active_npc.porn_sprite
	placeholder_image.visible = placeholder_image.texture != null
	background.show()
	dialogue_ui.set_illustration_mode(true)
	await _fade_to(0.0)
	_transitioning = false
	_scene_dialogue_started = true
	DialogueManager.request_conversation(_active_npc, _active_npc.intimacy_dialogue_json)
	if not DialogueManager.is_active:
		# Never advance the relationship after a missing/invalid scene.
		_finish_scene(false)


func _on_conversation_finished(npc: NPCData) -> void:
	if _active_npc == null or not _scene_dialogue_started or _transitioning \
			or npc != _active_npc:
		return
	_finish_scene(true)


func _finish_scene(completed: bool) -> void:
	if _active_npc == null or _transitioning:
		return
	_transitioning = true
	var finished_npc: NPCData = _active_npc
	var finished_id: StringName = _active_scene_id
	await _fade_to(1.0)
	background.hide()
	placeholder_image.hide()
	placeholder_image.texture = null
	warning_screen.hide()
	dialogue_ui.set_illustration_mode(false)
	_active_npc = null
	_active_scene_id = &""
	_scene_dialogue_started = false
	# Hold on a quiet, readable black screen before the day changes.
	# Both the shown and skipped illustration take this exact same path.
	if completed:
		await _show_overnight_interlude(finished_npc)
	if _music_stopped_for_scene:
		overworld_music.volume_db = _music_normal_volume_db
		overworld_music.play(0.0)
		_music_stopped_for_scene = false
	# Advance the clock and show morning dialogue only AFTER Continue.
	# Remain at full black until the room has switched presentation.
	scene_finished.emit(finished_npc, finished_id, completed)
	await _fade_to(0.0)
	_transitioning = false


# The same fade + sleep-text + Continue presentation as NPC overnights,
# without the adult-scene warning or romance progression.
# The room/clock owner runs its swap exactly once while the screen is black.
func play_rest_transition(message: String, on_black: Callable) -> bool:
	if _active_npc != null or _transitioning or not on_black.is_valid():
		return false
	_transitioning = true
	await _fade_to(1.0)
	await _show_sleep_interlude(message)
	on_black.call()
	await _fade_to(0.0)
	_transitioning = false
	return true


func _show_overnight_interlude(npc: NPCData) -> void:
	await _show_sleep_interlude(npc.overnight_transition_text if not npc.overnight_transition_text.is_empty()
		else "You drift off to sleep.")


func _show_sleep_interlude(message: String) -> void:
	sleep_text.text = message if not message.is_empty() else "You drift off to sleep."
	_interlude_active = true
	overnight_interlude.show()
	interlude_continue.grab_focus()
	await interlude_continue.pressed
	overnight_interlude.hide()
	_interlude_active = false


func _fade_to(alpha: float) -> void:
	fade_layer.show()
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", alpha, FADE_DURATION)
	await tween.finished
	if alpha <= 0.0:
		fade_layer.hide()
