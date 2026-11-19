extends Node2D
class_name DivingWorld

# Sea is an editable piece of the existing World. Only orchestration belongs
# here: fish/net/combat are separate reusable nodes; one-time beats belong to
# StoryDirector. We never create a second Player or Camera2D.
signal surface_requested

const SEA_TOP: float = 154.0
const SURFACE_REACH: float = 44.0
# First encounter: only lock movement when the fish is close enough to cast.
const FIRST_FISH_FOCUS_RANGE: float = 110.0
const MIN_TUTORIAL_SWIM_DISTANCE: float = 50.0
# Safety release: a tutorial must never leave the player unable to move.
const FISH_FOCUS_HOLD_SECONDS: float = 1.15
# Only the first storyboard fish bolts away on the forced line break.
const FIRST_FISH_ESCAPE_DISTANCE: float = 330.0
const FIRST_FISH_ESCAPE_SECONDS: float = 0.85
const FOLLOW_AFTER_ESCAPE_DISTANCE: float = 75.0
const SILAS_FISH: FishData = preload("res://resources/fish/silas.tres")
const WILD_FISH_SCRIPT = preload("res://scripts/diving/wild_fish.gd")

# Inspector texture slots remain editable even though the small cue is
# created at runtime. No new PackedScene or imported file is required.
@export var movement_tutorial_sprite: Texture2D
@export var cast_tutorial_sprite: Texture2D
@export var reel_tutorial_sprite: Texture2D

@onready var _guide: SeaEditorGuide = $EditorGuide
@onready var _entry: Marker2D = $Points/Entry
@onready var _exit: Marker2D = $Points/SurfaceExit
@onready var _spawns: Node2D = $FishSpawns
@onready var _actors: Node2D = $FishActors
@onready var _story: SeaStoryDirector = $StoryDirector
@onready var _net: DivingNetProjectile = $NetProjectile
@onready var _combat: DivingCombat = $Combat
@onready var _battle: DivingCompanionBattle = $CompanionBattle
@onready var _silas: SeaNPC = $NPCs/Silas

var _player: Player
var _camera: Camera2D
var _cue: SeaTutorialCue
var _wild_fish: Array[DivingWildFish] = []
var _fish_data: Dictionary = {}
var _tutorial_fish: DivingWildFish
var _silas_trap: DivingWildFish
var _silas_home: Vector2
var _tutorial_swim_origin: Vector2
var _fish_focus_locked: bool = false
var _fish_focus_timer: float = 0.0
var _first_fish_escape_finished: bool = false
var _help_reveal_x: float = -INF


func _ready() -> void:
	_player = get_parent().get_node_or_null("Player") as Player
	if _player != null:
		_camera = _player.get_node_or_null("Camera2D") as Camera2D
	_install_tutorial_cue()
	_silas_home = _silas.position
	_net.fish_hit.connect(_on_fish_hit)
	_combat.finished.connect(_on_combat_finished)
	_story.silas_following_started.connect(_on_silas_following_started)
	_spawn_editor_fish()
	_make_silas_trap()
	set_process(true)


# Create exactly one lightweight Sprite2D after the World/Camera nodes exist.
# This never participates in World scene parsing, so a missing tutorial
# scene/PNG cannot take down the main game.
func _install_tutorial_cue() -> void:
	if _camera == null:
		push_warning("Sea tutorial unavailable: Player Camera2D is missing.")
		return
	_cue = _camera.get_node_or_null("SeaTutorialCue") as SeaTutorialCue
	if _cue == null:
		_cue = SeaTutorialCue.new()
		_cue.name = "SeaTutorialCue"
		_camera.add_child(_cue)
		_cue.position = Vector2(0.0, 52.0)
		_cue.z_as_relative = false
		_cue.z_index = 110
		_cue.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cue.movement_sprite = movement_tutorial_sprite
	_cue.cast_sprite = cast_tutorial_sprite
	_cue.reel_sprite = reel_tutorial_sprite


func _spawn_editor_fish() -> void:
	for marker in _spawns.get_children():
		if not marker is DivingFishSpawn:
			continue
		var spawn: DivingFishSpawn = marker as DivingFishSpawn
		var data: FishData = spawn.species
		if data == null or data.item_data == null or data.item_data.sprite == null:
			continue
		var fish: DivingWildFish = WILD_FISH_SCRIPT.new() as DivingWildFish
		_actors.add_child(fish)
		fish.setup(data.fish_id, data.item_data.sprite, spawn.position, _sea_bounds(), spawn.random_seed)
		fish.set_max_health(data.max_health)
		fish.flee_radius = 32.0
		_wild_fish.append(fish)
		_fish_data[fish] = data
		if spawn.name == "FirstFish":
			_tutorial_fish = fish
			# Make the introductory cast readable instead of chasing a fish
			# that swims away during the movement lesson.
			fish.trapped = not _story.has_event(&"line_broken")


func _make_silas_trap() -> void:
	if SILAS_FISH.item_data == null or SILAS_FISH.item_data.sprite == null:
		return
	_silas_trap = WILD_FISH_SCRIPT.new() as DivingWildFish
	_actors.add_child(_silas_trap)
	_silas_trap.setup(SILAS_FISH.fish_id, SILAS_FISH.item_data.sprite,
		_silas_home, _sea_bounds(), 8805)
	_silas_trap.trapped = true
	_silas_trap.set_max_health(SILAS_FISH.max_health)
	# The editor-placeable SeaNPC sprite is the visible eel. This second,
	# invisible node is only its fishing/combat hit target.
	(_silas_trap.get_node("FishSprite") as Sprite2D).hide()
	_wild_fish.append(_silas_trap)
	_fish_data[_silas_trap] = SILAS_FISH


func enter_from_dock() -> void:
	if _player == null:
		push_warning("Sea needs World/Player to start a dive.")
		return
	_set_camera_bounds(true)
	_player.set_swimming(true, _sea_bounds())
	_tutorial_swim_origin = _player.position
	_story.on_dive_entered()


func _sea_bounds() -> Rect2:
	var size: Vector2 = _guide.map_size
	return Rect2(
		Vector2(_guide.map_origin.x + 16.0, SEA_TOP),
		Vector2(maxf(size.x - 32.0, 32.0), maxf(size.y - SEA_TOP - 16.0, 32.0))
	)


func _set_camera_bounds(in_sea: bool) -> void:
	if _camera == null:
		return
	if in_sea:
		_camera.limit_left = roundi(_guide.map_origin.x)
		_camera.limit_top = -90
		_camera.limit_right = roundi(_guide.map_origin.x + _guide.map_size.x + 64.0)
		_camera.limit_bottom = roundi(_guide.map_size.y)
	else:
		_camera.limit_left = -10000000
		_camera.limit_top = -10000000
		_camera.limit_right = 10000000
		_camera.limit_bottom = 10000000


func _process(delta: float) -> void:
	if _player == null or not _player.swimming:
		return
	# If the dive transition ran before its UI was ready, the Sea itself
	# starts the movement lesson on the next swimming frame.
	if _cue != null and _cue.current_action == &"" and not _story.has_event(&"fish_focus_seen") \
			and not _story.has_event(&"first_cast") and not _story.has_event(&"line_broken"):
		_story.on_dive_entered()
	_check_first_fish_focus(delta)
	_check_escape_followup()
	_battle.step(delta)
	if _combat.is_active():
		_combat.step(delta)
		if _combat.is_active():
			_sync_hooked_fish()
			_net.set_line_state(_combat.tension, _combat.phase == DivingCombat.Phase.STUN)
	for fish in _wild_fish:
		if not is_instance_valid(fish) or fish == _combat.target:
			continue
		fish.swim(delta, _player.position, false)
	if _story.has_silas_flag(&"silas_following"):
		_story.maybe_offer_companion_help(_player.position, _wild_fish)


# The player learns movement freely first. When the introductory fish is
# close enough for a real cast, pause Penni (and thus the follow camera)
# until the player clicks. The mouse/net still receive input while busy.
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
	if _player.position.distance_to(_tutorial_swim_origin) < MIN_TUTORIAL_SWIM_DISTANCE:
		return
	if _player.position.distance_to(_tutorial_fish.position) > FIRST_FISH_FOCUS_RANGE:
		return
	# The story only confirms the beat after a real visible sprite is shown.
	if not _story.on_first_fish_seen():
		return
	_fish_focus_locked = true
	_fish_focus_timer = FISH_FOCUS_HOLD_SECONDS
	_player.busy = true


func _release_first_fish_focus() -> void:
	if not _fish_focus_locked:
		return
	_fish_focus_locked = false
	_fish_focus_timer = 0.0
	_player.busy = false


func _check_escape_followup() -> void:
	# The bubble is based on moving farther LEFT after seeing the fish flee,
	# not on the reel action itself or a fixed speech timer.
	if _first_fish_escape_finished and not _story.has_event(&"help_called") \
			and _player.position.x <= _help_reveal_x:
		_story.on_followed_escape()


func _start_first_fish_escape() -> void:
	_help_reveal_x = _player.position.x - FOLLOW_AFTER_ESCAPE_DISTANCE
	_first_fish_escape_finished = false
	if not is_instance_valid(_tutorial_fish):
		_first_fish_escape_finished = true
		return
	var fish: DivingWildFish = _tutorial_fish
	# Penni must also swim a little past the fish's old position.
	_help_reveal_x = minf(_help_reveal_x, fish.position.x - 20.0)
	_tutorial_fish = null
	_wild_fish.erase(fish)
	_fish_data.erase(fish)
	# Remove it from normal fish simulation / catch candidates so the
	# escape tween is the sole owner of its movement.
	fish.trapped = true
	var graphic: Sprite2D = fish.get_node_or_null("FishSprite") as Sprite2D
	if graphic != null:
		graphic.flip_h = true
	fish.rotation = 0.0
	var dash: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dash.tween_property(fish, "position",
		fish.position + Vector2(-FIRST_FISH_ESCAPE_DISTANCE, -12.0),
		FIRST_FISH_ESCAPE_SECONDS)
	dash.tween_callback(_finish_first_fish_escape.bind(fish))


func _finish_first_fish_escape(fish: DivingWildFish) -> void:
	if is_instance_valid(fish):
		fish.queue_free()
	_first_fish_escape_finished = true


func _sync_hooked_fish() -> void:
	var fish: DivingWildFish = _combat.target
	if not is_instance_valid(fish):
		return
	var direction: Vector2 = (fish.position - _player.position).normalized()
	if direction.length_squared() < 0.01:
		direction = Vector2.RIGHT
	fish.position = _player.position + direction * _combat.line_distance
	if fish == _silas_trap:
		_silas.position = fish.position


# Main forwards UI-scaled mouse/key events here; sea remains in the original
# SubViewport, so Player.get_global_mouse_position() gives the correct aim.
func handle_input(event: InputEvent) -> bool:
	if _player == null or not _player.swimming:
		return false
	if DialogueManager.is_active or GameManager.is_modal_ui_open():
		return false
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_E or key.keycode == KEY_SPACE:
			if _player.position.distance_to(_silas.position) < 48.0 and _story.can_talk_to_silas():
				_story.talk_to_silas()
				return true
			if _player.position.distance_to(_exit.position) <= SURFACE_REACH:
				_return_to_surface()
				return true
		elif key.keycode == KEY_ESCAPE or key.keycode == KEY_F:
			if _combat.is_active():
				_combat.release()
				return true
			if _battle.is_active():
				_battle.stop()
				return true
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return false
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		if _net.is_busy():
			return true
		var candidates: Array[DivingWildFish] = []
		for fish in _wild_fish:
			if is_instance_valid(fish) and fish.catch_cooldown <= 0.0:
				if fish != _silas_trap or _story.can_net_silas():
					candidates.append(fish)
		var cast_started: bool = _net.cast_net(
			_player, _player.get_global_mouse_position(), candidates
		)
		if cast_started and not _story.has_event(&"first_cast") \
				and not _story.has_event(&"line_broken"):
			_release_first_fish_focus()
			_story.on_first_cast()
		return true
	if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _net.is_latched() and _story.consume_first_reel():
			_net.reset_net()
			_start_first_fish_escape()
			return true
		if _combat.is_active():
			_combat.reel_scroll()
			return true
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		return _try_companion_target(_player.get_global_mouse_position())
	return false


func _on_fish_hit(fish: DivingWildFish) -> void:
	if not is_instance_valid(fish):
		_net.retract()
		return
	if _story.wants_scripted_hook(fish, _tutorial_fish):
		_story.on_scripted_hook()
		return
	if fish == _silas_trap and not _story.can_net_silas():
		_net.retract()
		return
	var data: FishData = _fish_data.get(fish) as FishData
	if data == null:
		_net.retract()
		return
	if _battle.is_active():
		_battle.stop()
	_combat.record_lost_fish = fish != _silas_trap
	if _combat.begin(fish, data, _player.position.distance_to(fish.position),
			_net.max_range, fish.health_ratio()):
		_player.busy = true
	else:
		_net.retract()


func _on_combat_finished(won: bool, fish: DivingWildFish) -> void:
	_player.busy = false
	_net.reset_net()
	if not is_instance_valid(fish):
		return
	var data: FishData = _fish_data.get(fish) as FishData
	if won:
		if fish == _silas_trap:
			_wild_fish.erase(fish)
			_fish_data.erase(fish)
			_silas_trap = null
			fish.queue_free()
			_story.on_silas_rescued()
		else:
			FishingManager.catch_fish(data)
			_wild_fish.erase(fish)
			_fish_data.erase(fish)
			fish.queue_free()
	else:
		fish.catch_cooldown = 1.3
		if fish == _silas_trap:
			fish.position = _silas_home
			_silas.position = _silas_home


func _on_silas_following_started() -> void:
	_silas.following = true


func _try_companion_target(world_mouse: Vector2) -> bool:
	if not _story.has_silas_flag(&"silas_following"):
		return false
	if _battle.is_active():
		_battle.stop()
		return true
	var chosen: DivingWildFish
	var nearest: float = 24.0
	for fish in _wild_fish:
		if not is_instance_valid(fish) or fish.trapped:
			continue
		if _silas.position.distance_to(fish.position) > 120.0:
			continue
		var d: float = fish.position.distance_to(world_mouse)
		if d < nearest:
			nearest = d
			chosen = fish
	if chosen == null:
		return false
	var data: FishData = _fish_data.get(chosen) as FishData
	if data != null and _battle.start(chosen, data):
		_story.on_companion_targeted()
		return true
	return false


func _return_to_surface() -> void:
	if _player != null and _player.swimming:
		_release_first_fish_focus()
		if _combat.is_active():
			_combat.release()
		if _battle.is_active():
			_battle.stop()
		surface_requested.emit()
