extends CanvasLayer
class_name SeaSpeechBubble

# Dialogue calls use their own nine-slice frame. Tutorial controls are
# a single transparent sprite, with no window, caption or background.
@export var bubble_texture: Texture2D:
	set(value):
		bubble_texture = value
		if is_node_ready():
			_apply_frame()

@export_range(1, 48, 1) var patch_margin: int = 12:
	set(value):
		patch_margin = value
		if is_node_ready():
			_apply_frame()

# Replace these textures in the SeaSpeechBubble Inspector later.
@export var movement_sprite: Texture2D = preload("res://sprites/ui/tutorial_wasd.svg")
@export var cast_sprite: Texture2D = preload("res://sprites/ui/tutorial_cast.svg")
@export var reel_sprite: Texture2D = preload("res://sprites/ui/tutorial_reel.svg")

@onready var _call: Control = $Call
@onready var _frame: NinePatchRect = $Call/Frame
@onready var _fallback: Panel = $Call/Fallback
@onready var _text: Label = $Call/Message
@onready var _arrow: Label = $Call/Direction
@onready var _hint: Label = $Hint
@onready var _input_sprite: TextureRect = get_node_or_null("InputSprite") as TextureRect

var current_action: StringName = &""
var _input_tween: Tween
var _call_serial: int = 0


func _ready() -> void:
	add_to_group("sea_speech_bubble")
	_call.hide()
	_hint.hide()
	if _input_sprite != null:
		_input_sprite.hide()
	_apply_frame()


func _apply_frame() -> void:
	_frame.texture = bubble_texture
	_frame.patch_margin_left = patch_margin
	_frame.patch_margin_top = patch_margin
	_frame.patch_margin_right = patch_margin
	_frame.patch_margin_bottom = patch_margin
	_frame.visible = bubble_texture != null
	_fallback.visible = bubble_texture == null


func show_call(message: String, from_right: bool = true, seconds: float = 4.0) -> void:
	_call_serial += 1
	var serial: int = _call_serial
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var call_width: float = 340.0
	_call.position = Vector2(
		maxf(20.0, view_size.x - call_width - 18.0) if from_right else 18.0,
		maxf(28.0, view_size.y * 0.24)
	)
	_text.text = message
	_arrow.text = ">" if from_right else "<"
	_call.show()
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if serial == _call_serial and is_instance_valid(_call):
			_call.hide()


func hide_call() -> void:
	_call_serial += 1
	_call.hide()


func show_hint(message: String) -> void:
	hide_input_prompt()
	_hint.text = message
	_hint.visible = not message.is_empty()


func hide_hint() -> void:
	_hint.hide()


func show_input_prompt(action: StringName) -> void:
	_hint.hide()
	if _input_sprite == null:
		push_warning("SeaSpeechBubble is missing its InputSprite TextureRect.")
		return
	var graphic: Texture2D
	match action:
		&"move": graphic = movement_sprite
		&"cast": graphic = cast_sprite
		&"reel": graphic = reel_sprite
		_:
			hide_input_prompt()
			return
	if graphic == null:
		hide_input_prompt()
		return
	if current_action == action and _input_sprite.visible:
		return
	current_action = action
	_input_sprite.texture = graphic
	if _input_tween != null and _input_tween.is_running():
		_input_tween.kill()
	_input_sprite.modulate.a = 0.0
	_input_sprite.show()
	_input_tween = create_tween()
	_input_tween.tween_property(_input_sprite, "modulate:a", 1.0, 0.3)


func hide_input_prompt() -> void:
	current_action = &""
	if _input_sprite == null or not _input_sprite.visible:
		return
	if _input_tween != null and _input_tween.is_running():
		_input_tween.kill()
	_input_tween = create_tween()
	_input_tween.tween_property(_input_sprite, "modulate:a", 0.0, 0.16)
	_input_tween.tween_callback(_input_sprite.hide)
