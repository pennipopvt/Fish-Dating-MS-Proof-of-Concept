extends CanvasLayer
class_name SeaSpeechBubble

# Full-resolution screen-space bubble. Replace the Frame texture with your
# nine-slice PNG later; the fallback panel and text margins work without art.
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

@onready var _call: Control = $Call
@onready var _frame: NinePatchRect = $Call/Frame
@onready var _fallback: Panel = $Call/Fallback
@onready var _text: Label = $Call/Message
@onready var _arrow: Label = $Call/Direction
@onready var _hint: Label = $Hint

var _call_serial: int = 0


func _ready() -> void:
	add_to_group("sea_speech_bubble")
	_call.hide()
	_hint.hide()
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
		if serial == _call_serial:
			_call.hide()


func hide_call() -> void:
	_call_serial += 1
	_call.hide()


func show_hint(message: String) -> void:
	_hint.text = message
	_hint.visible = not message.is_empty()


func hide_hint() -> void:
	_hint.hide()
