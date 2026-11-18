extends Node2D
class_name DivingWildFish

# Tiny autonomous fish for the diving vertical slice. They wander on their
# own, notice the player, and flee unless Silas is concealing the approach.
var fish_name: StringName = &""
var swim_speed: float = 20.0
var capture_radius: float = 13.0
var flee_radius: float = 58.0
var catch_cooldown: float = 0.0
var max_health: float = 50.0
var health: float = 50.0
var defeated: bool = false
var selected_for_attack: bool = false
var _damage_flash: float = 0.0
# A rescued NPC may be trapped in place until the net battle is completed.
var trapped: bool = false
var region: Rect2 = Rect2(24, 35, 860, 430)
var home: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _heading: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0
var _t: float = 0.0
var _sprite: Sprite2D

func setup(kind: StringName, art: Texture2D, starting_position: Vector2, bounds: Rect2, seed_value: int, species: FishData = null) -> void:
	fish_name = kind
	position = starting_position
	home = starting_position
	region = bounds
	_rng.seed = seed_value
	# Larger, stronger species can withstand more damage before collapsing.
	max_health = maxf(30.0, species.stagger_resistance * 0.6) if species != null else 50.0
	health = max_health
	defeated = false
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
	if _sprite == null or defeated:
		return
	_damage_flash = maxf(0.0, _damage_flash - delta)
	_sprite.modulate = Color(1, 0.48, 0.46) if _damage_flash > 0.0 else Color.WHITE.lerp(Color(0.82, 0.82, 0.9), (1.0 - health_fraction()) * 0.42)
	catch_cooldown = maxf(0.0, catch_cooldown - delta)
	_t += delta
	if trapped:
		# Leave the fish at its burrow until the player reels it free. During
		# combat, DivingWorld moves the hooked fish along the attached line.
		_sprite.position.y = sin(_t * 2.2) * 0.7
		return
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

func health_fraction() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


func take_damage(amount: float) -> bool:
	if trapped or defeated or amount <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	_damage_flash = 0.18
	defeated = health <= 0.0
	queue_redraw()
	return defeated


func set_attack_target(active: bool) -> void:
	selected_for_attack = active
	queue_redraw()


func _draw() -> void:
	if not selected_for_attack or defeated:
		return
	# Five small pips anchored to the fish—not a full-screen HUD.
	var filled: int = ceili(health_fraction() * 5.0)
	for i in range(5):
		draw_circle(Vector2(-12.0 + float(i) * 6.0, -18.0), 1.8,
			Color("#f2c66c") if i < filled else Color(0.20, 0.31, 0.38, 0.85))


func is_targeted(world_mouse: Vector2, player_position: Vector2) -> bool:
	return not defeated and catch_cooldown <= 0.0 and world_mouse.distance_to(position) <= capture_radius + 7.0 and player_position.distance_to(position) <= 45.0

func get_display_name() -> String:
	return String(fish_name).capitalize()
