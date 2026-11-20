extends Node2D
class_name DivingWildFish

# Tiny autonomous fish for the diving vertical slice. They wander on their
# own, notice the player, and flee unless Silas is concealing the approach.
var fish_name: StringName = &""
var swim_speed: float = 20.0
var capture_radius: float = 13.0
var flee_radius: float = 58.0
# Configured by the editor-placeable DivingFishSpawn instance.
# Unlike net/combat rules these affect only free-swimming behavior.
var preferred_player_distance: float = 0.0
var flee_speed: float = 0.0
var catch_cooldown: float = 0.0
# A rescued NPC may be trapped in place until the net battle is completed.
var trapped: bool = false
# Companion auto-battle (DivingCompanionBattle). Damage lasts for the session.
var max_health: float = 30.0
var health: float = 30.0
# Held in place while the companion fights it.
var battling: bool = false:
	set(value):
		battling = value
		queue_redraw()
var _hit_flash: float = 0.0
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
	catch_cooldown = maxf(0.0, catch_cooldown - delta)
	_t += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		_sprite.modulate = Color(1.0, 0.55, 0.5) if _hit_flash > 0.0 else Color.WHITE
	if battling:
		# Locked in the fight with the companion: shake in place.
		_sprite.position = Vector2(sin(_t * 31.0) * 0.8, sin(_t * 2.2) * 0.7)
		return
	if trapped:
		# Leave the fish at its burrow until the player reels it free. During
		# combat, DivingWorld moves the hooked fish along the attached line.
		_sprite.position.y = sin(_t * 2.2) * 0.7
		return
	_wander_timer -= delta
	var distance: float = position.distance_to(player_position)
	var danger_distance: float = 18.0 if concealed else maxf(flee_radius, preferred_player_distance)
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
	if not concealed and distance < danger_distance and preferred_player_distance > 0.0:
		# Normal free swimming can be caught from net range, but Penni
		# can't simply overtake wary fish at 78px/s. No teleport or
		# arbitrary minimum net-cast distance is introduced.
		var retreat: float = flee_speed
		if distance > preferred_player_distance:
			retreat *= 0.82
		speed = maxf(speed, retreat)
	_sprite.position.x = 0.0
	position += direction * speed * delta
	position.x = clampf(position.x, region.position.x + 12.0, region.end.x - 12.0)
	position.y = clampf(position.y, region.position.y + 12.0, region.end.y - 12.0)
	_sprite.flip_h = direction.x < -0.01
	_sprite.position.y = sin(_t * 3.2 + float(_rng.seed % 10)) * 1.4
	rotation = clampf(direction.y * 0.15, -0.20, 0.20)

func set_max_health(value: float) -> void:
	max_health = maxf(value, 1.0)
	health = max_health
	queue_redraw()


func health_ratio() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	_hit_flash = 0.12
	queue_redraw()


func _draw() -> void:
	# Health bar only once the fish has been hurt or is being fought.
	if battling or health < max_health:
		DivingCompanionBattle.draw_health_bar(self, Vector2(0.0, -13.0), health_ratio())


func is_targeted(world_mouse: Vector2, player_position: Vector2) -> bool:
	return catch_cooldown <= 0.0 and world_mouse.distance_to(position) <= capture_radius + 7.0 and player_position.distance_to(position) <= 45.0

func get_display_name() -> String:
	return String(fish_name).capitalize()
