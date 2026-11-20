extends CanvasLayer
class_name SeaOxygenHud

# Small placeholder in the SAME 320x180 SubViewport as the sea.
# CanvasLayer is screen-space, NOT parented to Player/Camera2D: the meter
# must not drift or get cut off when the camera moves or changes its zoom.
# All visual properties remain exposed for future custom HUD art.
const VIGNETTE_SHADER: Shader = preload("res://shaders/sea_low_oxygen_vignette.gdshader")
const VIEW_SIZE := Vector2(320.0, 180.0)

@export var bar_position: Vector2 = Vector2(10.0, 10.0)
@export var bar_size: Vector2 = Vector2(46.0, 5.0)
@export var bar_color: Color = Color("#8cdde7")
@export var warning_color: Color = Color("#f46d73")
@export var frame_color: Color = Color("#122d39")

var _fraction: float = 1.0
var _warning_fraction: float = 0.25
var _vignette: ColorRect
var _frame: ColorRect
var _track: ColorRect
var _fill: ColorRect


func _ready() -> void:
	layer = 10
	# This HUD follows the viewport, never the Camera2D transform.
	follow_viewport_enabled = false

	_vignette = ColorRect.new()
	_vignette.name = "LowOxygenVignette"
	_vignette.position = Vector2.ZERO
	_vignette.size = VIEW_SIZE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE_SHADER
	_vignette.material = material
	add_child(_vignette)

	_frame = _make_rect("MeterFrame", frame_color)
	_track = _make_rect("MeterTrack", Color("#294b57"))
	_fill = _make_rect("MeterFill", bar_color)
	_refresh_meter()
	hide()


func _make_rect(name_for_node: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = name_for_node
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func show_oxygen(ratio: float, is_enabled: bool, warning: float) -> void:
	_fraction = clampf(ratio, 0.0, 1.0)
	_warning_fraction = maxf(warning, 0.01)
	_refresh_meter()
	visible = is_enabled
	var intensity: float = clampf(
		(_warning_fraction - _fraction) / _warning_fraction, 0.0, 1.0)
	(_vignette.material as ShaderMaterial).set_shader_parameter(
		"warning_strength", intensity)


func _refresh_meter() -> void:
	if not is_node_ready() and _frame == null:
		return
	_frame.position = bar_position - Vector2.ONE
	_frame.size = bar_size + Vector2(2.0, 2.0)
	_track.position = bar_position
	_track.size = bar_size
	_fill.position = bar_position
	_fill.size = Vector2(maxf(0.0, bar_size.x * _fraction), bar_size.y)
	_fill.color = warning_color if _fraction <= _warning_fraction else bar_color
	_fill.visible = _fraction > 0.0
