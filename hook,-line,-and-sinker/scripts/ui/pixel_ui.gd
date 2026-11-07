class_name PixelUI
extends RefCounted

# Shared pixel-art UI kit: palette, fonts, 9-slice boxes and a Theme.
# Everything sits on a SCALE-pixel grid (1920x1080 = 640x360 art pixels at 3x),
# so borders, fonts and icons line up with the game's pixel art.

const SCALE := 3

# Palette, taken from the terminal sprite (cyan screen on dark navy).
const INK := Color("0a141a")          # outlines
const WINDOW := Color("14232e")
const INSET := Color("0e1a22")
const ROW := Color("1b2f3b")
const ROW_EDGE := Color("2a4a58")
const ROW_DONE := Color("1f4048")
const CYAN := Color("7fe8e0")
const CYAN_DARK := Color("3fa8a8")
const TEAL := Color("2a5f7a")
const TEAL_HOVER := Color("36789a")
const TEAL_SELECTED := Color("4f9fca")
const TEXT := Color("e8fbf8")
const TEXT_DIM := Color("7fa3a8")
const GOLD := Color("f0c060")
const GREEN := Color("8fe06a")
const RED := Color("f07a6a")

# Font sizes are whole multiples of each font's pixel grid.
const SMALL_SIZE := 8 * SCALE     # PixelOperator8: body text
const LARGE_SIZE := 16 * SCALE    # PixelOperator: headers

const FONT_SMALL := preload("res://fonts/pixel_operator(1)/PixelOperator8.ttf")
const FONT_SMALL_BOLD := preload("res://fonts/pixel_operator(1)/PixelOperator8-Bold.ttf")
const FONT_LARGE_BOLD := preload("res://fonts/pixel_operator(1)/PixelOperator-Bold.ttf")

# User-drawn 32x32 terminal panel: 4 art-pixel patches around the corners.
# Kept separate from the generic PixelUI.box() until the appearance is approved.
const TERMINAL_FRAME_TEXTURE: Texture2D = preload("res://sprites/ui/ui_background.png")
const TERMINAL_PATCH_MARGIN := 4
static var _terminal_frame_style: StyleBoxTexture

static var _theme: Theme


# Show the hand-drawn 9-slice at the game's 3x integer art scale.
# Enlarge with nearest-neighbor BEFORE nine-slicing so the corners stay pixel sharp.
# This only applies to the Terminal's large outer frame for the initial visual test.
static func terminal_frame_style() -> StyleBoxTexture:
	if _terminal_frame_style != null:
		return _terminal_frame_style

	var source_image: Image = TERMINAL_FRAME_TEXTURE.get_image()
	source_image.resize(
		source_image.get_width() * SCALE,
		source_image.get_height() * SCALE,
		Image.INTERPOLATE_NEAREST
	)

	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(source_image)
	style.set_texture_margin_all(TERMINAL_PATCH_MARGIN * SCALE)
	# The scene already has a MarginContainer to keep text away from the border.
	style.set_content_margin_all(0)
	_terminal_frame_style = style
	return style


# A pixel box: 1-px ink outline with cut corners, 1-px border, optional
# 1-px top highlight, solid fill. `padding` is in art pixels.
static func box(fill: Color, border: Color, padding: int = 3, highlight := Color(0, 0, 0, 0)) -> StyleBoxTexture:
	const SIZE := 7
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(fill)

	for ring in 2:
		var color := INK if ring == 0 else border
		var far := SIZE - 1 - ring
		for i in range(ring, far + 1):
			image.set_pixel(i, ring, color)
			image.set_pixel(i, far, color)
			image.set_pixel(ring, i, color)
			image.set_pixel(far, i, color)

	if highlight.a > 0.0:
		for x in range(2, SIZE - 2):
			image.set_pixel(x, 2, highlight)

	# Cut corners for a rounded pixel look.
	for corner in [Vector2i(0, 0), Vector2i(SIZE - 1, 0), Vector2i(0, SIZE - 1), Vector2i(SIZE - 1, SIZE - 1)]:
		image.set_pixelv(corner, Color(0, 0, 0, 0))

	image.resize(SIZE * SCALE, SIZE * SCALE, Image.INTERPOLATE_NEAREST)

	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.set_texture_margin_all(3 * SCALE)
	style.set_content_margin_all((2 + padding) * SCALE)
	return style


# A flat bar segment (progress bars), outlined in ink.
static func bar(fill: Color) -> StyleBoxTexture:
	var style := box(fill, fill, 0)
	style.set_content_margin_all(0)
	return style


static func label(text: String, variation: StringName = &"", color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


# Shared theme for in-game menus. Built once.
static func get_theme() -> Theme:
	if _theme != null:
		return _theme

	var t := Theme.new()
	t.default_font = FONT_SMALL
	t.default_font_size = SMALL_SIZE

	t.set_color("font_color", "Label", TEXT)

	# Large header text, e.g. window titles.
	t.set_type_variation(&"HeaderLabel", &"Label")
	t.set_font("font", &"HeaderLabel", FONT_LARGE_BOLD)
	t.set_font_size("font_size", &"HeaderLabel", LARGE_SIZE)
	t.set_color("font_color", &"HeaderLabel", CYAN)

	# Bold body-size text, e.g. challenge names.
	t.set_type_variation(&"TitleLabel", &"Label")
	t.set_font("font", &"TitleLabel", FONT_SMALL_BOLD)
	t.set_color("font_color", &"TitleLabel", TEXT)

	t.set_type_variation(&"DimLabel", &"Label")
	t.set_color("font_color", &"DimLabel", TEXT_DIM)

	t.set_stylebox("panel", "PanelContainer", box(WINDOW, CYAN_DARK, 6, Color("1d3442")))

	t.set_stylebox("normal", "Button", box(TEAL, CYAN_DARK, 2))
	t.set_stylebox("hover", "Button", box(TEAL_HOVER, CYAN, 2))
	t.set_stylebox("pressed", "Button", box(TEAL_SELECTED, CYAN, 2))
	t.set_stylebox("hover_pressed", "Button", box(TEAL_SELECTED, CYAN, 2))
	t.set_stylebox("disabled", "Button", box(ROW, ROW_EDGE, 2))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), CYAN, 2))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)

	t.set_stylebox("tab_selected", "TabBar", box(TEAL, CYAN, 3))
	t.set_stylebox("tab_hovered", "TabBar", box(TEAL_HOVER, CYAN_DARK, 3))
	t.set_stylebox("tab_unselected", "TabBar", box(ROW, ROW_EDGE, 3))
	t.set_stylebox("tab_focus", "TabBar", box(Color(0, 0, 0, 0), CYAN, 3))
	t.set_color("font_selected_color", "TabBar", TEXT)
	t.set_color("font_hovered_color", "TabBar", TEXT)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_constant("h_separation", "TabBar", 2 * SCALE)

	t.set_stylebox("background", "ProgressBar", box(INSET, ROW_EDGE, 0))
	t.set_stylebox("fill", "ProgressBar", bar(CYAN))

	t.set_stylebox("scroll", "VScrollBar", box(INSET, ROW_EDGE, 0))
	t.set_stylebox("grabber", "VScrollBar", bar(CYAN_DARK))
	t.set_stylebox("grabber_highlight", "VScrollBar", bar(CYAN))
	t.set_stylebox("grabber_pressed", "VScrollBar", bar(CYAN))

	var line := StyleBoxLine.new()
	line.color = ROW_EDGE
	line.thickness = SCALE
	line.vertical = true
	t.set_stylebox("separator", "VSeparator", line)
	t.set_constant("separation", "VSeparator", 4 * SCALE)

	_theme = t
	return t
