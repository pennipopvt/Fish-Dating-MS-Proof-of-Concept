extends CanvasLayer
class_name SeaSpeechBubble

# Keep this one bubble on Main's proven UI canvas. Silas lives in the
# 320x180 SubViewport: only his point is mapped into Main coordinates.
# Never alter CanvasLayer.scale/offset or instance another bubble.
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

@export var bubble_offset: Vector2 = Vector2(44.0, -115.0)
@export_range(8.0, 48.0, 1.0) var screen_margin: float = 16.0

@onready var _call: Control = $Call
@onready var _frame: NinePatchRect = $Call/Frame
@onready var _fallback: Panel = $Call/Fallback
@onready var _text: Label = $Call/Message
@onready var _tail: TextureRect = $Call/Tail
@onready var _hint: Label = $Hint

var _call_serial: int = 0
var _speaker: Node2D
var _display: SubViewportContainer


func _ready() -> void:
	add_to_group("sea_speech_bubble")
	_display = get_parent().get_node_or_null("SubViewportContainer") as SubViewportContainer
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


func is_call_shown() -> bool:
	return is_node_ready() and visible and _call.is_visible_in_tree() \
		and (_frame.visible or _fallback.visible)


# This is the same draw path as the last screenshot in which "Help me!"
# appeared. It also works if the sea actor is temporarily unavailable.
func show_call(message: String, from_right: bool = true, seconds: float = 4.0) -> void:
	_call_serial += 1
	var serial: int = _call_serial
	_stop_tracking()
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var width: float = _call.size.x
	_call.position = Vector2(
		maxf(16.0, view_size.x - width - screen_margin) if from_right else screen_margin,
		maxf(20.0, view_size.y * 0.24)
	)
	_text.text = message
	show()
	_call.show()
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if serial == _call_serial and is_instance_valid(_call):
			hide_call()


func show_attached_call(message: String, speaker: Node2D, seconds: float = 0.0) -> void:
	if not is_instance_valid(speaker) or not is_instance_valid(_display):
		show_call(message, false, seconds)
		return
	_call_serial += 1
	var serial: int = _call_serial
	_speaker = speaker
	_text.text = message
	show()
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
	if not is_instance_valid(_speaker) or not is_instance_valid(_display):
		push_warning("[SEA BUBBLE] Hiding attached call: Silas or display reference invalid")
		hide_call()
		return
	var game_view: Vector2 = Vector2(_speaker.get_viewport().get_visible_rect().size)
	if game_view.x <= 0.0 or game_view.y <= 0.0:
		return
	var view_rect: Rect2 = _display.get_global_rect()
	var point_in_game: Vector2 = _speaker.get_global_transform_with_canvas() * Vector2(0.0, -10.0)
	var target: Vector2 = view_rect.position + point_in_game * (view_rect.size / game_view)
	var wanted: Vector2 = target + bubble_offset
	var low: Vector2 = view_rect.position + Vector2.ONE * screen_margin
	var high: Vector2 = view_rect.end - _call.size - Vector2.ONE * screen_margin
	high.x = maxf(low.x, high.x)
	high.y = maxf(low.y, high.y)
	_call.position = Vector2(
		roundf(clampf(wanted.x, low.x, high.x)),
		roundf(clampf(wanted.y, low.y, high.y))
	)
	_point_tail_at(target)


func _point_tail_at(target: Vector2) -> void:
	if tail_texture == null:
		return
	var half: Vector2 = _call.size * 0.5
	var direction: Vector2 = target - (_call.position + half)
	if direction.length_squared() < 0.001:
		direction = Vector2(-1.0, 1.0)
	var x_hit: float = half.x / maxf(absf(direction.x), 0.001)
	var y_hit: float = half.y / maxf(absf(direction.y), 0.001)
	var edge: Vector2 = half + direction * minf(x_hit, y_hit)
	if x_hit < y_hit:
		edge.x = _call.size.x if direction.x > 0.0 else 0.0
		edge.y = clampf(edge.y, 12.0, _call.size.y - 12.0)
	else:
		edge.y = _call.size.y if direction.y > 0.0 else 0.0
		edge.x = clampf(edge.x, 12.0, _call.size.x - 12.0)
	var pivot: Vector2 = _tail.size * 0.5
	var base_center: Vector2 = Vector2(_tail.size.x * 0.5, 0.0)
	_tail.pivot_offset = pivot
	_tail.rotation = direction.angle() - Vector2(-5.5, 5.5).angle()
	var rotated_base: Vector2 = (base_center - pivot).rotated(_tail.rotation)
	_tail.position = (edge - direction.normalized() - pivot - rotated_base).round()


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
