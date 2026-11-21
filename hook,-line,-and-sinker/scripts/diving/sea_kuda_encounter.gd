@tool
extends Node2D
class_name SeaKudaEncounter

# Second-NPC spatial encounter. StoryDirector owns flags/dialogue, World owns
# fish registration/combat, and this node owns only Kuda's hunting movement.
signal first_hook_dialogue_finished(fish: DivingWildFish)
signal recruited

enum Phase { DORMANT, CHASING, HOOK_DIALOGUE, REELING, CAUGHT_DIALOGUE, RECRUITED }

@export_group("Hunting Area")
@export var area_size: Vector2 = Vector2(210.0, 140.0):
	set(value):
		area_size = Vector2(maxf(80.0, value.x), maxf(80.0, value.y))
		queue_redraw()
@export var kuda_species: FishData = preload("res://resources/fish/kuda.tres")
@export var prey_species: FishData = preload("res://resources/fish/mullet.tres")
@export_range(0.1, 1.0, 0.05) var initial_health_ratio: float = 0.5

@export_group("Sprites")
# Individual encounter art sizes, independent of the shared species data.
@export_range(20.0, 72.0, 1.0, "suffix:px") var kuda_sprite_width: float = 44.0
@export_range(12.0, 56.0, 1.0, "suffix:px") var prey_sprite_width: float = 26.0

@export_group("Chase Speeds")
@export_range(35.0, 220.0, 1.0) var prey_speed: float = 90.0
@export_range(50.0, 280.0, 1.0) var kuda_speed: float = 126.0
@export_range(50.0, 320.0, 1.0) var burst_speed: float = 185.0
@export_range(0.1, 3.0, 0.1) var burst_interval: float = 1.65
@export_range(0.1, 1.0, 0.05) var burst_seconds: float = 0.38
@export_range(8.0, 40.0, 1.0) var bite_range: float = 12.0
@export_range(0.0, 12.0, 0.5) var bite_damage: float = 4.0

@export_group("Speech")
@export_range(40.0, 220.0, 1.0) var shout_range: float = 130.0
@export_range(2.0, 20.0, 0.5) var shout_cooldown: float = 9.0
@export var shout_text: String = "COME HERE! LEMME EAT YOU!"

var phase: Phase = Phase.DORMANT
var kuda: DivingWildFish
var prey: DivingWildFish

var _player: Player
var _story: SeaStoryDirector
var _spawn: Callable
var _unregister: Callable
var _is_open: Callable
var _burst_left: float = 0.0
var _burst_timer: float = 0.0
var _bite_timer: float = 0.0
var _prey_respawn_timer: float = 0.0
var _speech_timer: float = 2.0
var _prey_heading: Vector2 = Vector2.RIGHT


func _draw() -> void:
	if Engine.is_editor_hint():
		var area := Rect2(Vector2.ZERO, area_size)
		draw_rect(area, Color(0.98, 0.36, 0.35, 0.11), true)
		draw_rect(area, Color(1.0, 0.52, 0.37, 0.85), false, 1.0)
		draw_circle(area.size * 0.5, 3.0, Color(1.0, 0.7, 0.4, 0.85))


func configure(player: Player, story: SeaStoryDirector, spawn_fish: Callable,
		unregister_fish: Callable, open_water: Callable) -> void:
	_player = player
	_story = story
	_spawn = spawn_fish
	_unregister = unregister_fish
	_is_open = open_water
	if not _story.kuda_hook_dialogue_finished.is_connected(_on_hook_dialogue_finished):
		_story.kuda_hook_dialogue_finished.connect(_on_hook_dialogue_finished)
	if not _story.kuda_recruited.is_connected(_on_recruited):
		_story.kuda_recruited.connect(_on_recruited)


func can_start() -> bool:
	# The second introduction follows Silas's first shore transformation.
	return _story != null and _story.has_silas_flag(&"silas_surface_transformed") \
		and not _story.has_kuda_flag(&"Recruited")


func activate() -> bool:
	if phase != Phase.DORMANT or not can_start() or not _spawn.is_valid():
		return false
	var kuda_position: Vector2 = _find_open_position(Vector2(0.28, 0.52))
	var prey_position: Vector2 = _find_open_position(Vector2(0.76, 0.47))
	if not kuda_position.is_finite() or not prey_position.is_finite() \
			or kuda_position.distance_to(prey_position) < 24.0:
		push_warning("Kuda encounter: no open-water starting positions in hunting area.")
		return false
	kuda = _spawn.call(kuda_species, kuda_position, 71031, 0.0, 0.0, 0.0) as DivingWildFish
	prey = _spawn.call(prey_species, prey_position, 71032, 0.0, 0.0, 0.0) as DivingWildFish
	if not is_instance_valid(kuda) or not is_instance_valid(prey):
		end_dive()
		return false
	kuda.health = kuda.max_health * initial_health_ratio
	# Bigger art must also give the net a matching clickable/hittable radius.
	_set_sprite_width(kuda, kuda_sprite_width)
	_set_sprite_width(prey, prey_sprite_width)
	kuda.queue_redraw()
	_reset_chase()
	phase = Phase.CHASING
	return true


func _set_sprite_width(fish: DivingWildFish, width: float) -> void:
	if not is_instance_valid(fish):
		return
	var art: Sprite2D = fish.get_node_or_null("FishSprite") as Sprite2D
	if art == null or art.texture == null:
		return
	art.scale = Vector2.ONE * (width / maxf(float(art.texture.get_width()), 1.0))
	fish.capture_radius = maxf(fish.capture_radius, width * 0.42)


func _find_open_position(at: Vector2, distance_from_kuda: float = 0.0) -> Vector2:
	var offsets := [Vector2.ZERO, Vector2(0.0, -0.2), Vector2(-0.2, 0.0),
		Vector2(0.2, 0.2), Vector2(0.0, 0.2)]
	for offset in offsets:
		var uv: Vector2 = at + offset
		var in_area: Vector2 = Vector2(clampf(uv.x, 0.08, 0.92),
			clampf(uv.y, 0.08, 0.92)) * area_size
		var sea_point: Vector2 = (get_parent() as Node2D).to_local(to_global(in_area))
		if bool(_is_open.call(sea_point)) and (
				not is_instance_valid(kuda) or
				sea_point.distance_to(kuda.position) >= distance_from_kuda):
			return sea_point
	for y in range(1, 9):
		for x in range(1, 11):
			var candidate: Vector2 = (get_parent() as Node2D).to_local(
				to_global(Vector2(float(x) / 11.0 * area_size.x,
					float(y) / 9.0 * area_size.y)))
			if bool(_is_open.call(candidate)) and (
					not is_instance_valid(kuda) or
					candidate.distance_to(kuda.position) >= distance_from_kuda):
				return candidate
	return Vector2.INF


func controls_fish(fish: DivingWildFish) -> bool:
	return fish != null and phase != Phase.DORMANT and phase != Phase.RECRUITED \
		and (fish == kuda or fish == prey)


func protects_from_silas(fish: DivingWildFish) -> bool:
	# Silas won't interfere with a hunt, including by attacking the prey.
	return controls_fish(fish)


func on_net_hit(fish: DivingWildFish) -> bool:
	if fish != kuda or phase != Phase.CHASING:
		return false
	kuda.trapped = true
	if not _story.has_event(&"kuda_first_net_dialogue") \
			and _story.start_kuda_hook_dialogue():
		phase = Phase.HOOK_DIALOGUE
		_hide_hunting_bubble()
		return true
	phase = Phase.REELING
	_hide_hunting_bubble()
	return false


func _on_hook_dialogue_finished() -> void:
	if phase == Phase.HOOK_DIALOGUE and is_instance_valid(kuda):
		phase = Phase.REELING
		first_hook_dialogue_finished.emit(kuda)


func on_escape() -> void:
	if phase != Phase.REELING or not is_instance_valid(kuda):
		return
	kuda.trapped = false
	_reset_chase()
	phase = Phase.CHASING


func on_caught() -> bool:
	if phase != Phase.REELING or not is_instance_valid(kuda):
		return false
	phase = Phase.CAUGHT_DIALOGUE
	kuda.trapped = true
	_hide_hunting_bubble()
	if _story.start_kuda_caught_dialogue():
		return true
	# The NPC must never be silently converted to an inventory fish.
	push_warning("Kuda caught without DialogueUI; will retry the dialogue.")
	return true


func try_caught_dialogue_again() -> void:
	if phase == Phase.CAUGHT_DIALOGUE and not DialogueManager.is_active:
		_story.start_kuda_caught_dialogue()


func _on_recruited() -> void:
	if phase != Phase.CAUGHT_DIALOGUE:
		return
	phase = Phase.RECRUITED
	_hide_hunting_bubble()
	if is_instance_valid(kuda):
		_unregister.call(kuda)
		kuda.queue_free()
	kuda = null
	# Leave the prey as a normal wild fish after the encounter ends.
	prey = null
	recruited.emit()


func end_dive() -> void:
	_hide_hunting_bubble()
	for fish in [kuda, prey]:
		if is_instance_valid(fish):
			_unregister.call(fish)
			fish.queue_free()
	kuda = null
	prey = null
	phase = Phase.DORMANT


func step(delta: float) -> void:
	if phase == Phase.CAUGHT_DIALOGUE:
		try_caught_dialogue_again()
		return
	if phase != Phase.CHASING or not is_instance_valid(kuda):
		return
	if _player == null or not _player.swimming or DialogueManager.is_active:
		return
	# These two fish are excluded from DivingWorld's generic swim() loop.
	# Their net cooldowns must still advance, especially after Kuda escapes.
	kuda.catch_cooldown = maxf(0.0, kuda.catch_cooldown - delta)
	if is_instance_valid(prey):
		prey.catch_cooldown = maxf(0.0, prey.catch_cooldown - delta)
	if not is_instance_valid(prey):
		_prey_respawn_timer -= delta
		if _prey_respawn_timer <= 0.0:
			_respawn_prey()
		return
	_burst_timer -= delta
	_burst_left = maxf(0.0, _burst_left - delta)
	_bite_timer = maxf(0.0, _bite_timer - delta)
	_speech_timer -= delta
	if _burst_timer <= 0.0:
		_burst_timer = burst_interval
		_burst_left = burst_seconds
	var away: Vector2 = (prey.position - kuda.position).normalized()
	if away.is_zero_approx():
		away = Vector2.RIGHT
	# A touch of sideways movement lets Kuda overshoot and circle back.
	var sideways := Vector2(-away.y, away.x) * sin(Time.get_ticks_msec() * 0.002)
	var desired_prey: Vector2 = (away * 0.85 + sideways * 0.4).normalized()
	# Turn away from edges to create repeated, readable interception passes.
	var bounds := Rect2(position + Vector2(10.0, 10.0),
		area_size - Vector2(20.0, 20.0))
	var next_prey := prey.position + desired_prey * prey_speed * delta
	next_prey = next_prey.clamp(bounds.position, bounds.end)
	if next_prey.distance_squared_to(prey.position) < 1.0:
		desired_prey = (bounds.get_center() - prey.position).normalized()
		next_prey = prey.position + desired_prey * prey_speed * delta
	prey.position = _move_open(prey, next_prey, bounds)
	_face(prey, desired_prey)
	var kuda_direction: Vector2 = (prey.position - kuda.position).normalized()
	if not kuda_direction.is_zero_approx():
		var speed: float = burst_speed if _burst_left > 0.0 else kuda_speed
		kuda.position = _move_open(kuda, kuda.position + kuda_direction * speed * delta,
			bounds)
		_face(kuda, kuda_direction)
	if kuda.position.distance_to(prey.position) < bite_range and _bite_timer <= 0.0:
		prey.take_damage(bite_damage)
		_bite_timer = 0.8
		if prey.health <= 0.0:
			var defeated: DivingWildFish = prey
			prey = null
			_unregister.call(defeated)
			defeated.queue_free()
			_prey_respawn_timer = 1.3
	_update_shout()


func _move_open(fish: DivingWildFish, destination: Vector2, bounds: Rect2) -> Vector2:
	var next: Vector2 = destination.clamp(bounds.position, bounds.end)
	# Reuse the wild-fish collision slide instead of ignoring spline rock.
	return fish._avoid_solids(fish.position, next)


func _face(fish: DivingWildFish, heading: Vector2) -> void:
	var image: Sprite2D = fish.get_node_or_null("FishSprite") as Sprite2D
	if image != null:
		image.flip_h = heading.x < 0.0
		image.position.y = sin(Time.get_ticks_msec() * 0.008) * 1.0


func _respawn_prey() -> void:
	# Prefer a fresh prey well ahead of Kuda, so he must actually pursue it
	# instead of killing a replacement on the same frame it appears.
	var at: Vector2 = _find_open_position(Vector2(0.7, 0.5), 65.0)
	if not at.is_finite():
		at = _find_open_position(Vector2(0.7, 0.5))
	if not at.is_finite():
		_prey_respawn_timer = 1.0
		return
	prey = _spawn.call(prey_species, at, randi(), 0.0, 0.0, 0.0) as DivingWildFish
	_set_sprite_width(prey, prey_sprite_width)


func _reset_chase() -> void:
	_burst_timer = burst_interval
	_burst_left = 0.0
	_bite_timer = 0.8
	_speech_timer = 1.8


func _update_shout() -> void:
	if _speech_timer > 0.0 or not is_instance_valid(kuda) or _player == null:
		return
	if _player.position.distance_to(kuda.position) > shout_range:
		return
	if _story.show_kuda_chase_bubble(kuda, shout_text):
		_speech_timer = shout_cooldown


func _hide_hunting_bubble() -> void:
	if _story != null:
		_story.hide_kuda_chase_bubble()
