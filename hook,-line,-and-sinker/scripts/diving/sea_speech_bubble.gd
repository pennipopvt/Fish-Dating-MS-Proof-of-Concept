extends CanvasLayer
class_name SeaSpeechBubble

# Runs in the SAME 320x180 SubViewport as the sea. The bubble is screen-
# fixed only while Silas is offscreen; once visible it stays beside him.
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

@export_range(1, 16, 1) var patch_margin: int = 6:
	set(value):
		patch_margin = value
		if is_node_ready():
			_apply_frame()

# Native game pixels, not outer-window UI pixels.
@export var bubble_offset: Vector2 = Vector2(11.0, -42.0)
@export_range(2.0, 24.0, 1.0) var screen_margin: float = 12.0

@onready var _call: Control = $Call
@onready var _frame: NinePatchRect = $Call/Frame
@onready var _fallback: Panel = $Call/Fallback
@onready var _text: Label = $Call/Message
@onready var _tail: TextureRect = $Call/Tail
@onready var _hint: Label = $Hint

var _call_serial: int = 0
var _speaker: Node2D


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
	_tail.visible = _call.visible and is_instance_valid(_speaker) and tail_texture != null


# Ordinary timed bubble, for callers with no scene speaker.
func show_call(message: String, from_right: bool = true, seconds: float = 4.0) -> void:
	_call_serial += 1
	var serial: int = _call_serial
	_stop_tracking()
	var size: Vector2 = get_viewport().get_visible_rect().size
	_call.position = Vector2(
		size.x - _call.size.x - screen_margin if from_right else screen_margin,
		maxf(screen_margin, roundf(size.y * 0.24))
	)
	_text.text = message
	_call.show()
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if serial == _call_serial and is_instance_valid(_call):
			hide_call()


# 0 seconds keeps Silas's first cry onscreen until he is interacted with.
func show_attached_call(message: String, speaker: Node2D, seconds: float = 0.0) -> void:
	if not is_instance_valid(speaker):
		show_call(message, false, seconds)
		return
	_call_serial += 1
	var serial: int = _call_serial
	_speaker = speaker
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
	if not is_instance_valid(_speaker):
		hide_call()
		return
	# Both Silas and this CanvasLayer belong to the game SubViewport.
	# Godot's canvas transform already includes the active player camera.
	var target_screen: Vector2 = (
		_speaker.get_global_transform_with_canvas() * Vector2(0.0, -10.0)
	)
	var game_size: Vector2 = get_viewport().get_visible_rect().size
	var desired: Vector2 = target_screen + bubble_offset
	var low: Vector2 = Vector2.ONE * screen_margin
	var high: Vector2 = game_size - _call.size - low
	high.x = maxf(low.x, high.x)
	high.y = maxf(low.y, high.y)
	_call.position = Vector2(
		roundf(clampf(desired.x, low.x, high.x)),
		roundf(clampf(desired.y, low.y, high.y))
	)
	_point_tail_toward(target_screen)


func _point_tail_toward(target_screen: Vector2) -> void:
	if tail_texture == null:
		return
	var half: Vector2 = _call.size * 0.5
	var direction: Vector2 = target_screen - (_call.position + half)
	if direction.length_squared() < 0.01:
		direction = Vector2(-1.0, 1.0)
	var x_factor: float = half.x / maxf(absf(direction.x), 0.001)
	var y_factor: float = half.y / maxf(absf(direction.y), 0.001)
	var edge: Vector2 = half + direction * minf(x_factor, y_factor)
	# Connect along one side, not the sharp, rounded 9-slice corners.
	if x_factor < y_factor:
		edge.x = _call.size.x if direction.x > 0.0 else 0.0
		edge.y = clampf(edge.y, 8.0, _call.size.y - 8.0)
	else:
		edge.y = _call.size.y if direction.y > 0.0 else 0.0
		edge.x = clampf(edge.x, 8.0, _call.size.x - 8.0)

	# The user's 12x12 tail has its FLAT BASE across the top edge and its
	# tip pointing down-left. Align the base with the OUTSIDE of the box;
	# the frame draws over a 1px seam so the tail appears attached.
	var pivot: Vector2 = _tail.size * 0.5
	var base_center: Vector2 = Vector2(_tail.size.x * 0.5, 0.0)
	_tail.pivot_offset = pivot
	_tail.rotation = direction.angle() - Vector2(-5.5, 5.5).angle()
	var base_from_pivot: Vector2 = (base_center - pivot).rotated(_tail.rotation)
	var attachment: Vector2 = edge - direction.normalized()
	_tail.position = (attachment - pivot - base_from_pivot).round()


func _stop_tracking() -> void:
	_speaker = null
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
