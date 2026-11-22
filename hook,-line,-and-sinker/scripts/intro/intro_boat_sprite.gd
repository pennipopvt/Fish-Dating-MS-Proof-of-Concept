@tool
class_name IntroBoatSprite
extends AnimatedSprite2D

# The artist's existing boat.png is the sheet. Change Columns/Rows and
# Frame Count in the Inspector if the artist rearranges the frames.
@export var sprite_sheet: Texture2D
@export_range(1, 16, 1) var columns: int = 4
@export_range(1, 16, 1) var rows: int = 1
@export_range(1, 256, 1) var frame_count: int = 4
@export_range(1.0, 24.0, 0.5) var frames_per_second: float = 5.0


func _ready() -> void:
	_build_frames()
	if sprite_frames != null and sprite_frames.has_animation(&"sail"):
		play(&"sail")


func _build_frames() -> void:
	if sprite_sheet == null:
		return
	if sprite_sheet.get_width() % columns != 0 or sprite_sheet.get_height() % rows != 0:
		push_warning("Boat frames do not divide the sheet; adjust Columns/Rows.")
		return
	var width: int = sprite_sheet.get_width() / columns
	var height: int = sprite_sheet.get_height() / rows
	if width < 1 or height < 1:
		return
	var frames := SpriteFrames.new()
	frames.add_animation(&"sail")
	frames.set_animation_loop(&"sail", true)
	frames.set_animation_speed(&"sail", frames_per_second)
	for index in range(mini(frame_count, columns * rows)):
		var frame := AtlasTexture.new()
		frame.atlas = sprite_sheet
		var column: int = index % columns
		var row: int = index / columns
		frame.region = Rect2(column * width, row * height, width, height)
		frames.add_frame(&"sail", frame)
	sprite_frames = frames
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
