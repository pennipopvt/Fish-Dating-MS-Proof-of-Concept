class_name DialogueUI
extends CanvasLayer

# Player-facing dialogue box. Conversation state lives in DialogueManager;
# this script only displays it and forwards the player's input.

signal conversation_ended(npc: NPCData)

const PLAYER_NAME := "Penni"
# Conversations with no second character to show (see _show_line).
const NO_PORTRAIT_NPCS: Array[StringName] = [&"penni_monologue", &"dock_dive_prompt"]
const NPC_NAME_COLOR := Color(1.0, 0.85, 0.5)
const PLAYER_NAME_COLOR := Color(0.6, 0.85, 1.0)
const SPEAKING_MODULATE := Color.WHITE
const LISTENING_MODULATE := Color(0.5, 0.5, 0.55)
const ADVANCE_ACTION := &"Interact"
const LETTER_POP_EFFECT = preload("res://scripts/ui/dialogue_letter_pop.gd")
# Choices picked before (no more affection from them): grey, still pickable.
const PICKED_CHOICE_COLOR := Color(0.55, 0.55, 0.6)

# Shown when an NPC has no portrait assigned yet.
@export var placeholder_portrait: Texture2D
@export var player_portrait: Texture2D

@export_group("Dialogue Typing")
@export var typewriter_enabled: bool = true
@export_range(8.0, 120.0, 1.0, "suffix:chars/s") var characters_per_second: float = 36.0
@export_range(0.0, 0.6, 0.01, "suffix:s") var letter_bounce_seconds: float = 0.18
@export_range(0.0, 0.6, 0.01) var letter_scale_boost: float = 0.16
@export_range(0.0, 8.0, 0.25, "suffix:px") var letter_jitter_pixels: float = 2.0

@export_group("Dialogue Voice")
# All speakers use the Penni speak audio unless their NPCData overrides it.
# If this resource is blank, find the new Penni speak file by its name at
# runtime (useful when the audio was added locally but not pushed yet).
@export var default_voice_sound: AudioStream
# Penni's base pitch and volume belong to the DialogueVoice node, not
# duplicate exports here. Only the random pitch variation is on DialogueUI.
@export_range(0.0, 0.5, 0.01) var penni_pitch_variation: float = 0.08

# At scale 1, this reproduces the existing 1040x1600 room layout.
# Keep the portrait rectangle's proportions fixed; TextureRect's
# Keep Aspect Centered mode preserves each NPC texture's aspect ratio.
const ROOM_PORTRAIT_BASE_SIZE := Vector2(1040.0, 1600.0)

@export_group("Room Portrait Layout")
## Center of the room portrait, relative to the screen's bottom center.
## Positive X moves right and positive Y moves down.
@export var room_portrait_position: Vector2 = Vector2(0.0, -560.0)
## Uniform portrait size: 1.0 is the original room layout.
@export_range(0.1, 3.0, 0.05, "or_greater") var room_portrait_scale: float = 1.0

@onready var _box: PanelContainer = %Box
@onready var _player_portrait: TextureRect = %PlayerPortrait
@onready var _npc_portrait: TextureRect = %NPCPortrait
@onready var _name_label: Label = %NameLabel
@onready var _text_label: RichTextLabel = %TextLabel
@onready var _choice_list: VBoxContainer = %ChoiceList
@onready var _continue_hint: Label = %ContinueHint
# Scene-authored sound settings are always read from DialogueVoice.
# The second player receives per-letter pitch variation and NPC overrides;
# the editor-authored DialogueVoice node is never overwritten by playback.
@onready var _voice: AudioStreamPlayer = $DialogueVoice
@onready var _voice_playback: AudioStreamPlayer = $VoicePlayback

var _npc: NPCData = null
var _portrait_npc: NPCData = null # Current visible speaker, not relationship owner.
var _opened_frame := -1
var _illustration_mode := false
var _room_mode := false
var _underwater_mode := false
var _land_layer: int = 10
var _npc_land_offsets: Vector4
var _npc_land_anchors: Vector4
var _player_land_offsets: Vector4
var _displayed_line: DialogueLineData
var _typewriting: bool = false
var _type_elapsed: float = 0.0
var _type_total: int = 0
var _spoken_text: String = ""
var _current_voice_npc: NPCData
var _current_line_player: bool = false

# The exact same dialogue box, choice buttons, and conversation manager are
# used on land and underwater. Only the art and portrait framing change.
# Keep DialogueManager, text, choices and speaker styling unchanged.
# Room view only hides Penni's portrait and reframes the existing NPC portrait.
func set_room_mode(enabled: bool) -> void:
	_room_mode = enabled
	if not is_node_ready():
		return
	if enabled:
		_player_portrait.hide()
		_npc_portrait.anchor_left = 0.5
		_npc_portrait.anchor_right = 0.5
		_npc_portrait.anchor_top = 1.0
		_npc_portrait.anchor_bottom = 1.0
		_apply_room_portrait_layout()
		_npc_portrait.flip_h = false
	else:
		_npc_portrait.anchor_left = _npc_land_anchors.x
		_npc_portrait.anchor_top = _npc_land_anchors.y
		_npc_portrait.anchor_right = _npc_land_anchors.z
		_npc_portrait.anchor_bottom = _npc_land_anchors.w
		_restore_portrait_offsets(_npc_portrait, _npc_land_offsets)
		_player_portrait.visible = not _illustration_mode
	_apply_npc_portrait_presentation()
	if DialogueManager.is_active:
		_refresh()


# Convert the two editor controls into the existing rectangle offsets.
# Changing position moves the image; changing scale changes both dimensions
# equally, without stretching it or affecting normal outdoor dialogue.
func _apply_room_portrait_layout() -> void:
	var half_size: Vector2 = ROOM_PORTRAIT_BASE_SIZE * maxf(room_portrait_scale, 0.1) * 0.5
	_restore_portrait_offsets(_npc_portrait, Vector4(
		room_portrait_position.x - half_size.x,
		room_portrait_position.y - half_size.y,
		room_portrait_position.x + half_size.x,
		room_portrait_position.y + half_size.y
	))


func set_underwater_mode(enabled: bool) -> void:
	_underwater_mode = enabled
	if not is_node_ready():
		return
	# Dialogue UI stays identical above and below water; only the NPC's
	# portrait texture switches to that character's fish form underwater.
	layer = 40 if enabled else _land_layer
	_npc_portrait.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST if enabled
		else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	)
	# Underwater fish portraits sit to Penni's right. Flip only their fish
	# form so they're looking toward her; human portraits stay unchanged.
	var shown: NPCData = _portrait_npc if _portrait_npc != null else _npc
	_npc_portrait.flip_h = enabled and shown != null and shown.underwater_sprite != null
	# Keep Penni's real portrait, original placement and filtering everywhere.
	_restore_portrait_offsets(_player_portrait, _player_land_offsets)
	if not _room_mode:
		_restore_portrait_offsets(_npc_portrait, _npc_land_offsets)
	_apply_npc_portrait_presentation()
	if DialogueManager.is_active and visible:
		_refresh()


# Every NPC uses the SAME dialogue box. A resource optionally changes only
# the fish-form illustration's scale/tilt/offset, never its dialogue behavior.
# Restore original offsets each time so shifts cannot accumulate by line.
func _apply_npc_portrait_presentation() -> void:
	if not is_node_ready():
		return
	_npc_portrait.scale = Vector2.ONE
	_npc_portrait.rotation_degrees = 0.0
	if not _room_mode:
		_restore_portrait_offsets(_npc_portrait, _npc_land_offsets)
	_npc_portrait.pivot_offset = _npc_portrait.size * 0.5
	var shown: NPCData = _portrait_npc if _portrait_npc != null else _npc
	if _room_mode or not _underwater_mode or shown == null or shown.sea_visuals == null:
		return
	var visuals: SeaCharacterVisuals = shown.sea_visuals
	_npc_portrait.scale = Vector2.ONE * visuals.portrait_scale
	_npc_portrait.rotation_degrees = visuals.portrait_angle_degrees
	_npc_portrait.position += visuals.portrait_offset


func _restore_portrait_offsets(view: TextureRect, values: Vector4) -> void:
	view.offset_left = values.x
	view.offset_top = values.y
	view.offset_right = values.z
	view.offset_bottom = values.w


# Illustration scenes reuse the dialogue box, but suppress both portraits.
func set_illustration_mode(enabled: bool) -> void:
	_illustration_mode = enabled
	if is_node_ready():
		_player_portrait.visible = not enabled and not _room_mode
		_npc_portrait.visible = not enabled


func _ready() -> void:
	_find_default_voice()
	# DialogueVoice holds Penni's real editor-authored pitch, volume and bus.
	# VoicePlayback receives the actual per-letter sound so those properties
	# never get overwritten, even while the game is running.
	_text_label.bbcode_enabled = true
	_text_label.install_effect(LETTER_POP_EFFECT.new())
	_land_layer = layer
	_player_land_offsets = Vector4(
		_player_portrait.offset_left, _player_portrait.offset_top,
		_player_portrait.offset_right, _player_portrait.offset_bottom
	)
	_npc_land_offsets = Vector4(
		_npc_portrait.offset_left, _npc_portrait.offset_top,
		_npc_portrait.offset_right, _npc_portrait.offset_bottom
	)
	_npc_land_anchors = Vector4(
		_npc_portrait.anchor_left, _npc_portrait.anchor_top,
		_npc_portrait.anchor_right, _npc_portrait.anchor_bottom
	)
	hide()
	add_to_group(&"modal_ui")
	DialogueManager.dialogue_requested.connect(start)
	DialogueManager.conversation_finished.connect(_on_manager_conversation_finished)
	_box.gui_input.connect(_on_box_gui_input)


func _on_manager_conversation_finished(npc: NPCData) -> void:
	# Close synchronously so another conversation can start on the next
	# interaction, including when the diver talks to Silas repeatedly.
	if visible and _npc == npc:
		_close()


func _process(delta: float) -> void:
	# Close if the conversation was ended from somewhere else.
	if visible and not DialogueManager.is_active:
		_close()
		return
	if visible and _typewriting:
		_type_elapsed += delta
		var previous_count: int = maxi(_text_label.visible_characters, 0)
		var next_count: int = mini(
			int(_type_elapsed * maxf(characters_per_second, 1.0)), _type_total
		)
		_text_label.visible_characters = next_count
		for index in range(previous_count, next_count):
			_play_letter_sound(index)
		if next_count >= _type_total:
			_finish_typing()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if (
		event.is_action_pressed(ADVANCE_ACTION)
		or event.is_action_pressed("ui_accept")
	):
		get_viewport().set_input_as_handled()
		_advance()


# Start a conversation and open the UI.
# Returns false if the NPC has nothing to say, leaving the UI closed.
func start(npc: NPCData) -> bool:
	if visible or npc == null or DialogueManager.is_active:
		return false

	DialogueManager.start_conversation(npc)

	if not DialogueManager.is_active:
		return false

	_npc = npc
	_portrait_npc = npc
	_displayed_line = null
	_typewriting = false
	_opened_frame = Engine.get_process_frames()
	show()
	# Keep the world running while dialogue captures gameplay input.
	_refresh()
	return true


func _advance() -> void:
	# Ignore the same key press that opened the dialogue.
	if Engine.get_process_frames() == _opened_frame:
		return

	if _typewriting:
		# A press during typing reveals the whole line; the next press
		# advances DialogueManager, preserving one action per dialogue beat.
		_finish_typing()
		return

	if DialogueManager.is_awaiting_choice():
		return

	DialogueManager.advance()
	_refresh()


func _select_choice(index: int) -> void:
	DialogueManager.select_choice(index)
	_refresh()


# Redraw from DialogueManager's current state.
func _refresh() -> void:
	if not DialogueManager.is_active:
		_close()
		return

	# While choices are shown there is no current line,
	# so the last line stays on screen above them.
	var line = DialogueManager.get_current_line()

	if line != null:
		_show_line(line)

	_clear_choices()

	var awaiting_choice = DialogueManager.is_awaiting_choice()
	if awaiting_choice:
		_finish_typing()
	_choice_list.visible = awaiting_choice
	_continue_hint.visible = not awaiting_choice and not _typewriting

	if awaiting_choice:
		_show_choices()
	else:
		_continue_hint.text = "[%s] Continue" % (
			InteractPrompt.get_action_key_text(ADVANCE_ACTION)
		)
		_release_focus()


func _show_line(line: DialogueLineData) -> void:
	var is_player := line.speaker == DialogueLineData.Speaker.PLAYER
	if not is_player:
		_portrait_npc = DialogueManager.get_speaker_npc(line)
	elif _portrait_npc == null:
		_portrait_npc = _npc

	_name_label.text = PLAYER_NAME if is_player else DialogueManager.get_current_speaker_name()
	_name_label.add_theme_color_override(
		"font_color",
		PLAYER_NAME_COLOR if is_player else NPC_NAME_COLOR
	)
	_player_portrait.texture = player_portrait
	_npc_portrait.texture = _get_portrait(line)
	# A Penni-only reaction, or a prompt from an object (the dock), has no
	# second character, so no NPC portrait (not even the placeholder one).
	_npc_portrait.visible = not _illustration_mode and not (_npc != null and _npc.npc_id in NO_PORTRAIT_NPCS)
	_player_portrait.visible = not _illustration_mode and not _room_mode
	_npc_portrait.flip_h = _underwater_mode and _portrait_npc != null and _portrait_npc.underwater_sprite != null
	_apply_npc_portrait_presentation()

	# Light up whoever is speaking; dim the listener.
	_player_portrait.modulate = (
		SPEAKING_MODULATE if is_player else LISTENING_MODULATE
	)
	_npc_portrait.modulate = (
		LISTENING_MODULATE if is_player else SPEAKING_MODULATE
	)
	if line != _displayed_line:
		_displayed_line = line
		_current_line_player = is_player
		_current_voice_npc = null if is_player else _portrait_npc
		_begin_typing(line.text)


# Keep the complete line in a RichTextLabel, then reveal its shaped
# characters without reflowing or replacing text every frame.
func _begin_typing(value: String) -> void:
	_spoken_text = value
	_type_elapsed = 0.0
	var safe_text: String = value.replace("[", "[lb]")
	_text_label.text = ("[letterpop speed=%.2f duration=%.2f scale=%.2f jitter=%.2f]%s[/letterpop]" % [
		characters_per_second, letter_bounce_seconds, letter_scale_boost,
		letter_jitter_pixels, safe_text
	]) if typewriter_enabled else value
	_type_total = _text_label.get_total_character_count()
	_typewriting = typewriter_enabled and _type_total > 0
	_text_label.visible_characters = 0 if _typewriting else -1


func _finish_typing() -> void:
	_typewriting = false
	_text_label.visible_characters = -1
	_continue_hint.visible = not DialogueManager.is_awaiting_choice()


# Letters and digits get voice cues; punctuation, spaces and newlines stay silent.
func _play_letter_sound(index: int) -> void:
	if index >= _spoken_text.length():
		return
	var letter: String = _spoken_text.substr(index, 1)
	if letter.to_lower() == letter.to_upper() and not letter.is_valid_int():
		return
	var sound: AudioStream = default_voice_sound
	# Read Penni's actual Pitch Scale from the scene's DialogueVoice node
	# each time, so Inspector changes are effective without restarting.
	var base_pitch: float = _voice.pitch_scale
	var variance: float = penni_pitch_variation
	if not _current_line_player and _current_voice_npc != null:
		if _current_voice_npc.dialogue_voice_sound != null:
			sound = _current_voice_npc.dialogue_voice_sound
		base_pitch = _current_voice_npc.voice_pitch_scale
		variance = _current_voice_npc.voice_pitch_variation
	if sound == null:
		return
	# Copy, never mutate, the original DialogueVoice's loudness and bus.
	# Only the dedicated playback node receives randomized or NPC pitch.
	_voice_playback.volume_db = _voice.volume_db
	_voice_playback.bus = _voice.bus
	_voice_playback.max_polyphony = _voice.max_polyphony
	if _voice_playback.stream != sound:
		_voice_playback.stream = sound
	_voice_playback.pitch_scale = maxf(0.1, base_pitch + randf_range(-variance, variance))
	_voice_playback.play()


# When a new local file named Penni Speak is available, use it for every
# character automatically, with character-specific pitch in NPCData.
func _find_default_voice() -> void:
	if default_voice_sound != null:
		return
	for folder in ["res://sounds/sfx", "res://sounds"]:
		for file_name in DirAccess.get_files_at(folder):
			var lowercase: String = file_name.to_lower()
			if not lowercase.contains("penni") or not (
					lowercase.contains("speak") or lowercase.contains("voice")):
				continue
			if not (lowercase.ends_with(".wav") or lowercase.ends_with(".mp3")
					or lowercase.ends_with(".ogg")):
				continue
			default_voice_sound = load(folder.path_join(file_name)) as AudioStream
			if default_voice_sound != null:
				return


func _show_choices() -> void:
	var choices = DialogueManager.get_choices()

	for i in range(choices.size()):
		if choices[i] == null:
			continue

		var button := Button.new()
		button.text = choices[i].text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if DialogueManager.is_choice_greyed(i):
			for color_name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
				button.add_theme_color_override(color_name, PICKED_CHOICE_COLOR)
		button.pressed.connect(_select_choice.bind(i))
		_choice_list.add_child(button)

	if _choice_list.get_child_count() > 0:
		_choice_list.get_child(0).grab_focus()


# Expressions are reserved for future portrait sets;
# every line uses the NPC's base portrait for now.
func _get_portrait(_line: DialogueLineData) -> Texture2D:
	var shown: NPCData = _portrait_npc if _portrait_npc != null else _npc
	if shown == null:
		return placeholder_portrait
	if _underwater_mode:
		return shown.underwater_sprite if shown.underwater_sprite != null else placeholder_portrait
	if shown.portrait != null:
		return shown.portrait
	return placeholder_portrait


func _clear_choices() -> void:
	for button in _choice_list.get_children():
		_choice_list.remove_child(button)
		button.queue_free()


func _release_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()

	if focused != null:
		focused.release_focus()


func _close() -> void:
	if not visible:
		return

	hide()
	_clear_choices()
	_typewriting = false
	_displayed_line = null
	_spoken_text = ""
	_current_voice_npc = null
	_text_label.visible_characters = -1
	# Gameplay input resumes automatically once the dialogue closes.

	var npc := _npc
	_npc = null
	_portrait_npc = null
	conversation_ended.emit(npc)


func _on_box_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton

	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_advance()
