extends CanvasLayer
class_name SeaSpeechBubble

# One bubble, rendered by Main (never moved into the game SubViewport).
# All local UI coordinates are in NATIVE 320x180 pixels; the CanvasLayer
# maps them to Main's SubViewportContainer, nearest-filtered for pixel art.
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
@export_range(9, 18, 1) var font_pixels: int = 11
@export var bubble_offset: Vector2 = Vector2(25.0, -51.0)
@export_range(2.0, 24.0, 1.0) var screen_margin: float = 8.0
@export_range(0.04, 0.3, 0.01) var letter_seconds: float = 0.09
@export_range(0.5, 8.0, 0.1) var help_hold_seconds: float = 2.4
@export_range(0.1, 2.0, 0.1) var fade_seconds: float = 0.7
@export_range(0.2, 6.0, 0.1) var repeat_gap_seconds: float = 1.8

@onready var _call: Control = $Call
@onready var _frame: NinePatchRect = $Call/Frame
@onready var _fallback: Panel = $Call/Fallback
@onready var _text: Label = $Call/Message
@onready var _tail: TextureRect = $Call/Tail
@onready var _hint: Label = $Hint
@onready var _hint_frame: NinePatchRect = get_node_or_null("HintFrame") as NinePatchRect

var _display: SubViewportContainer
var _game_viewport: SubViewport
var _speaker: Node2D
var _message: String = ""
var _session_active: bool = false
var _repeating: bool = false
var _cycle_time: float = 0.0
var _hold_time: float = 0.0
var _origin: Vector2 = Vector2(10.0, 35.0)
var _last_state: StringName = &"idle"
var _call_serial: int = 0


func _ready() -> void:
	add_to_group("sea_speech_bubble")
	_display = get_parent().get_node_or_null("SubViewportContainer") as SubViewportContainer
	if _display != null:
		_game_viewport = _display.get_node_or_null("SubViewport") as SubViewport
	# The fallback created in Main at runtime uses the same child names.
	_text.add_theme_font_size_override("font_size", font_pixels)
	_text.add_theme_color_override("font_color", Color.BLACK)
	_text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_frame()
	_call.hide()
	_tail.hide()
	_hint.hide()
	if _hint_frame != null:
		_hint_frame.hide()
	_sync_game_scale()
	set_process(false)


func _apply_frame() -> void:
	_frame.texture = bubble_texture
	_frame.patch_margin_left = patch_margin
	_frame.patch_margin_top = patch_margin
	_frame.patch_margin_right = patch_margin
	_frame.patch_margin_bottom = patch_margin
	_frame.visible = bubble_texture != null
	_fallback.visible = bubble_texture == null
	# Never stretch the speaker marker: it is a 12x12 PNG drawn alongside
	# the 32x32 nine-slice, and both use 1 source pixel = 1 game pixel.
	# The runtime recovery used to inflate this 12px marker to 24px.
	_tail.texture = tail_texture
	if _hint_frame != null:
		_hint_frame.texture = bubble_texture
		_hint_frame.patch_margin_left = patch_margin
		_hint_frame.patch_margin_top = patch_margin
		_hint_frame.patch_margin_right = patch_margin
		_hint_frame.patch_margin_bottom = patch_margin
	_hint_frame_placeholder()
	_tail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tail.stretch_mode = TextureRect.STRETCH_KEEP
	_tail.scale = Vector2.ONE
	if tail_texture != null:
		_tail.size = Vector2(tail_texture.get_size())
		_tail.pivot_offset = _tail.size * 0.5


# Runtime fallback still draws readable black text if the nine-slice
# texture hasn't imported; never make the hint silently invisible.
func _hint_frame_placeholder() -> void:
	if _hint_frame != null:
		_hint_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _game_size() -> Vector2:
	if is_instance_valid(_game_viewport):
		return Vector2(_game_viewport.get_visible_rect().size)
	return Vector2(320.0, 180.0)


func _sync_game_scale() -> void:
	if not is_instance_valid(_display):
		return
	var size: Vector2 = _game_size()
	var rect: Rect2 = _display.get_global_rect()
	if size.x <= 0.0 or size.y <= 0.0 or rect.size.x <= 0.0:
		return
	scale = rect.size / size
	offset = rect.position


# "Shown" describes the actual visible portion of the cycle; "active"
# remains true during the intentional gap between repeated cries.
func is_call_shown() -> bool:
	return is_node_ready() and visible and _call.is_visible_in_tree() \
		and (_frame.visible or _fallback.visible)


func is_call_active() -> bool:
	return _session_active and is_instance_valid(_call)


func bubble_debug_state() -> String:
	return "%s chars=%d/%d repeat=%s size=%s scale=%s" % [
		String(_last_state), _text.visible_characters, _message.length(),
		str(_repeating), str(_call.size), str(scale)]


func show_call(message: String, from_right: bool = true, seconds: float = 4.0) -> void:
	_speaker = null
	_sync_game_scale()
	var game_size: Vector2 = _game_size()
	_origin = Vector2(game_size.x - 100.0 if from_right else 10.0, 34.0)
	# A zero-duration test call stays up until explicitly hidden.
	_begin_message(message, false, -1.0 if seconds <= 0.0 else seconds)


# Repeating, persistent cries when seconds is zero; a timed one-shot
# message for later companion advice when seconds is positive.
func show_attached_call(message: String, speaker: Node2D, seconds: float = 0.0) -> void:
	if not is_instance_valid(speaker):
		show_call(message, false, seconds)
		return
	_speaker = speaker
	_begin_message(message, seconds <= 0.0, help_hold_seconds if seconds <= 0.0 else seconds)


func _begin_message(message: String, repeat: bool, hold: float) -> void:
	_call_serial += 1
	_message = message
	_repeating = repeat
	_hold_time = hold
	_cycle_time = 0.0
	_session_active = true
	_last_state = &"reveal"
	_text.text = message
	_text.visible_characters = 0
	show()
	_call.show()
	_call.modulate.a = 1.0
	_tail.visible = tail_texture != null and is_instance_valid(_speaker)
	_update_animation(0.0)
	_update_position()
	set_process(true)


func _process(delta: float) -> void:
	if not _session_active:
		return
	_sync_game_scale()
	_cycle_time += delta
	_update_animation(_cycle_time)
	if _session_active and _call.visible:
		_update_position()


func _update_animation(elapsed: float) -> void:
	var reveal_duration: float = maxf(float(_message.length()) * letter_seconds, 0.1)
	var duration: float = reveal_duration + _hold_time + fade_seconds
	if _hold_time < 0.0:
		duration = INF
	var total_cycle: float = duration + repeat_gap_seconds
	if _repeating and elapsed >= total_cycle:
		_cycle_time = fmod(elapsed, total_cycle)
		elapsed = _cycle_time
	if not _repeating and elapsed >= duration and _hold_time >= 0.0:
		hide_call()
		return
	if _repeating and elapsed >= duration:
		_last_state = &"waiting"
		_call.hide()
		return
	_call.show()
	if elapsed < reveal_duration:
		_last_state = &"reveal"
		var shown: int = mini(int(floor(elapsed / letter_seconds)), _message.length())
		_text.visible_characters = shown
		_layout_for_characters(shown)
		_call.modulate.a = 1.0
	elif elapsed < reveal_duration + _hold_time or _hold_time < 0.0:
		_last_state = &"hold"
		_text.visible_characters = _message.length()
		_layout_for_characters(_message.length())
		_call.modulate.a = 1.0
	else:
		_last_state = &"fade"
		_text.visible_characters = _message.length()
		_layout_for_characters(_message.length())
		_call.modulate.a = clampf(
			1.0 - (elapsed - reveal_duration - _hold_time) / fade_seconds, 0.0, 1.0)


func _layout_for_characters(count: int) -> void:
	# Measure the currently revealed text, not the final string: this makes
	# the nine-slice frame physically grow with the typewriter animation.
	var shown: String = _message.substr(0, count)
	var font: Font = _text.get_theme_font("font")
	var font_size: int = _text.get_theme_font_size("font_size")
	var measured: float = float(count) * 6.0
	if font != null and not shown.is_empty():
		measured = font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width: float = clampf(18.0 + measured, 26.0, 112.0)
	var height: float = 30.0
	if 18.0 + measured > 112.0:
		height = 42.0
	_call.size = Vector2(ceilf(width), height)
	# Runtime recovery also creates Panel/NinePatch without anchors.
	_frame.size = _call.size
	_fallback.size = _call.size
	_text.position = Vector2(7.0, 4.0)
	_text.size = _call.size - Vector2(14.0, 8.0)


func _update_position() -> void:
	var target: Vector2 = Vector2.ZERO
	var tracked: bool = is_instance_valid(_speaker)
	if tracked:
		target = _speaker.get_global_transform_with_canvas() * Vector2(0.0, -10.0)
	else:
		target = _origin
	var desired: Vector2 = target + bubble_offset if tracked else target
	var min_pos: Vector2 = Vector2.ONE * screen_margin
	var max_pos: Vector2 = _game_size() - _call.size - min_pos
	max_pos.x = maxf(min_pos.x, max_pos.x)
	max_pos.y = maxf(min_pos.y, max_pos.y)
	_call.position = Vector2(
		roundf(clampf(desired.x, min_pos.x, max_pos.x)),
		roundf(clampf(desired.y, min_pos.y, max_pos.y)))
	_tail.visible = tracked and tail_texture != null
	if _tail.visible:
		_place_speaker_marker(target)


func _update_attached_position() -> void:
	# Existing storyboard/debug tests call this method explicitly.
	if _session_active:
		_sync_game_scale()
		_update_position()


# The circle is independent of the speech box. Place it over Silas, or
# on the screen edge pointing to him while he is outside the camera.
func _place_speaker_marker(target: Vector2) -> void:
	if tail_texture == null:
		return
	var screen: Vector2 = _game_size()
	var marker: Vector2 = target + Vector2(7.0, -8.0 + sin(_cycle_time * 3.0) * 1.0)
	marker.x = clampf(marker.x, 7.0, screen.x - 7.0)
	marker.y = clampf(marker.y, 7.0, screen.y - 7.0)
	_tail.rotation = 0.0
	_tail.position = (marker - _call.position - _tail.size * 0.5).round()


func hide_call() -> void:
	_call_serial += 1
	_session_active = false
	_repeating = false
	_speaker = null
	_last_state = &"idle"
	_call.hide()
	_tail.hide()
	set_process(false)


func show_hint(message: String) -> void:
	_sync_game_scale()
	# Brief guidance uses a small, wrapped 8px Pixel Operator label in
	# the top-right instead of an unreadable viewport-wide bottom banner.
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.text = message
	_hint.size = Vector2(132.0, 30.0)
	_hint.position = Vector2(_game_size().x - 141.0, 18.0).round()
	_hint.visible = not message.is_empty()
	if _hint_frame != null:
		_hint_frame.position = _hint.position - Vector2(5.0, 3.0)
		_hint_frame.size = _hint.size + Vector2(10.0, 6.0)
		_hint_frame.visible = _hint.visible and bubble_texture != null


func hide_hint() -> void:
	_hint.hide()
	if _hint_frame != null:
		_hint_frame.hide()
