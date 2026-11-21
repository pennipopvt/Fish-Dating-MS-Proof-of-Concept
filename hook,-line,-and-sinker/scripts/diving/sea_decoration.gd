@tool
extends AnimatedSprite2D
class_name SeaDecoration

# One editor-placeable decoration for every animation in the shared
# SpriteFrames library. Use AnimatedSprite2D's native Animation dropdown,
# Speed Scale, Flip H, Modulate and Z Index properties per instance.
@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		if is_node_ready():
			_play_selected()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animation_changed.connect(_play_selected)
	sprite_frames_changed.connect(_play_selected)
	_play_selected()


func _play_selected() -> void:
	if sprite_frames == null or not sprite_frames.has_animation(animation) \
			or sprite_frames.get_frame_count(animation) == 0:
		stop()
		return
	if Engine.is_editor_hint() and not preview_in_editor:
		stop()
		return
	play(animation)
