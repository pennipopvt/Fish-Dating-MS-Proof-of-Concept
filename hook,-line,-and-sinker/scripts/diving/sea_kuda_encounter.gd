@tool
extends Node2D
class_name SeaKudaEncounter

# Kuda's encounter owns his hunting, recruitment and first shore introduction.
# StoryDirector owns flags/dialogue; World owns fish registration/combat.
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

@export_group("Chase Steering")
# Keep Kuda's heading through the prey rather than switching directions
# every frame when their centers overlap.
@export_range(0.15, 1.2, 0.05, "suffix:s") var attack_pass_seconds: float = 0.4
@export_range(10.0, 40.0, 1.0, "suffix:px") var attack_pass_distance: float = 21.0
@export_range(0.5, 10.0, 0.25) var hunter_turn_response: float = 4.0
@export_range(0.5, 10.0, 0.25) var prey_turn_response: float = 3.0
@export_range(8.0, 60.0, 1.0, "suffix:px") var edge_steering_margin: float = 24.0

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
var _hunter_heading: Vector2 = Vector2.RIGHT
var _attack_pass_heading: Vector2 = Vector2.RIGHT
var _attack_pass_remaining: float = 0.0


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


@export_group("First Townhouse Arrival")
@export_range(0.1, 1.0, 0.05) var townhouse_fade_seconds: float = 0.35

# Called only after the shared surface presentation has transformed the school.
# The surface animator supplies temporary human actors; this encounter checks
# that Kuda ACTUALLY reached shore before starting his one-time conversation.
func play_first_surface_reveal(surface_actors: Array[Node2D]) -> void:
	if _story == null or not _story.can_begin_kuda_surface_reveal():
		return
	var kuda_actor: NPCInteractable = null
	for actor in surface_actors:
		var guest: NPCInteractable = actor as NPCInteractable
		if is_instance_valid(guest) and guest.visible and guest.npc != null \
				and guest.npc.npc_id == _story.kuda_data.npc_id:
			kuda_actor = guest
			break
	if kuda_actor == null:
		return
	# Keep the visible human actor on the dock until the dialogue ends.
	if not _story.start_kuda_surface_reveal():
		return
	await _story.kuda_surface_reveal_finished
	# Mirror Silas's first return: after seeing his human form on the dock,
	# Penni shows Kuda the townhouse BEFORE he is assigned a room.
	var world: Node2D = _player.get_parent() as Node2D
	var player_spot: Marker2D = world.get_node("TownhouseArrival/PlayerSpot") as Marker2D
	var kuda_spot: Marker2D = world.get_node("TownhouseArrival/KudaSpot") as Marker2D
	var travel := ScreenFade.new()
	get_tree().root.add_child(travel)
	await travel.fade_to(1.0, townhouse_fade_seconds)
	_player.global_position = player_spot.global_position
	_player.animator.play(&"idle_r")
	var camera: Camera2D = _player.get_node("Camera2D") as Camera2D
	camera.position = Vector2.ZERO
	camera.reset_smoothing()
	camera.force_update_scroll()
	NPCTemporaryActor.place_feet(kuda_actor, kuda_spot.global_position)
	await travel.fade_to(0.0, townhouse_fade_seconds)
	_story.start_kuda_townhouse_arrival()
	await _story.kuda_townhouse_dialogue_finished
	await travel.fade_to(1.0, townhouse_fade_seconds)
	var assigned: bool = RecruitmentHandler.assign_home(_story.kuda_data)
	if not assigned:
		push_warning("Kuda accepted the room, but no townhouse door was available.")
	else:
		_story.complete_kuda_townhouse_arrival()
	# The common surface transition owns temporary actor cleanup.
	await travel.fade_to(0.0, townhouse_fade_seconds)
	travel.queue_free()


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
	# These two fish do not use DivingWildFish.swim(), so handle net
	# cooldowns here as well as the chase itself.
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
	var bounds := Rect2(position + Vector2(10.0, 10.0),
		area_size - Vector2(20.0, 20.0))
	_steer_prey(delta, bounds)
	_steer_kuda(delta, bounds)
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


# Prey steers gradually rather than snapping directly opposite Kuda's
# instantaneous position. Edge recovery preserves the chase in its area.
func _steer_prey(delta: float, bounds: Rect2) -> void:
	var flee: Vector2 = prey.position - kuda.position
	if flee.length_squared() < 36.0:
		flee = _prey_heading
	var desired: Vector2 = flee.normalized()
	var near_edge: bool = (
		prey.position.x < bounds.position.x + edge_steering_margin
		or prey.position.x > bounds.end.x - edge_steering_margin
		or prey.position.y < bounds.position.y + edge_steering_margin
		or prey.position.y > bounds.end.y - edge_steering_margin
	)
	if near_edge:
		var center: Vector2 = (bounds.get_center() - prey.position).normalized()
		desired = (desired * 0.45 + center * 0.85).normalized()
	_prey_heading = _turn_towards(_prey_heading, desired, prey_turn_response * delta)
	var next: Vector2 = prey.position + _prey_heading * prey_speed * delta
	var prior: Vector2 = prey.position
	prey.position = _move_open(prey, next, bounds)
	if prey.position.distance_squared_to(prior) < 0.25:
		_prey_heading = _turn_towards(_prey_heading,
			(bounds.get_center() - prey.position).normalized(),
			prey_turn_response * delta * 2.0)
	_face(prey, _prey_heading)


# A close-range encounter starts a committed lunge THROUGH the prey.
# Hunting resumes only after the pass, even if Kuda has crossed the target.
# This removes the per-frame left/right flipping at overlapping positions.
func _steer_kuda(delta: float, bounds: Rect2) -> void:
	var to_prey: Vector2 = prey.position - kuda.position
	if _attack_pass_remaining <= 0.0 and (
			to_prey.length() <= attack_pass_distance):
		_attack_pass_remaining = attack_pass_seconds
		_attack_pass_heading = _hunter_heading
		if _attack_pass_heading.length_squared() < 0.01:
			_attack_pass_heading = to_prey.normalized()
		if _attack_pass_heading.length_squared() < 0.01:
			_attack_pass_heading = Vector2.RIGHT
	if _attack_pass_remaining > 0.0:
		_hunter_heading = _attack_pass_heading
		_attack_pass_remaining = maxf(0.0, _attack_pass_remaining - delta)
	else:
		# Lead the fleeing fish a little, but keep a continuous turning arc.
		var aim: Vector2 = prey.position + _prey_heading * 9.0 - kuda.position
		if aim.length_squared() > 0.01:
			_hunter_heading = _turn_towards(
				_hunter_heading, aim.normalized(), hunter_turn_response * delta)
	var speed: float = burst_speed if _attack_pass_remaining > 0.0 \
		or _burst_left > 0.0 else kuda_speed
	kuda.position = _move_open(
		kuda, kuda.position + _hunter_heading * speed * delta, bounds)
	_face(kuda, _hunter_heading)


func _turn_towards(previous: Vector2, wanted: Vector2, amount: float) -> Vector2:
	if wanted.length_squared() < 0.001:
		return previous
	if previous.length_squared() < 0.001:
		return wanted.normalized()
	var steered: Vector2 = previous.lerp(wanted, clampf(amount, 0.0, 1.0))
	return steered.normalized() if steered.length_squared() > 0.001 else previous


func _move_open(fish: DivingWildFish, destination: Vector2, bounds: Rect2) -> Vector2:
	var next: Vector2 = destination.clamp(bounds.position, bounds.end)
	# Reuse the wild-fish collision slide instead of ignoring spline rock.
	return fish._avoid_solids(fish.position, next)


func _face(fish: DivingWildFish, heading: Vector2) -> void:
	var image: Sprite2D = fish.get_node_or_null("FishSprite") as Sprite2D
	if image != null:
		# Keep the previous facing while moving mostly vertically.
		if heading.x < -0.25:
			image.flip_h = true
		elif heading.x > 0.25:
			image.flip_h = false
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
	_reset_chase()


func _reset_chase() -> void:
	_burst_timer = burst_interval
	_burst_left = 0.0
	_bite_timer = 0.8
	_speech_timer = 1.8
	_attack_pass_remaining = 0.0
	if is_instance_valid(kuda) and is_instance_valid(prey):
		var direction: Vector2 = (prey.position - kuda.position).normalized()
		_hunter_heading = direction if direction.length_squared() > 0.001 else Vector2.RIGHT
		_prey_heading = _hunter_heading
	else:
		_hunter_heading = Vector2.RIGHT
		_prey_heading = Vector2.RIGHT
	_attack_pass_heading = _hunter_heading


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
