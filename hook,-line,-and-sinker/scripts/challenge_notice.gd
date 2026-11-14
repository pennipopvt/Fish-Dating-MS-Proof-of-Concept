class_name ChallengeNotice
extends Node2D

# In-world "challenge done" bubble that pops up above the terminal, drawn in
# world pixels in the terminal's palette. The node's origin is the tip of the
# bubble's tail; the bubble sits above it.
#
# Usage:
#   var notice := ChallengeNotice.new()
#   notice.challenge = challenge
#   terminal.add_child(notice)   # position = where the tail points
#   await notice.finished

signal finished

const SUBTITLE := "CHALLENGE DONE"
const FONT := PixelUI.FONT_SMALL
const FONT_BOLD := PixelUI.FONT_SMALL_BOLD
const FONT_SIZE := 8
const LINE_HEIGHT := 9
const ICON_SIZE := 16
const PADDING := 3   # inside the 2-px frame
const GAP := 3       # between icon and text
const TAIL := 3

const RISE := 4.0
const APPEAR_TIME := 0.25
const HOLD_TIME := 4.0
const FADE_TIME := 0.5

var challenge: ChallengeData
# Reused for other notices (e.g. affection): set these instead of challenge.
var subtitle: String = SUBTITLE
var title: String = ""

var _size := Vector2i.ZERO
var _rest_y := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 20

	if challenge != null:
		title = challenge.display_name
	var text_width := maxi(
		ceili(FONT.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x),
		ceili(FONT_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	)
	var inner := Vector2i(_icon_space() + text_width, maxi(ICON_SIZE, LINE_HEIGHT * 2))
	_size = inner + Vector2i.ONE * (PADDING + 2) * 2

	_rest_y = position.y
	_play()


func _play() -> void:
	modulate.a = 0.0
	_set_rise(RISE)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, APPEAR_TIME)
	tween.parallel().tween_method(_set_rise, RISE, 0.0, APPEAR_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	await tween.finished

	finished.emit()
	queue_free()


# Whole pixels only, so the bubble stays on the art grid while it moves.
func _set_rise(offset: float) -> void:
	position.y = _rest_y + roundf(offset)


func _draw() -> void:
	var w := _size.x
	var h := _size.y
	var left := -(w / 2)
	var top := -TAIL - h

	# Frame: ink outline, cyan border, window fill. Corners cut.
	_box(Rect2i(left, top, w, h), PixelUI.INK)
	_box(Rect2i(left + 1, top + 1, w - 2, h - 2), PixelUI.CYAN_DARK)
	draw_rect(Rect2(left + 2, top + 2, w - 4, h - 4), PixelUI.WINDOW)
	draw_rect(Rect2(left + 2, top + 2, w - 4, 1), Color("1d3442"))  # top highlight

	# Tail pointing down at the terminal; its top row opens into the border.
	for row in TAIL + 1:
		var half := TAIL - row
		var y := top + h - 1 + row
		draw_rect(Rect2(-half - 1, y, half * 2 + 3, 1), PixelUI.INK)
		if half > 0:
			draw_rect(Rect2(-half, y, half * 2 + 1, 1), PixelUI.CYAN_DARK)

	var content := Vector2i(left, top) + Vector2i.ONE * (PADDING + 2)
	var content_h := _size.y - (PADDING + 2) * 2

	if _icon() != null:
		var icon_y := content.y + (content_h - ICON_SIZE) / 2
		draw_texture_rect(_icon(), Rect2(content.x, icon_y, ICON_SIZE, ICON_SIZE), false)

	var text_x := content.x + _icon_space()
	var text_y := content.y + (content_h - LINE_HEIGHT * 2) / 2
	var ascent := roundi(FONT.get_ascent(FONT_SIZE))
	draw_string(FONT, Vector2(text_x, text_y + ascent), subtitle,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, PixelUI.CYAN)
	draw_string(FONT_BOLD, Vector2(text_x, text_y + LINE_HEIGHT + ascent), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, PixelUI.TEXT)


func _icon() -> Texture2D:
	return challenge.icon if challenge != null else null


# Width taken by the icon column: always for challenges (as before), none
# for text-only notices.
func _icon_space() -> int:
	return ICON_SIZE + GAP if challenge != null else 0


# Filled rect with its four corner pixels left out.
func _box(rect: Rect2i, color: Color) -> void:
	draw_rect(Rect2(rect.position.x + 1, rect.position.y, rect.size.x - 2, rect.size.y), color)
	draw_rect(Rect2(rect.position.x, rect.position.y + 1, rect.size.x, rect.size.y - 2), color)
