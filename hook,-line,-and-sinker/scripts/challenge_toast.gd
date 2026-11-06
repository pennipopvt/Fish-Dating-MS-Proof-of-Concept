class_name ChallengeToast
extends CanvasLayer

# Steam-style "Challenge Unlocked" popup that slides up from the bottom-right corner.
# Several completions at once are queued and shown one after another.

const TOAST_SIZE := Vector2(520, 136)
const MARGIN := 32.0
const SLIDE_TIME := 0.35
const HOLD_TIME := 4.0
const BG_TOP := Color("2a475e")
const BG_BOTTOM := Color("1b2838")
const SUBTITLE_COLOR := Color("8f98a0")

var _queue: Array[ChallengeData] = []
var _showing := false
var _panel: PanelContainer
var _icon: TextureRect
var _title: Label


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func show_challenge(challenge: ChallengeData) -> void:
	_queue.append(challenge)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return

	_showing = true
	var challenge: ChallengeData = _queue.pop_front()
	_icon.texture = challenge.icon
	_title.text = challenge.display_name

	var viewport_size := _panel.get_viewport_rect().size
	var shown_y := viewport_size.y - TOAST_SIZE.y - MARGIN
	_panel.position = Vector2(viewport_size.x - TOAST_SIZE.x - MARGIN, viewport_size.y + 8.0)
	_panel.show()

	var tween := create_tween()
	tween.tween_property(_panel, "position:y", shown_y, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(_panel, "position:y", viewport_size.y + 8.0, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(_panel.hide)
	tween.tween_callback(_show_next)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = TOAST_SIZE
	_panel.size = TOAST_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _make_style())
	_panel.hide()
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)

	_icon = TextureRect.new()
	# 32px pixel icons at an exact 3x.
	_icon.custom_minimum_size = Vector2(96, 96)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)

	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	var subtitle := Label.new()
	subtitle.text = "Challenge Unlocked!"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	text.add_child(subtitle)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(_title)


func _make_style() -> StyleBoxTexture:
	# Vertical gradient background with a blue accent line, like Steam's popup.
	var gradient := Gradient.new()
	gradient.set_color(0, BG_TOP)
	gradient.set_color(1, BG_BOTTOM)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64

	var style := StyleBoxTexture.new()
	style.texture = texture
	style.set_content_margin_all(20)
	return style
