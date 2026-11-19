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

# Optional user-made graphics. When blank, simple key/mouse images are
# drawn in memory so the tutorial never depends on newly imported assets.
@export var movement_sprite: Texture2D
@export var cast_sprite: Texture2D
@export var reel_sprite: Texture2D

const GLYPHS: Dictionary = {
	"W": ["10001", "10001", "10101", "10101", "10101", "11011", "10001"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"]
}

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
var _fallback_icons: Dictionary = {}


func _ready() -> void:
	add_to_group("sea_speech_bubble")
	_call.hide()
	_hint.hide()
	if _input_sprite != null:
		_input_sprite.hide()
		_place_input_sprite()
		get_viewport().size_changed.connect(_place_input_sprite)
	_apply_frame()


# Put the one sprite in actual viewport pixels. This doesn't rely on
# CanvasLayer anchoring inside a dynamically stretched SubViewportContainer.
func _place_input_sprite() -> void:
	if _input_sprite == null:
		return
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	_input_sprite.position = Vector2(
		roundf((screen_size.x - _input_sprite.size.x) * 0.5),
		roundf(screen_size.y * 0.72 - _input_sprite.size.y * 0.5)
	)


func is_input_prompt_visible(action: StringName) -> bool:
	return _input_sprite != null and _input_sprite.is_visible_in_tree() \
		and _input_sprite.texture != null and current_action == action


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


func show_input_prompt(action: StringName) -> bool:
	_hint.hide()
	if _input_sprite == null:
		push_warning("SeaSpeechBubble is missing its InputSprite TextureRect.")
		return false
	var graphic: Texture2D
	match action:
		&"move": graphic = movement_sprite
		&"cast": graphic = cast_sprite
		&"reel": graphic = reel_sprite
		_:
			hide_input_prompt()
			return false
	if graphic == null:
		graphic = _fallback_icon(action)
	if graphic == null:
		hide_input_prompt()
		return false
	if current_action == action and _input_sprite.visible:
		return is_input_prompt_visible(action)
	current_action = action
	_input_sprite.texture = graphic
	if _input_tween != null and _input_tween.is_running():
		_input_tween.kill()
	_input_sprite.modulate.a = 0.0
	_input_sprite.show()
	_input_tween = create_tween()
	_input_tween.tween_property(_input_sprite, "modulate:a", 1.0, 0.3)
	return is_input_prompt_visible(action)


func hide_input_prompt() -> void:
	current_action = &""
	if _input_sprite == null or not _input_sprite.visible:
		return
	if _input_tween != null and _input_tween.is_running():
		_input_tween.kill()
	_input_tween = create_tween()
	_input_tween.tween_property(_input_sprite, "modulate:a", 0.0, 0.16)
	_input_tween.tween_callback(_input_sprite.hide)


# Transparent, editor-independent placeholder art. The output is a real
# ImageTexture assigned to the single InputSprite; replacing the Inspector
# Texture2D exports above overrides this without changing the story logic.
func _fallback_icon(action: StringName) -> Texture2D:
	if _fallback_icons.has(action):
		return _fallback_icons[action] as Texture2D
	var pixels: Image = Image.create(96, 64, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	match action:
		&"move":
			_draw_key(pixels, Vector2i(34, 2), "W")
			_draw_key(pixels, Vector2i(2, 34), "A")
			_draw_key(pixels, Vector2i(34, 34), "S")
			_draw_key(pixels, Vector2i(66, 34), "D")
		&"cast":
			_draw_mouse(pixels, false)
		&"reel":
			_draw_mouse(pixels, true)
		_:
			return null
	var result: ImageTexture = ImageTexture.create_from_image(pixels)
	_fallback_icons[action] = result
	return result


func _draw_key(pixels: Image, start: Vector2i, letter: String) -> void:
	var border := Color(0.50, 0.86, 0.93)
	var interior := Color(0.08, 0.22, 0.31, 0.88)
	var light := Color(0.96, 1.0, 1.0)
	pixels.fill_rect(Rect2i(start, Vector2i(28, 28)), border)
	pixels.fill_rect(Rect2i(start + Vector2i(2, 2), Vector2i(24, 24)), interior)
	var rows: Array = GLYPHS.get(letter, [])
	for y in range(rows.size()):
		var row: String = str(rows[y])
		for x in range(row.length()):
			if row[x] == "1":
				pixels.fill_rect(Rect2i(start + Vector2i(9 + x * 2, 7 + y * 2),
					Vector2i(2, 2)), light)


func _draw_mouse(pixels: Image, scroll: bool) -> void:
	var border := Color(0.89, 0.98, 1.0)
	var interior := Color(0.08, 0.22, 0.31, 0.88)
	var accent := Color(0.53, 0.91, 0.95)
	pixels.fill_rect(Rect2i(27, 2, 42, 60), border)
	pixels.fill_rect(Rect2i(30, 5, 36, 54), interior)
	pixels.fill_rect(Rect2i(30, 24, 36, 2), border)
	pixels.fill_rect(Rect2i(47, 5, 2, 19), border)
	if scroll:
		pixels.fill_rect(Rect2i(44, 10, 8, 15), accent)
		pixels.fill_rect(Rect2i(46, 34, 4, 13), accent)
		pixels.fill_rect(Rect2i(42, 43, 12, 4), accent)
		pixels.fill_rect(Rect2i(45, 47, 6, 4), accent)
	else:
		pixels.fill_rect(Rect2i(30, 5, 17, 19), accent)
