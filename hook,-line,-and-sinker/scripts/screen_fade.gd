class_name ScreenFade
extends CanvasLayer

# Full-screen fade to/from black. Add it under the root so it covers the whole
# window. While visible it's in the modal_ui group, so the player can't act
# (GameManager.is_modal_ui_open).

const DEFAULT_DURATION := 0.5

var _rect: ColorRect


func _init() -> void:
	layer = 20
	visible = false
	add_to_group(&"modal_ui")
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


# 1.0 = black, 0.0 = clear (hides the layer when done).
func fade_to(alpha: float, duration: float = DEFAULT_DURATION) -> void:
	show()
	var tween := create_tween()
	tween.tween_property(_rect, "modulate:a", alpha, duration)
	await tween.finished
	if alpha <= 0.0:
		hide()
