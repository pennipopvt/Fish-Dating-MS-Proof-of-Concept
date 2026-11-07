extends CanvasLayer

# A reusable illustrated encounter layer. The overworld remains loaded.
# Only the shared DialogueUI changes presentation: its portraits are hidden.
const SCENES := {
	"silas_house": {
		"title": "Silas's House",
		"dialogue": "res://dialogue/garden_eel_house_scene.json",
		# Post-scene dialogue runs in the overworld, after fading back in.
		"post_dialogue": "res://dialogue/garden_eel_after_scene.json",
		"reward_item": "silas"
	}
}
const FADE_DURATION := 0.75
const MUSIC_FADE_DURATION := 0.75

# Connect a cosmetic award handler when the reward has been designed.
signal cosmetic_reward_requested(npc: NPCData, reward_id: String)

@onready var background: ColorRect = $Background
@onready var warning_screen: ColorRect = $WarningScreen
@onready var skip_button: Button = $WarningScreen/Center/Choices/SkipButton
@onready var show_button: Button = $WarningScreen/Center/Choices/ShowButton
@onready var placeholder_label: Label = $Background/PlaceholderLabel
@onready var fade_layer: CanvasLayer = $FadeLayer
@onready var fade_rect: ColorRect = $FadeLayer/Fade
@onready var dialogue_ui: DialogueUI = get_parent().get_node("CanvasLayer/DialogueUI")
@onready var overworld_music: AudioStreamPlayer2D = get_parent().get_node("AudioStreamPlayer2D")

var _active_npc: NPCData = null
var _active_scene_id: String = ""
var _pending_scene_data: Dictionary = {}
var _transitioning := false
var _scene_dialogue_started := false
var _post_scene_npc: NPCData = null
var _post_scene_reward_id: String = ""
var _music_stopped_for_scene := false
var _music_normal_volume_db: float = 0.0

func _ready() -> void:
	_music_normal_volume_db = overworld_music.volume_db
	background.hide()
	warning_screen.hide()
	fade_layer.hide()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	background.add_to_group(&"modal_ui")
	warning_screen.add_to_group(&"modal_ui")
	skip_button.pressed.connect(_on_skip_pressed)
	show_button.pressed.connect(_on_show_pressed)
	fade_layer.add_to_group(&"modal_ui")
	DialogueManager.scene_requested.connect(_on_scene_requested)
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	
	#im uh gonna FORCE myself in here
	RecruitmentHandler.fade_to.connect(_basic_fade)
	cosmetic_reward_requested.connect(_on_cosmetic_reward_requested)

func _on_scene_requested(npc: NPCData, scene_id: String) -> void:
	if _active_npc != null or not SCENES.has(scene_id) or npc == null:
		return
	_active_npc = npc
	_active_scene_id = scene_id
	_transitioning = true
	_scene_dialogue_started = false
	_open_scene(scene_id)

func _open_scene(scene_id: String) -> void:
	await _fade_to(1.0)
	_pending_scene_data = SCENES[scene_id]
	# Show the opt-in warning BEFORE revealing any illustrated content.
	warning_screen.show()
	await _fade_to(0.0)
	_transitioning = false
	skip_button.grab_focus()

func _basic_fade() -> void:
	#i have forced myself in here hello its me
	_transitioning = true
	await _fade_to(1.0)
	await _fade_to(0.0)
	_transitioning = false

func _on_skip_pressed() -> void:
	if _active_npc == null or _transitioning:
		return
	# Skipping the optional adult scene still counts as completing the route.
	_finish_scene(true)


func _on_show_pressed() -> void:
	if _active_npc == null or _transitioning:
		return
	_transitioning = true
	_start_illustration()


func _start_illustration() -> void:
	# Fade the overworld music out together with the screen, then stay silent.
	var music_tween := create_tween()
	music_tween.tween_property(overworld_music, "volume_db", -80.0, MUSIC_FADE_DURATION)
	await _fade_to(1.0)
	music_tween.kill()
	overworld_music.stop()
	overworld_music.volume_db = _music_normal_volume_db
	_music_stopped_for_scene = true
	warning_screen.hide()
	placeholder_label.text = str(_pending_scene_data.get("title", "Illustration")) + "\n[Placeholder illustration]"
	background.show()
	dialogue_ui.set_illustration_mode(true)
	await _fade_to(0.0)
	_transitioning = false
	# Start via the existing DialogueUI only after the warning was accepted.
	_scene_dialogue_started = true
	DialogueManager.request_conversation(_active_npc, str(_pending_scene_data["dialogue"]))
	if not DialogueManager.is_active:
		# Missing/invalid dialogue returns safely without a completion flag.
		_finish_scene()

func _on_conversation_finished(npc: NPCData) -> void:
	if _post_scene_npc != null and npc == _post_scene_npc:
		# Finish the NPC's route first, then grant the gift. The bobber
		# manager checks this flag before accepting Silas's unlock.
		_mark_route_complete(npc)
		if not _post_scene_reward_id.is_empty():
			cosmetic_reward_requested.emit(npc, _post_scene_reward_id)
		_post_scene_reward_id = ""
		_post_scene_npc = null
		return
	if _active_npc == null or not _scene_dialogue_started or _transitioning or npc != _active_npc:
		return
	_finish_scene(true)

func _finish_scene(completed: bool = false) -> void:
	if _transitioning:
		return
	_transitioning = true
	# Hold onto the NPC and post-dialogue path before clearing scene state.
	var finished_npc := _active_npc
	var finished_scene_id := _active_scene_id
	var post_path := str(_pending_scene_data.get("post_dialogue", ""))
	var reward_id := str(_pending_scene_data.get("reward_item", ""))
	await _fade_to(1.0)
	# At full black, restore the overworld and normal portrait layout.
	background.hide()
	warning_screen.hide()
	dialogue_ui.set_illustration_mode(false)
	_active_npc = null
	_active_scene_id = ""
	_pending_scene_data = {}
	_scene_dialogue_started = false
	# Restart the overworld track from its beginning as we return.
	if _music_stopped_for_scene:
		overworld_music.volume_db = _music_normal_volume_db
		overworld_music.play(0.0)
		_music_stopped_for_scene = false
	await _fade_to(0.0)
	_transitioning = false
	if not completed or finished_npc == null or finished_scene_id != "silas_house":
		return
	if post_path.is_empty():
		# No gift dialogue means no reward was given; never auto-unlock.
		push_warning("Silas reward dialogue is missing; bobber remains locked.")
		return
	# Whether the player watched or skipped the optional adult scene, Silas
	# speaks automatically after the return fade. Complete the route afterward.
	_post_scene_npc = finished_npc
	_post_scene_reward_id = reward_id
	DialogueManager.request_conversation(finished_npc, post_path)
	if not DialogueManager.is_active:
		push_warning("Post-scene dialogue could not start: " + post_path)
		_post_scene_npc = null
		_post_scene_reward_id = ""
		# No reward is granted without completing the gift dialogue.
		# Leave the route incomplete if the gift dialogue fails to start.


# Grant the bobber only after Silas's post-scene gift dialogue finishes.
func _on_cosmetic_reward_requested(npc: NPCData, reward_id: String) -> void:
	if npc == null or npc.npc_id != &"test_npc":
		return
	BobberManager.unlock_bobber(StringName(reward_id))


func _mark_route_complete(npc: NPCData) -> void:
	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
	flags[&"silas_route_complete"] = true

func _fade_to(alpha: float) -> void:
	fade_layer.show()
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", alpha, FADE_DURATION)
	await tween.finished
	if alpha <= 0.0:
		fade_layer.hide()
