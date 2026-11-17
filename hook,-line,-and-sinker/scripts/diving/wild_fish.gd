extends Node2D
class_name DivingWildFish

# Tiny autonomous fish for the diving vertical slice. They wander on their
# own, notice the player, and flee unless Silas is concealing the approach.
var fish_name: StringName = &""
var swim_speed: float = 20.0
var capture_radius: float = 13.0
var flee_radius: float = 58.0
var region: Rect2 = Rect2(24, 35, 860, 430)
var home: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _heading: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0
var _t: float = 0.0
var _sprite: Sprite2D

func setup(kind: StringName, art: Texture2D, starting_position: Vector2, bounds: Rect2, seed_value: int) -> void:
	fish_name = kind
	position = starting_position
	home = starting_position
	region = bounds
	_rng.seed = seed_value
	swim_speed = _rng.randf_range(14.0, 24.0)
	_heading = Vector2.RIGHT.rotated(_rng.randf_range(-PI, PI))
	_sprite = Sprite2D.new()
	_sprite.name = "FishSprite"
	_sprite.texture = art
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * (20.0 / maxf(float(art.get_width()), 1.0))
	_sprite.z_index = 4
	add_child(_sprite)

func swim(delta: float, player_position: Vector2, concealed: bool) -> void:
	if _sprite == null:
		return
	_t += delta
	_wander_timer -= delta
	var distance: float = position.distance_to(player_position)
	var danger_distance: float = 18.0 if concealed else flee_radius
	var direction: Vector2 = _heading
	if distance < danger_distance and distance > 0.01:
		direction = (position - player_position).normalized()
		_heading = direction
		_wander_timer = 0.8
	else:
		if _wander_timer <= 0.0:
			_wander_timer = _rng.randf_range(1.0, 2.8)
			var toward_home: Vector2 = (home - position).normalized()
			_heading = (Vector2.RIGHT.rotated(_rng.randf_range(-PI, PI)) * 0.55 + toward_home * 0.45).normalized()
		direction = _heading
	var speed: float = swim_speed * (1.9 if distance < danger_distance else 0.62)
	position += direction * speed * delta
	position.x = clampf(position.x, region.position.x + 12.0, region.end.x - 12.0)
	position.y = clampf(position.y, region.position.y + 12.0, region.end.y - 12.0)
	_sprite.flip_h = direction.x < -0.01
	_sprite.position.y = sin(_t * 3.2 + float(_rng.seed % 10)) * 1.4
	rotation = clampf(direction.y * 0.15, -0.20, 0.20)

func is_targeted(world_mouse: Vector2, player_position: Vector2) -> bool:
	return world_mouse.distance_to(position) <= capture_radius + 7.0 and player_position.distance_to(position) <= 45.0

func get_display_name() -> String:
	return String(fish_name).capitalize()
