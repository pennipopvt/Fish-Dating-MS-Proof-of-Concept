class_name TitleImageButton
extends TextureButton

# The Texture Normal slot owns the image; hover and pressed feedback never
# replace that texture. All interaction settings are editable on each button.
@export_group("Button Feedback")
@export_range(1.0, 1.4, 0.01) var hover_scale: float = 1.08
@export_range(0.2, 1.0, 0.05) var pressed_brightness: float = 0.65
@export_range(0.0, 0.5, 0.01, "suffix:s") var feedback_seconds: float = 0.12

var _base_scale: Vector2
var _base_tint: Color
var _hovered: bool = false
var _held: bool = false
var _feedback_tween: Tween


func _ready() -> void:
	_base_scale = scale
	_base_tint = self_modulate
	_update_pivot()
	resized.connect(_update_pivot)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _update_pivot() -> void:
	# Scale around the image center without shifting the surrounding VBox.
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	_hovered = true
	_update_feedback()


func _on_mouse_exited() -> void:
	_hovered = false
	_update_feedback()


func _on_button_down() -> void:
	_held = true
	_update_feedback()


func _on_button_up() -> void:
	_held = false
	_update_feedback()


func _update_feedback() -> void:
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	var desired_scale: Vector2 = _base_scale * (hover_scale if _hovered else 1.0)
	var desired_tint: Color = _base_tint
	if _held:
		desired_tint = Color(
		_base_tint.r * pressed_brightness,
		_base_tint.g * pressed_brightness,
		_base_tint.b * pressed_brightness,
		_base_tint.a
		)
	if feedback_seconds <= 0.0:
		scale = desired_scale
		self_modulate = desired_tint
		return
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(self, "scale", desired_scale, feedback_seconds)
	_feedback_tween.parallel().tween_property(
		self, "self_modulate", desired_tint, feedback_seconds)
