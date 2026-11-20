extends Node2D
class_name SeaOxygenHud

# A small placeholder meter inside the existing 320x180 world viewport.
# This is a camera child, so it stays in screen space while Penni swims.
# Visuals are deliberately separate from SeaOxygen's timer.
const VIGNETTE_SHADER: Shader = preload("res://shaders/sea_low_oxygen_vignette.gdshader")

@export var bar_position: Vector2 = Vector2(-150.0, -81.0)
@export var bar_size: Vector2 = Vector2(46.0, 5.0)
@export var bar_color: Color = Color("#8cdde7")
@export var warning_color: Color = Color("#f46d73")
@export var frame_color: Color = Color("#122d39")

var _fraction: float = 1.0
var _warning_fraction: float = 0.25
var _vignette: ColorRect


func _ready() -> void:
	z_as_relative = false
	z_index = 115
	_vignette = ColorRect.new()
	_vignette.name = "LowOxygenVignette"
	_vignette.position = Vector2(-160.0, -90.0)
	_vignette.size = Vector2(320.0, 180.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color.WHITE
	_vignette.z_index = -1
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE_SHADER
	_vignette.material = material
	add_child(_vignette)
	hide()


func show_oxygen(ratio: float, is_enabled: bool, warning: float) -> void:
	_fraction = clampf(ratio, 0.0, 1.0)
	_warning_fraction = maxf(warning, 0.01)
	visible = is_enabled
	var intensity: float = clampf((_warning_fraction - _fraction) / _warning_fraction, 0.0, 1.0)
	(_vignette.material as ShaderMaterial).set_shader_parameter("warning_strength", intensity)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(bar_position - Vector2.ONE, bar_size + Vector2(2, 2)),
		frame_color)
	draw_rect(Rect2(bar_position, bar_size), Color("#294b57"))
	var fill_width: float = bar_size.x * _fraction
	if fill_width > 0.0:
		draw_rect(Rect2(bar_position, Vector2(fill_width, bar_size.y)),
			warning_color if _fraction <= _warning_fraction else bar_color)
