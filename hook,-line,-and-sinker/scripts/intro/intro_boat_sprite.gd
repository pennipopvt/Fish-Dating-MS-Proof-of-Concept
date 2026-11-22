@tool
class_name IntroBoatSprite
extends AnimatedSprite2D

# The artist's existing boat.png is the sheet. Change Frame Count and
# Vertical Strip in the inspector if the sprite sheet layout changes.
@export var sprite_sheet: Texture2D
@export_range(1, 16, 1) var frame_count: int = 4
@export var vertical_strip: bool = false
@export_range(1.0, 24.0, 0.5) var frames_per_second: float = 5.0


func _ready() -> void:
	_build_frames()
	if sprite_frames != null and sprite_frames.has_animation(&"sail"):
		play(&"sail")


func _build_frames() -> void:
	if sprite_sheet == null:
		return
	var columns: int = 1 if vertical_strip else frame_count
	var rows: int = frame_count if vertical_strip else 1
	if sprite_sheet.get_width() % columns != 0 or sprite_sheet.get_height() % rows != 0:
		push_warning("Boat frames do not divide the sheet; adjust Frame Count/Vertical Strip.")
		return
	var width: int = sprite_sheet.get_width() / columns
	var height: int = sprite_sheet.get_height() / rows
	if width < 1 or height < 1:
		return
	var frames := SpriteFrames.new()
	frames.add_animation(&"sail")
	frames.set_animation_loop(&"sail", true)
	frames.set_animation_speed(&"sail", frames_per_second)
	for index in range(frame_count):
		var frame := AtlasTexture.new()
		frame.atlas = sprite_sheet
		frame.region = Rect2(index * width if not vertical_strip else 0,
			index * height if vertical_strip else 0, width, height)
		frames.add_frame(&"sail", frame)
	sprite_frames = frames
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
