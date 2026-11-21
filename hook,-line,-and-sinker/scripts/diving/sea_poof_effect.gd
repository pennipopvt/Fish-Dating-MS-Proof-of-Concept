extends RefCounted
class_name SeaPoofEffect

const POOF_TEXTURE: Texture2D = preload("res://sprites/characters/poof.png")


static func spawn(world: Node2D, at: Vector2) -> AnimatedSprite2D:
	var effect := AnimatedSprite2D.new()
	effect.name = "CompanionPoof"
	effect.z_index = 12
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frames := SpriteFrames.new()
	frames.add_animation(&"poof")
	frames.set_animation_loop(&"poof", false)
	frames.set_animation_speed(&"poof", 12.0)
	var width: int = POOF_TEXTURE.get_width()
	var height: int = POOF_TEXTURE.get_height()
	var horizontal: bool = width > height and width % height == 0
	var vertical: bool = height > width and height % width == 0
	var count: int = int(width / height) if horizontal else (int(height / width) if vertical else 1)
	for i in range(count):
		var frame := AtlasTexture.new()
		frame.atlas = POOF_TEXTURE
		if horizontal:
			frame.region = Rect2(i * height, 0, height, height)
		elif vertical:
			frame.region = Rect2(0, i * width, width, width)
		else:
			frame.region = Rect2(0, 0, width, height)
		frames.add_frame(&"poof", frame)
	effect.sprite_frames = frames
	world.add_child(effect)
	effect.global_position = at + Vector2(0.0, -13.0)
	effect.play(&"poof")
	return effect
