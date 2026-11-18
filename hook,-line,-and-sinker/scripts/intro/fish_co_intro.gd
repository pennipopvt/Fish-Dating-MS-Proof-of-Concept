extends Control
class_name FishCoIntro

# Visual backdrop only. The opening now uses the SAME DialogueManager and
# DialogueUI as Silas, dates, and other conversations. The script/dialogue and
# Fish Co portrait are configured on resources, not in this scene.
const STAGE_SIZE := Vector2(320.0, 180.0)

@onready var _penni: Sprite2D = $Penni

var _time: float = 0.0
var _stage_scale: float = 1.0
var _stage_origin: Vector2 = Vector2.ZERO
var _penni_base: Vector2 = Vector2.ZERO


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_recalculate_stage)
	_recalculate_stage()
	set_process(false)


func play() -> void:
	_time = 0.0
	show()
	set_process(true)
	_recalculate_stage()


func end() -> void:
	hide()
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	_penni.position = _penni_base + Vector2(0.0, sin(_time * 1.8) * _stage_scale * 0.7)
	queue_redraw()


func _recalculate_stage() -> void:
	_stage_scale = maxf(minf(size.x / STAGE_SIZE.x, size.y / STAGE_SIZE.y), 0.1)
	_stage_origin = (size - STAGE_SIZE * _stage_scale) * 0.5
	_penni_base = _at(158.0, 80.0)
	if is_instance_valid(_penni):
		_penni.position = _penni_base
		_penni.scale = Vector2.ONE * _stage_scale * 0.8
	queue_redraw()


func _at(x: float, y: float) -> Vector2:
	return _stage_origin + Vector2(x, y) * _stage_scale


func _draw() -> void:
	if _stage_scale <= 0.0:
		return
	# Playable placeholder boat; dialogue and portraits are drawn separately
	# by the existing DialogueUI above this CanvasLayer.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#102f4c"))
	draw_rect(Rect2(_at(0, 0), STAGE_SIZE * _stage_scale), Color("#93bbc7"))
	draw_rect(Rect2(_at(0, 102), Vector2(320, 78) * _stage_scale), Color("#215a75"))
	draw_rect(Rect2(_at(0, 122), Vector2(320, 58) * _stage_scale), Color("#173d60"))
	for i in range(13):
		var wave_x: float = fposmod(float(i) * 31.0 + sin(_time * 0.7 + float(i)) * 5.0, 316.0)
		var wave_y: float = 109.0 + float(i % 5) * 13.0
		draw_line(_at(wave_x, wave_y), _at(wave_x + 18, wave_y),
			Color(0.65, 0.89, 0.93, 0.38), maxf(1.0, _stage_scale * 0.5))
	draw_colored_polygon(PackedVector2Array([
		_at(102, 91), _at(215, 91), _at(202, 109),
		_at(113, 109)
	]), Color("#503c3c"))
	draw_line(_at(106, 92), _at(210, 92), Color("#d6ae7c"), 3.0 * _stage_scale)
	draw_rect(Rect2(_at(144, 87), Vector2(28, 5) * _stage_scale), Color("#9b7557"))
	draw_line(_at(174, 87), _at(174, 61), Color("#6f5350"), 2.0 * _stage_scale)
	draw_colored_polygon(PackedVector2Array([
		_at(177, 63), _at(177, 82), _at(196, 81)
	]), Color("#f1e6c7"))
