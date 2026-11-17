class_name DialogueUI
extends CanvasLayer

# Player-facing dialogue box. Conversation state lives in DialogueManager;
# this script only displays it and forwards the player's input.

signal conversation_ended(npc: NPCData)

const PLAYER_NAME := "Penni"
const NPC_NAME_COLOR := Color(1.0, 0.85, 0.5)
const PLAYER_NAME_COLOR := Color(0.6, 0.85, 1.0)
const SPEAKING_MODULATE := Color.WHITE
const LISTENING_MODULATE := Color(0.5, 0.5, 0.55)
const ADVANCE_ACTION := &"Interact"
# Choices picked before (no more affection from them): grey, still pickable.
const PICKED_CHOICE_COLOR := Color(0.55, 0.55, 0.6)
const SILAS_FISH_SPRITE: Texture2D = preload("res://sprites/fish/silas_eel.png")
const PENNI_IDLE_SHEET: Texture2D = preload("res://sprites/characters/penni/penni_idle.png")

# Shown when an NPC has no portrait assigned yet.
@export var placeholder_portrait: Texture2D
@export var player_portrait: Texture2D

@onready var _box: PanelContainer = %Box
@onready var _player_portrait: TextureRect = %PlayerPortrait
@onready var _npc_portrait: TextureRect = %NPCPortrait
@onready var _name_label: Label = %NameLabel
@onready var _text_label: Label = %TextLabel
@onready var _choice_list: VBoxContainer = %ChoiceList
@onready var _continue_hint: Label = %ContinueHint

var _npc: NPCData = null
var _opened_frame := -1
var _illustration_mode := false
var _underwater_mode := false
var _land_layer: int = 10
var _npc_land_offsets: Vector4
var _player_land_offsets: Vector4
var _swimming_penni_sprite: AtlasTexture

# The exact same dialogue box, choice buttons, and conversation manager are
# used on land and underwater. Only the art and portrait framing change.
func set_underwater_mode(enabled: bool) -> void:
	_underwater_mode = enabled
	if not is_node_ready():
		return
	layer = 40 if enabled else _land_layer
	_player_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if enabled else CanvasItem.TEXTURE_FILTER_INHERIT
	_npc_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if enabled else CanvasItem.TEXTURE_FILTER_INHERIT
	if enabled:
		# Large, clear pixel sprites instead of oversized portrait paintings.
		_player_portrait.offset_left = 70.0
		_player_portrait.offset_top = -700.0
		_player_portrait.offset_right = 670.0
		_player_portrait.offset_bottom = -100.0
		_npc_portrait.offset_left = -730.0
		_npc_portrait.offset_top = -720.0
		_npc_portrait.offset_right = -110.0
		_npc_portrait.offset_bottom = -100.0
	else:
		_restore_portrait_offsets(_player_portrait, _player_land_offsets)
		_restore_portrait_offsets(_npc_portrait, _npc_land_offsets)
	if DialogueManager.is_active and visible:
		_refresh()


func _restore_portrait_offsets(view: TextureRect, values: Vector4) -> void:
	view.offset_left = values.x
	view.offset_top = values.y
	view.offset_right = values.z
	view.offset_bottom = values.w


# Illustration scenes reuse the dialogue box, but suppress both portraits.
func set_illustration_mode(enabled: bool) -> void:
	_illustration_mode = enabled
	if is_node_ready():
		_player_portrait.visible = not enabled
		_npc_portrait.visible = not enabled


func _ready() -> void:
	_land_layer = layer
	_player_land_offsets = Vector4(
		_player_portrait.offset_left, _player_portrait.offset_top,
		_player_portrait.offset_right, _player_portrait.offset_bottom
	)
	_npc_land_offsets = Vector4(
		_npc_portrait.offset_left, _npc_portrait.offset_top,
		_npc_portrait.offset_right, _npc_portrait.offset_bottom
	)
	_swimming_penni_sprite = AtlasTexture.new()
	_swimming_penni_sprite.atlas = PENNI_IDLE_SHEET
	_swimming_penni_sprite.region = Rect2(0, 0, 32, 32)
	hide()
	add_to_group(&"modal_ui")
	DialogueManager.dialogue_requested.connect(start)
	_box.gui_input.connect(_on_box_gui_input)


func _process(_delta: float) -> void:
	# Close if the conversation was ended from somewhere else.
	if visible and not DialogueManager.is_active:
		_close()


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
	_opened_frame = Engine.get_process_frames()
	show()
	# Keep the world running while dialogue captures gameplay input.
	_refresh()
	return true


func _advance() -> void:
	# Ignore the same key press that opened the dialogue.
	if Engine.get_process_frames() == _opened_frame:
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
	_choice_list.visible = awaiting_choice
	_continue_hint.visible = not awaiting_choice

	if awaiting_choice:
		_show_choices()
	else:
		_continue_hint.text = "[%s] Continue" % (
			InteractPrompt.get_action_key_text(ADVANCE_ACTION)
		)
		_release_focus()


func _show_line(line: DialogueLineData) -> void:
	var is_player := line.speaker == DialogueLineData.Speaker.PLAYER

	_name_label.text = PLAYER_NAME if is_player else DialogueManager.get_current_speaker_name()
	_name_label.add_theme_color_override(
		"font_color",
		PLAYER_NAME_COLOR if is_player else NPC_NAME_COLOR
	)
	_player_portrait.texture = _swimming_penni_sprite if _underwater_mode else player_portrait
	_npc_portrait.texture = _get_portrait(line)

	# Light up whoever is speaking; dim the listener.
	_player_portrait.modulate = (
		SPEAKING_MODULATE if is_player else LISTENING_MODULATE
	)
	_npc_portrait.modulate = (
		LISTENING_MODULATE if is_player else SPEAKING_MODULATE
	)
	_text_label.text = line.text


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
	if _underwater_mode:
		if _npc.npc_id == &"test_npc":
			return SILAS_FISH_SPRITE
		# Future underwater NPCs automatically use their fishing species art.
		for fish in FishingManager.possible_catches:
			if fish != null and fish.npc_data != null and fish.item_data != null:
				var character: NPCInteractable = null
				if fish.npc_data.can_instantiate():
					# PackedScene metadata can be resolved without spawning.
					var state: SceneState = fish.npc_data.get_state()
					for index in range(state.get_node_property_count(0)):
						if state.get_node_property_name(0, index) == &"npc":
							var npc_data: NPCData = state.get_node_property_value(0, index) as NPCData
							if npc_data != null and npc_data.npc_id == _npc.npc_id:
								return fish.item_data.sprite
	if _npc.portrait != null:
		return _npc.portrait

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
	# Gameplay input resumes automatically once the dialogue closes.

	var npc := _npc
	_npc = null
	conversation_ended.emit(npc)


func _on_box_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton

	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_advance()
