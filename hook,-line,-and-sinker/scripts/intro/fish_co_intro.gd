extends Control
class_name FishCoIntro

# A short staged phone call over a placeholder boat. All spoken lines are
# editable in dialogue/fish_co_phone_intro.json rather than hardcoded here.
signal finished

const CALL_SCRIPT_PATH := "res://dialogue/fish_co_phone_intro.json"
const STAGE_SIZE := Vector2(320.0, 180.0)

@onready var _penni: Sprite2D = $Penni
@onready var _speaker: Label = $DialoguePanel/Margin/Layout/Speaker
@onready var _speech: Label = $DialoguePanel/Margin/Layout/Speech
@onready var _page_count: Label = $DialoguePanel/Margin/Layout/Bottom/PageCount
@onready var _continue: Button = $DialoguePanel/Margin/Layout/Bottom/Continue

var _pages: Array[Dictionary] = []
var _page_index: int = 0
var _time: float = 0.0
var _stage_scale: float = 1.0
var _stage_origin: Vector2 = Vector2.ZERO
var _penni_base: Vector2 = Vector2.ZERO


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_continue.pressed.connect(advance)
	resized.connect(_recalculate_stage)
	_load_pages()
	_recalculate_stage()
	set_process(false)


func _load_pages() -> void:
	_pages.clear()
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(CALL_SCRIPT_PATH))
	if not json is Dictionary:
		push_error("Fish Co. intro dialogue could not be loaded: " + CALL_SCRIPT_PATH)
		return
	var lines: Variant = json.get("lines", [])
	if not lines is Array:
		push_error("Fish Co. intro dialogue must provide a lines array.")
		return
	for entry in lines:
		if entry is Dictionary and entry.has("speaker") and entry.has("text"):
			_pages.append(entry.duplicate(true))


func play() -> void:
	if _pages.is_empty():
		finished.emit()
		return
	_page_index = 0
	_time = 0.0
	show()
	set_process(true)
	_show_page()
	_continue.grab_focus()


func advance() -> void:
	if not visible:
		return
	_page_index += 1
	if _page_index >= _pages.size():
		hide()
		set_process(false)
		finished.emit()
		return
	_show_page()


func _show_page() -> void:
	var page: Dictionary = _pages[_page_index]
	var is_penni: bool = str(page["speaker"]) == "Penni"
	_speaker.text = str(page["speaker"]).to_upper()
	_speaker.add_theme_color_override("font_color",
		Color("#b5e1f7") if is_penni else Color("#f4d68d"))
	_speech.text = str(page["text"])
	_page_count.text = "%02d / %02d" % [_page_index + 1, _pages.size()]
	_continue.text = "HANG UP" if _page_index == _pages.size() - 1 else "CONTINUE"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
			advance()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta
	_penni.position = _penni_base + Vector2(0.0, sin(_time * 1.8) * _stage_scale * 0.7)
	queue_redraw()


func _recalculate_stage() -> void:
	_stage_scale = maxf(minf(size.x / STAGE_SIZE.x, size.y / STAGE_SIZE.y), 0.1)
	_stage_origin = (size - STAGE_SIZE * _stage_scale) * 0.5
	_penni_base = _at(158.0, 80.0)
	_penni.position = _penni_base
	_penni.scale = Vector2.ONE * _stage_scale * 0.8
	queue_redraw()


func _at(x: float, y: float) -> Vector2:
	return _stage_origin + Vector2(x, y) * _stage_scale


func _draw() -> void:
	if _stage_scale <= 0.0:
		return
	# Minimal pixel-shape blocking so the introduction is playable before
	# a finished boat background/animation is created.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#102f4c"))
	draw_rect(Rect2(_at(0, 0), STAGE_SIZE * _stage_scale), Color("#93bbc7"))
	draw_rect(Rect2(_at(0, 102), Vector2(320, 78) * _stage_scale), Color("#215a75"))
	draw_rect(Rect2(_at(0, 122), Vector2(320, 58) * _stage_scale), Color("#173d60"))
	for i in range(13):
		var wave_x: float = fposmod(float(i) * 31.0 + sin(_time * 0.7 + float(i)) * 5.0, 316.0)
		var wave_y: float = 109.0 + float(i % 5) * 13.0
		draw_line(_at(wave_x, wave_y), _at(wave_x + 18, wave_y),
			Color(0.65, 0.89, 0.93, 0.38), maxf(1.0, _stage_scale * 0.5))
	# A tiny wooden boat with a low rail, floating in front of the horizon.
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
