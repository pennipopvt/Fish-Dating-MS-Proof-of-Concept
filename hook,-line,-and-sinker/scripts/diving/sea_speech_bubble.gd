extends CanvasLayer
class_name SeaSpeechBubble

# A single speech bubble tracks its speaker, clamping to the screen edge
# while offscreen. The separate tail points to the same world position.
@export var bubble_texture: Texture2D:
	set(value):
		bubble_texture = value
		if is_node_ready():
			_apply_frame()

@export var tail_texture: Texture2D:
	set(value):
		tail_texture = value
		if is_node_ready():
			_apply_frame()

@export_range(1, 48, 1) var patch_margin: int = 6:
	set(value):
		patch_margin = value
		if is_node_ready():
			_apply_frame()

@export var bubble_offset: Vector2 = Vector2(36.0, -118.0)
@export_range(0.0, 64.0, 1.0) var screen_margin: float = 12.0

@onready var _call: Control = $Call
@onready var _frame: NinePatchRect = $Call/Frame
@onready var _fallback: Panel = $Call/Fallback
@onready var _text: Label = $Call/Message
@onready var _tail: TextureRect = $Call/Tail
@onready var _hint: Label = $Hint

var _call_serial: int = 0
var _speaker: Node2D
var _game_display: SubViewportContainer


func _ready() -> void:
	add_to_group("sea_speech_bubble")
	_call.hide()
	_tail.hide()
	_hint.hide()
	_apply_frame()
	set_process(false)


func _apply_frame() -> void:
	_frame.texture = bubble_texture
	_frame.patch_margin_left = patch_margin
	_frame.patch_margin_top = patch_margin
	_frame.patch_margin_right = patch_margin
	_frame.patch_margin_bottom = patch_margin
	_frame.visible = bubble_texture != null
	_fallback.visible = bubble_texture == null
	_tail.texture = tail_texture
	_tail.visible = _call.visible and _speaker != null and tail_texture != null


# A fallback for messages without a world speaker.
func show_call(message: String, from_right: bool = true, seconds: float = 4.0) -> void:
	_call_serial += 1
	var serial: int = _call_serial
	_stop_tracking()
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var call_width: float = _call.size.x
	_call.position = Vector2(
		maxf(screen_margin, view_size.x - call_width - screen_margin) if from_right else screen_margin,
		maxf(screen_margin, view_size.y * 0.24)
	)
	_text.text = message
	_call.show()
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if serial == _call_serial and is_instance_valid(_call):
			hide_call()


# 0 seconds means persist until hide_call(), as for Silas's first cry.
func show_attached_call(
		message: String, speaker: Node2D,
		display: SubViewportContainer, seconds: float = 0.0) -> void:
	if not is_instance_valid(speaker) or not is_instance_valid(display):
		show_call(message, false, seconds)
		return
	_call_serial += 1
	var serial: int = _call_serial
	_speaker = speaker
	_game_display = display
	_text.text = message
	_call.show()
	_tail.visible = tail_texture != null
	set_process(true)
	_update_attached_position()
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if serial == _call_serial and is_instance_valid(_call):
			hide_call()


func _process(_delta: float) -> void:
	_update_attached_position()


func _update_attached_position() -> void:
	if not is_instance_valid(_speaker) or not is_instance_valid(_game_display):
		hide_call()
		return
	# The speaker is in the 320x180 game SubViewport, while this CanvasLayer
	# is in Main's UI viewport. Map through the SubViewportContainer rect so
	# camera movement and window resizing both work correctly.
	var canvas_point: Vector2 = (
		_speaker.get_global_transform_with_canvas() * Vector2(0.0, -10.0)
	)
	var game_size: Vector2 = Vector2(_speaker.get_viewport().get_visible_rect().size)
	if game_size.x <= 0.0 or game_size.y <= 0.0:
		return
	var display_rect: Rect2 = _game_display.get_global_rect()
	var target_on_screen: Vector2 = display_rect.position + (
		canvas_point * (display_rect.size / game_size)
	)
	var desired: Vector2 = target_on_screen + bubble_offset
	var min_position: Vector2 = display_rect.position + Vector2.ONE * screen_margin
	var max_position: Vector2 = display_rect.end - _call.size - Vector2.ONE * screen_margin
	max_position.x = maxf(min_position.x, max_position.x)
	max_position.y = maxf(min_position.y, max_position.y)
	_call.position = Vector2(
		clampf(desired.x, min_position.x, max_position.x),
		clampf(desired.y, min_position.y, max_position.y)
	)
	_point_tail_toward(target_on_screen)


func _point_tail_toward(target_screen: Vector2) -> void:
	if tail_texture == null:
		return
	var center: Vector2 = _call.position + _call.size * 0.5
	var direction: Vector2 = target_screen - center
	if direction.length_squared() < 1.0:
		direction = Vector2(-1.0, 1.0)
	var half: Vector2 = _call.size * 0.5
	var x_factor: float = half.x / maxf(absf(direction.x), 0.001)
	var y_factor: float = half.y / maxf(absf(direction.y), 0.001)
	var point: Vector2 = half + direction * minf(x_factor, y_factor)
	# Keep the tail away from the bubble's corner pixels.
	if point.x < 1.0 or point.x > _call.size.x - 1.0:
		point.y = clampf(point.y, 16.0, _call.size.y - 16.0)
	else:
		point.x = clampf(point.x, 16.0, _call.size.x - 16.0)
	_tail.position = point - _tail.size * 0.5
	_tail.pivot_offset = _tail.size * 0.5
	# The user's tail image points down-left by default.
	_tail.rotation = direction.angle() - Vector2(-5.5, 11.0).angle()


func _stop_tracking() -> void:
	_speaker = null
	_game_display = null
	_tail.hide()
	set_process(false)


func hide_call() -> void:
	_call_serial += 1
	_stop_tracking()
	_call.hide()


func show_hint(message: String) -> void:
	_hint.text = message
	_hint.visible = not message.is_empty()


func hide_hint() -> void:
	_hint.hide()
