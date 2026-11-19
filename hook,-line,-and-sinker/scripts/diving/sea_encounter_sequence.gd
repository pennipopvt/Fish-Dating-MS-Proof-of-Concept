extends Node
class_name SeaEncounterSequence

# One-off first dive choreography only. StoryDirector owns progression
# flags/dialogue; DivingWorld owns the spawned fish registry and normal
# reel/parry/companion combat.
signal fish_remove_requested(fish: DivingWildFish)

@export_group("First Fish: Focus")
@export_range(0.0, 240.0, 1.0) var first_fish_focus_range: float = 110.0
@export_range(0.0, 140.0, 1.0) var min_tutorial_swim_distance: float = 50.0
@export_range(0.2, 6.0, 0.05) var fish_focus_hold_seconds: float = 1.15
@export_group("First Fish: Reel and Escape")
@export_range(50.0, 600.0, 1.0) var first_fish_escape_distance: float = 330.0
@export_range(0.1, 3.0, 0.05) var first_fish_escape_seconds: float = 0.85
@export_range(0.0, 180.0, 1.0) var follow_after_escape_distance: float = 75.0
@export_range(0.0, 180.0, 1.0) var silas_help_nearby_range: float = 108.0
@export_range(1.0, 30.0, 1.0) var tutorial_reel_per_scroll: float = 12.0
@export_range(10.0, 130.0, 1.0) var tutorial_break_distance: float = 44.0
@export_range(0.1, 3.0, 0.05) var tutorial_break_seconds: float = 0.7
@export_group("Silas Rescue")
@export_range(1.0, 30.0, 1.0) var rescue_reel_per_scroll: float = 13.0
@export_range(5.0, 80.0, 1.0) var rescue_finish_distance: float = 17.0

@export_group("Silas Surface Reveal")
@export var silas_land_scene: PackedScene = preload("res://prefabs/silas.tscn")
@export var silas_poof_texture: Texture2D = preload("res://sprites/characters/poof.png")
@export_range(0.1, 2.0, 0.05) var silas_surface_swim_seconds: float = 0.75
@export_range(0.1, 1.2, 0.05) var silas_surface_jump_seconds: float = 0.48
var _silas_surface_scene_running: bool = false

var _player: Player
var _story: SeaStoryDirector
var _net: DivingNetProjectile
var _silas: SeaNPC
var _cue: SeaTutorialCue
var _tutorial_fish: DivingWildFish
var _silas_trap: DivingWildFish
var _silas_home: Vector2
var _tutorial_swim_origin: Vector2
var _fish_focus_locked: bool = false
var _fish_focus_timer: float = 0.0
var _first_fish_escape_finished: bool = false
var _help_reveal_x: float = -INF
var _scripted_reel_mode: StringName = &""
var _scripted_reel_scrolls: int = 0
var _scripted_break_elapsed: float = 0.0

# Read-only access for the world input router and developer panel.
var tutorial_fish: DivingWildFish:
	get:
		return _tutorial_fish

var silas_trap: DivingWildFish:
	get:
		return _silas_trap

var first_fish_escape_finished: bool:
	get:
		return _first_fish_escape_finished

var help_reveal_x: float:
	get:
		return _help_reveal_x

var reel_mode: StringName:
	get:
		return _scripted_reel_mode

var reel_scrolls: int:
	get:
		return _scripted_reel_scrolls


func configure(player: Player, story: SeaStoryDirector, net: DivingNetProjectile,
		silas: SeaNPC, cue: SeaTutorialCue) -> void:
	_player = player
	_story = story
	_net = net
	_silas = silas
	_cue = cue
	_silas_home = silas.position


func register_tutorial_fish(fish: DivingWildFish) -> void:
	_tutorial_fish = fish
	fish.trapped = not _story.has_event(&"line_broken")


func register_silas_trap(fish: DivingWildFish) -> void:
	_silas_trap = fish


func on_dive_entered() -> void:
	_tutorial_swim_origin = _player.position
	_story.on_dive_entered()


func step(delta: float) -> void:
	# Preserve the original order of scene beat checks.
	if _cue != null and _cue.current_action == &"" \
			and not _story.has_event(&"fish_focus_seen") \
			and not _story.has_event(&"first_cast") \
			and not _story.has_event(&"line_broken"):
		_story.on_dive_entered()
	_check_first_fish_focus(delta)
	_advance_scripted_break(delta)
	if _first_fish_escape_finished and _story.has_event(&"line_broken") \
			and not _story.has_event(&"penni_fish_reaction"):
		_story.on_first_fish_escaped()
	_check_escape_followup()


# True means this was an encounter-specific net hit; false means
# DivingWorld should continue with ordinary DivingCombat.
func handle_fish_hit(fish: DivingWildFish) -> bool:
	if _story.wants_scripted_hook(fish, _tutorial_fish):
		_start_tutorial_reel(fish)
		_story.on_scripted_hook()
		return true
	if fish == _silas_trap:
		if not _story.can_net_silas():
			_net.retract()
			return true
		_start_silas_rescue()
		return true
	return false


func on_cast_started() -> void:
	if not _story.has_event(&"first_cast") and not _story.has_event(&"line_broken"):
		_release_first_fish_focus()
		_story.on_first_cast()


func reel_if_scripted() -> bool:
	if _net.is_latched() and (_scripted_reel_mode == &"tutorial_reel" \
			or _scripted_reel_mode == &"silas_rescue"):
		_reel_scripted_target()
		return true
	return _scripted_reel_mode == &"tutorial_break"


func cancel_if_scripted() -> bool:
	if _scripted_reel_mode == &"":
		return false
	_cancel_scripted_reel()
	return true


# First-shore story choreography, not part of generic transition or NPC combat.
# Markers and art are intentionally editor-facing.
func leave_sea() -> void:
	_release_first_fish_focus()
	cancel_if_scripted()


func finish_silas_rescue_from_combat() -> void:
	# Compatibility for an already-running normal combat on the trap.
	_finish_silas_rescue()


func restore_silas_position() -> void:
	_silas.position = _silas_home
	if is_instance_valid(_silas_trap):
		_silas_trap.position = _silas_home


func _check_first_fish_focus(delta: float) -> void:
	if _fish_focus_locked:
		_fish_focus_timer -= delta
		if _fish_focus_timer <= 0.0:
			_release_first_fish_focus()
		return
	if not _story.wants_first_fish_focus():
		return
	if not is_instance_valid(_tutorial_fish) or _player.busy:
		return
	if DialogueManager.is_active or GameManager.is_modal_ui_open() or _net.is_busy():
		return
	if _player.position.distance_to(_tutorial_swim_origin) < min_tutorial_swim_distance:
		return
	if _player.position.distance_to(_tutorial_fish.position) > first_fish_focus_range:
		return
	# The story only confirms the beat after a real visible sprite is shown.
	if not _story.on_first_fish_seen():
		return
	_fish_focus_locked = true
	_fish_focus_timer = fish_focus_hold_seconds
	_player.busy = true


func _release_first_fish_focus() -> void:
	if not _fish_focus_locked:
		return
	_fish_focus_locked = false
	_fish_focus_timer = 0.0
	_player.busy = false


func _check_escape_followup() -> void:
	# Penni's first personal reaction completes before the next voice cue.
	if DialogueManager.is_active:
		return
	if _story.has_event(&"help_called"):
		return
	# Preferred storyboard: first fish flees, then Penni follows it left.
	if _first_fish_escape_finished and _player.position.x <= _help_reveal_x:
		_story.on_followed_escape()
	# Recovery path: the sea is explorable, so players can simply swim
	# around the first fish. Silas should still call as they approach.
	if not _story.has_event(&"help_called") \
			and _player.position.distance_to(_silas.position) <= silas_help_nearby_range:
		_story.on_followed_escape(true)


func _start_first_fish_escape() -> void:
	_help_reveal_x = _player.position.x - follow_after_escape_distance
	_first_fish_escape_finished = false
	if not is_instance_valid(_tutorial_fish):
		_first_fish_escape_finished = true
		return
	var fish: DivingWildFish = _tutorial_fish
	# Penni must also swim a little past the fish's old position.
	_help_reveal_x = minf(_help_reveal_x, fish.position.x - 20.0)
	_tutorial_fish = null
	fish_remove_requested.emit(fish)
	# Remove it from normal fish simulation / catch candidates so the
	# escape tween is the sole owner of its movement.
	fish.trapped = true
	var graphic: Sprite2D = fish.get_node_or_null("FishSprite") as Sprite2D
	if graphic != null:
		graphic.flip_h = true
	fish.rotation = 0.0
	var dash: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dash.tween_property(fish, "position",
		fish.position + Vector2(-first_fish_escape_distance, -12.0),
		first_fish_escape_seconds)
	dash.tween_callback(_finish_first_fish_escape.bind(fish))


func _finish_first_fish_escape(fish: DivingWildFish) -> void:
	if is_instance_valid(fish):
		fish.queue_free()
	_first_fish_escape_finished = true
	_story.on_first_fish_escaped()


# Real net movement for the first tutorial fish, then a visibly escalating
# tension break near Penni. Silas's scripted rescue shares net retrieval but
# deliberately has NO outward pulling or tension/resistance.
func _start_tutorial_reel(fish: DivingWildFish) -> void:
	_scripted_reel_mode = &"tutorial_reel"
	_scripted_reel_scrolls = 0
	_scripted_break_elapsed = 0.0
	fish.trapped = true
	_player.busy = true
	_net.set_line_state(0.06)
	print("[SEA NET] First fish hooked; scroll to reel it closer")


func _start_silas_rescue() -> void:
	_scripted_reel_mode = &"silas_rescue"
	_scripted_reel_scrolls = 0
	_player.busy = true
	_net.set_line_state(0.0)
	_story.on_silas_rescue_started()
	print("[SEA NET] Silas rescue hooked; no fighting or pullback")


func _reel_scripted_target() -> void:
	var fish: DivingWildFish = _tutorial_fish if _scripted_reel_mode == &"tutorial_reel" else _silas_trap
	if not is_instance_valid(fish):
		_cancel_scripted_reel()
		return
	_scripted_reel_scrolls += 1
	var offset: Vector2 = fish.position - _player.position
	var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.01 else Vector2.LEFT
	var amount: float = rescue_reel_per_scroll if _scripted_reel_mode == &"silas_rescue" else tutorial_reel_per_scroll
	var remaining: float = maxf(rescue_finish_distance, offset.length() - amount)
	fish.position = _player.position + direction * remaining
	if _scripted_reel_mode == &"silas_rescue":
		_silas.position = fish.position
		_net.set_line_state(0.0)
		if remaining <= rescue_finish_distance + 0.1:
			_finish_silas_rescue()
		return
	_net.set_line_state(minf(0.48, 0.06 + float(_scripted_reel_scrolls) * 0.065))
	print("[SEA NET] Tutorial reel %d: remaining %.1f px" % [_scripted_reel_scrolls, remaining])
	# Several genuine inward reels must happen before the authored panic.
	if (_scripted_reel_scrolls >= 3 and remaining <= tutorial_break_distance) \
			or _scripted_reel_scrolls >= 8:
		_scripted_reel_mode = &"tutorial_break"
		_scripted_break_elapsed = 0.0
		print("[SEA NET] Fish panics as it gets close; tension surging")


func _advance_scripted_break(delta: float) -> void:
	if _scripted_reel_mode != &"tutorial_break":
		return
	_scripted_break_elapsed += delta
	var ratio: float = clampf(_scripted_break_elapsed / tutorial_break_seconds, 0.0, 1.0)
	_net.set_line_state(lerpf(0.55, 1.0, ratio))
	if is_instance_valid(_tutorial_fish):
		_tutorial_fish.position += Vector2(-8.0 * delta, -2.0 * delta)
	if ratio >= 1.0:
		_scripted_reel_mode = &""
		_scripted_reel_scrolls = 0
		_player.busy = false
		_story.consume_first_reel()
		_net.reset_net()
		_start_first_fish_escape()
		print("[SEA NET] Scripted tension break; first fish escapes left")


func _finish_silas_rescue() -> void:
	_scripted_reel_mode = &""
	_scripted_reel_scrolls = 0
	_player.busy = false
	_net.reset_net()
	var fish: DivingWildFish = _silas_trap
	_silas_trap = null
	if is_instance_valid(fish):
		fish_remove_requested.emit(fish)
		fish.queue_free()
	_story.on_silas_rescued()
	print("[SEA NET] Silas rescued without resistance")


func _cancel_scripted_reel() -> void:
	var was_rescue: bool = _scripted_reel_mode == &"silas_rescue"
	var was_tutorial: bool = _scripted_reel_mode == &"tutorial_reel" \
		or _scripted_reel_mode == &"tutorial_break"
	_scripted_reel_mode = &""
	_scripted_reel_scrolls = 0
	_player.busy = false
	_net.reset_net()
	if was_rescue:
		_silas.position = _silas_home
		if is_instance_valid(_silas_trap):
			_silas_trap.position = _silas_home
		_story.on_silas_rescue_cancelled()
	elif was_tutorial:
		_story.on_tutorial_hook_cancelled()
	print("[SEA NET] Scripted reel cancelled")




# Called after SeaDiveTransition has restored walking and land portraits.
# Silas swims to the same dock, leaps after Penni, then changes actor on poof.

func play_silas_surface_reveal() -> void:
	if _silas_surface_scene_running or not _story.begin_silas_surface_reveal():
		return
	_silas_surface_scene_running = true
	_player.busy = true
	_silas.following = false
	var world: Node2D = _player.get_parent() as Node2D
	var approach: Marker2D = get_parent().get_node("Points/SilasSurfaceApproach") as Marker2D
	var dock_wait: Marker2D = get_parent().get_node("Points/SilasDockWait") as Marker2D

	# Visibly catch up with Penni at the waterline, then leap onto the dock.
	var swim: Tween = create_tween()
	swim.tween_property(_silas, "global_position", approach.global_position,
		silas_surface_swim_seconds).set_trans(Tween.TRANS_SINE)
	await swim.finished
	var jump_from: Vector2 = _silas.global_position
	var jump_to: Vector2 = dock_wait.global_position + Vector2(-12.0, 0.0)
	var jump: Tween = create_tween()
	jump.tween_method(
		_move_silas_surface_jump.bind(jump_from, jump_to),
		0.0, 1.0, silas_surface_jump_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await jump.finished

	_story.start_silas_surface_warning()
	await _story.silas_surface_warning_finished
	# Use the existing poof sprite and existing land NPC scene.
	var effect: AnimatedSprite2D = _make_silas_poof(world, dock_wait.global_position)
	await get_tree().create_timer(0.17).timeout
	_silas.hide()
	var land_actor: NPCInteractable = _spawn_silas_on_dock(world, dock_wait.global_position)
	await get_tree().create_timer(0.42).timeout
	if is_instance_valid(effect):
		effect.queue_free()
	if land_actor != null:
		land_actor.show()
	_story.on_silas_surface_transformed()
	await _story.silas_surface_reveal_finished
	_player.busy = false
	_silas_surface_scene_running = false


func _move_silas_surface_jump(t: float, start: Vector2, destination: Vector2) -> void:
	_silas.global_position = start.lerp(destination, t) + Vector2(0.0, -22.0 * sin(PI * t))


func _spawn_silas_on_dock(world: Node2D, at: Vector2) -> NPCInteractable:
	var existing: NPCInteractable = world.get_node_or_null("SilasDockActor") as NPCInteractable
	if existing != null:
		return existing
	if silas_land_scene == null:
		push_warning("Silas's land NPC scene is missing.")
		return null
	var actor: NPCInteractable = silas_land_scene.instantiate() as NPCInteractable
	if actor == null:
		push_warning("Silas's land scene must use the existing NPCInteractable.")
		return null
	actor.name = "SilasDockActor"
	actor.visible = false
	world.add_child(actor)
	actor.global_position = at
	actor.z_index = 6
	# Waiting is NOT recruitment: prevent the old post-catch romance/recruitment
	# dialogue from opening until a dock interaction is actually designed.
	actor.monitoring = false
	actor.monitorable = false
	actor.collision_layer = 0
	actor.collision_mask = 0
	var collision: CollisionShape2D = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.set_deferred("disabled", true)
	var prompt: InteractPrompt = actor.get_node_or_null("InteractPrompt") as InteractPrompt
	if prompt != null:
		prompt.pop_out()
	return actor


func _make_silas_poof(world: Node2D, at: Vector2) -> AnimatedSprite2D:
	var effect: AnimatedSprite2D = AnimatedSprite2D.new()
	effect.name = "SilasSurfacePoof"
	effect.z_index = 12
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Interpret a strip of square frames if the source art is a sprite sheet.
	# A single square image works as a one-frame effect without assumptions.
	var frames: SpriteFrames = SpriteFrames.new()
	frames.add_animation(&"poof")
	frames.set_animation_loop(&"poof", false)
	frames.set_animation_speed(&"poof", 12.0)
	if silas_poof_texture != null:
		var width: int = silas_poof_texture.get_width()
		var height: int = silas_poof_texture.get_height()
		var horizontal: bool = width > height and width % height == 0
		var vertical: bool = height > width and height % width == 0
		var count: int = int(width / height) if horizontal else (int(height / width) if vertical else 1)
		for index in range(count):
			var frame: AtlasTexture = AtlasTexture.new()
			frame.atlas = silas_poof_texture
			var source_rect: Rect2 = Rect2(0.0, 0.0, width, height)
			if horizontal:
				source_rect = Rect2(index * height, 0, height, height)
			elif vertical:
				source_rect = Rect2(0, index * width, width, width)
			frame.region = source_rect
			frames.add_frame(&"poof", frame)
	effect.sprite_frames = frames
	world.add_child(effect)
	effect.global_position = at + Vector2(0.0, -13.0)
	if frames.get_frame_count(&"poof") > 0:
		effect.play(&"poof")
	return effect
