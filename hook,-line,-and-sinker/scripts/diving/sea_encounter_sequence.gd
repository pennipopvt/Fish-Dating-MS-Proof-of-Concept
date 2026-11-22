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
@export_range(0.1, 1.0, 0.05) var townhouse_fade_seconds: float = 0.35
var _silas_surface_scene_running: bool = false
# Injected by SeaDiveTransition: the same presentation handles the school.
var _surface_presentation: SeaPartyEntrance

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


func set_surface_presentation(presentation: SeaPartyEntrance) -> void:
	_surface_presentation = presentation
	# Preserve the artist-editable Silas scene override in the shared actor
	# factory, so first-return and future party exits show the same artwork.
	if silas_land_scene != null and _story != null:
		_surface_presentation.register_land_scene(_story.silas_data.npc_id, silas_land_scene)


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

func play_silas_surface_reveal(from_first_land_care: bool = false) -> void:
	if _silas_surface_scene_running or not _story.begin_silas_surface_reveal():
		return
	_silas_surface_scene_running = true
	_player.busy = true
	_silas.following = false
	var world: Node2D = _player.get_parent() as Node2D
	var approach: Marker2D = get_parent().get_node("Points/SilasSurfaceApproach") as Marker2D
	var dock_wait: Marker2D = get_parent().get_node("Points/SilasDockWait") as Marker2D

	# Stage the real human art invisibly FIRST. Its feet align to the dock
	# marker; the fish swims/jumps to that sprite's visual center (not the
	# marker), so fish, poof and human cannot appear at different positions.
	# Use the exact same non-interactive temporary actor/feet alignment as
	# ordinary party exits. Silas's special story sequence stays here.
	var temporary_actor: Node2D = _surface_presentation.stage_surface_actor(
		_story.silas_data, dock_wait.global_position, "SilasDockActor"
	)
	var land_actor: NPCInteractable = temporary_actor as NPCInteractable
	if land_actor == null:
		push_warning("Silas's surface actor must use NPCInteractable.")
		if is_instance_valid(temporary_actor):
			temporary_actor.queue_free()
	var human_center: Vector2 = _surface_presentation.surface_visual_center(land_actor) \
		if land_actor != null else dock_wait.global_position
	await _surface_presentation.swim_and_jump_to_surface(
		_silas, approach.global_position, human_center
	)

	_story.start_silas_surface_warning(from_first_land_care)
	await _story.silas_surface_warning_finished
	if land_actor != null:
		await _surface_presentation.transform_surface_fish(_silas, land_actor)
	else:
		_silas.hide()
	_story.on_silas_surface_transformed()
	await _story.silas_surface_reveal_finished
	# Reuse the existing townhouse choreography for normal returns and
	# blackouts; the latter leaves its actor for shared surface cleanup.
	await _bring_silas_to_townhouse(land_actor, true)
	_player.busy = false
	_silas_surface_scene_running = false


func play_silas_blackout_townhouse_arrival(land_actor: NPCInteractable) -> void:
	if land_actor == null:
		return
	await _bring_silas_to_townhouse(land_actor, false)


func _bring_silas_to_townhouse(land_actor: NPCInteractable,
		cleanup_here: bool) -> void:
	var world: Node2D = _player.get_parent() as Node2D
	var dock_wait: Marker2D = get_parent().get_node("Points/SilasDockWait") as Marker2D
	var travel := ScreenFade.new()
	get_tree().root.add_child(travel)
	await travel.fade_to(1.0, townhouse_fade_seconds)
	var player_spot: Marker2D = world.get_node("TownhouseArrival/PlayerSpot") as Marker2D
	var silas_spot: Marker2D = world.get_node("TownhouseArrival/SilasSpot") as Marker2D
	_player.global_position = player_spot.global_position
	_player.animator.play(&"idle_r")
	var camera: Camera2D = _player.get_node("Camera2D") as Camera2D
	camera.position = Vector2.ZERO
	camera.reset_smoothing()
	camera.force_update_scroll()
	if is_instance_valid(land_actor):
		land_actor.global_position = silas_spot.global_position + (
			land_actor.global_position - dock_wait.global_position)
	await travel.fade_to(0.0, townhouse_fade_seconds)
	_story.start_silas_townhouse_arrival()
	await _story.silas_townhouse_dialogue_finished
	if cleanup_here:
		await travel.fade_to(1.0, townhouse_fade_seconds)
	var assigned: bool = RecruitmentHandler.assign_home(_story.silas_data)
	if not assigned:
		push_warning("Silas accepted the room, but no townhouse door was available.")
	if cleanup_here:
		if is_instance_valid(land_actor):
			land_actor.queue_free()
		await travel.fade_to(0.0, townhouse_fade_seconds)
	travel.queue_free()
	_story.complete_silas_townhouse_arrival()


