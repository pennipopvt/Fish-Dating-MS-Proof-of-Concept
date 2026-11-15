class_name SpeechBubble
extends NinePatchRect

# Reusable world-space bubble using the same 9-slice frame as the terminal.
# Set an icon and/or a short line of text. The pixel tail points down.
const ICON_ONLY_SIZE := Vector2(45, 48)
const TEXT_SIZE := Vector2(138, 54)

@onready var _icon: TextureRect = $Icon
@onready var _label: Label = $Caption
@onready var _tail_outline: Polygon2D = $TailOutline
@onready var _tail_fill: Polygon2D = $TailFill


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_icon.position = Vector2(12, 12)
	_icon.size = Vector2(24, 24)
	_label.position = Vector2(43 if icon != null else 12, 12)
	_label.size = Vector2(size.x - _label.position.x - 9, size.y - 22)
	var center_x: float = roundf(size.x * 0.5)
	_tail_outline.position = Vector2(center_x - 6, size.y - 3)
	_tail_fill.position = Vector2(center_x - 4, size.y - 3)
