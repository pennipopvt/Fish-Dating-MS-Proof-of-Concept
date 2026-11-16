class_name SpeechBubble
extends Panel

# Reusable world-space bubble with a slim one-pixel frame in the terminal palette.
# Set an icon and/or a short line of text. The pixel tail points down.
const ICON_ONLY_SIZE := Vector2(32, 32)
const TEXT_SIZE := Vector2(138, 54)

@onready var _icon: TextureRect = $Icon
@onready var _label: Label = $Caption
@onready var _tail_outline: Polygon2D = $TailOutline
@onready var _tail_fill: Polygon2D = $TailFill


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", PixelUI.notification_bubble_style())
	set_content(null)


func set_content(icon: Texture2D, message: String = "") -> void:
	# Also supports calls made directly after instancing.
	if not is_node_ready():
		await ready
	_icon.texture = icon
	_icon.visible = icon != null
	_label.text = message
	_label.visible = not message.is_empty()
	size = TEXT_SIZE if not message.is_empty() else ICON_ONLY_SIZE
	# The 24x24 fish portrait has only 4px of padding on each side.
	_icon.position = Vector2(4, 4)
	_icon.size = Vector2(24, 24)
	_label.position = Vector2(32 if icon != null else 4, 4)
	_label.size = Vector2(size.x - _label.position.x - 4, size.y - 8)
	var center_x: float = roundf(size.x * 0.5)
	_tail_outline.position = Vector2(center_x - 6, size.y - 3)
	_tail_fill.position = Vector2(center_x - 4, size.y - 3)
