extends Node2D
class_name DivingWorld

# Sea is an editable piece of the existing World. Only orchestration belongs
# here: fish/net/combat are separate reusable nodes; one-time beats belong to
# StoryDirector. We never create a second Player or Camera2D.
signal surface_requested

const SEA_TOP: float = 154.0
const SURFACE_REACH: float = 44.0
const SILAS_FISH: FishData = preload("res://resources/fish/silas.tres")
const WILD_FISH_SCRIPT = preload("res://scripts/diving/wild_fish.gd")

# Inspector texture slots remain editable even though the small cue is
# created at runtime. No new PackedScene or imported file is required.
@export var movement_tutorial_sprite: Texture2D
@export var cast_tutorial_sprite: Texture2D
@export var reel_tutorial_sprite: Texture2D
@export var right_click_tutorial_sprite: Texture2D

@export_group("Sea Parry Feedback")
@export_range(0.05, 1.0, 0.05) var perfect_parry_line_flash_seconds: float = 0.35

@onready var _guide: SeaEditorGuide = $EditorGuide
@onready var _entry: Marker2D = $Points/Entry
@onready var _exit: Marker2D = $Points/SurfaceExit
@onready var _exit_prompt: InteractPrompt = $Points/SurfaceExit/InteractPrompt
@onready var _spawns: Node2D = $FishSpawns
@onready var _actors: Node2D = $FishActors
@onready var _story: SeaStoryDirector = $StoryDirector
@onready var _net: DivingNetProjectile = $NetProjectile
@onready var _combat: DivingCombat = $Combat
@onready var _silas: SeaNPC = $NPCs/Silas
@onready var _battle: DivingCompanionBattle = $NPCs/Silas/CompanionBattle
@onready var _silas_behavior: SilasCombatBehavior = $NPCs/Silas/CombatBehavior
@onready var _encounter: SeaEncounterSequence = $EncounterSequence

var _player: Player
var _camera: Camera2D
var _cue: SeaTutorialCue
var _wild_fish: Array[DivingWildFish] = []
var _fish_data: Dictionary = {}
var _combat_debug_status: String = "No companion command yet"
var _perfect_parry_line_flash_left: float = 0.0
# Keeps the hooked fish in open water during the fight (see _is_open_water).
# Loaded by path (like WILD_FISH_SCRIPT) so it works before the editor has
# registered the HookedFishMover class name.
const HOOKED_FISH_MOVER_SCRIPT = preload("res://scripts/diving/hooked_fish_mover.gd")
var _hooked_mover := HOOKED_FISH_MOVER_SCRIPT.new()
var _hooked_fish: DivingWildFish
@onready var _solids: TileMapLayer = get_node_or_null("Solids") as TileMapLayer
# Points around a hooked fish's center that must be clear of Solids tiles.
const HOOKED_FISH_PROBES: Array[Vector2] = [
	Vector2.ZERO, Vector2(-6.0, 0.0), Vector2(6.0, 0.0), Vector2(0.0, -4.0), Vector2(0.0, 4.0)
]


func _ready() -> void:
	_player = get_parent().get_node_or_null("Player") as Player
	if _player != null:
		_camera = _player.get_node_or_null("Camera2D") as Camera2D
	_hooked_mover.is_open = _is_open_water
	_install_tutorial_cue()
	_encounter.configure(_player, _story, _net, _silas, _cue)
	_encounter.fish_remove_requested.connect(_unregister_encounter_fish)
	_net.fish_hit.connect(_on_fish_hit)
	_combat.finished.connect(_on_combat_finished)
	_combat.parried.connect(_on_sea_parried)
	_story.silas_following_started.connect(_on_silas_following_started)
	_battle.started.connect(_on_battle_started)
	_battle.ended.connect(_on_battle_ended)
	_battle.hit.connect(_on_battle_hit)
	_battle.fish_knocked_out.connect(_on_battle_fish_knocked_out)
	_battle.companion_knocked_out.connect(_on_battle_companion_knocked_out)
	_silas_behavior.fish_spared.connect(_story.on_silas_spared_fish)
	_silas_behavior.attack_refused.connect(_story.on_silas_attack_refused)
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
	_cue.right_click_sprite = right_click_tutorial_sprite


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
		fish.is_open = _is_open_water
		fish.set_max_health(data.max_health)
		fish.preferred_player_distance = spawn.preferred_player_distance
		fish.flee_radius = maxf(spawn.alert_distance, spawn.preferred_player_distance)
		fish.flee_speed = spawn.flee_speed
		_wild_fish.append(fish)
		_fish_data[fish] = data
		if spawn.is_first_dive_fish:
			if _encounter.tutorial_fish != null:
				push_warning("[SEA STORY] Multiple fish spawns marked as first-dive fish.")
			else:
				_encounter.register_tutorial_fish(fish)


func _make_silas_trap() -> void:
	if SILAS_FISH.item_data == null or SILAS_FISH.item_data.sprite == null:
		return
	var trap: DivingWildFish = WILD_FISH_SCRIPT.new() as DivingWildFish
	_actors.add_child(trap)
	trap.setup(SILAS_FISH.fish_id, SILAS_FISH.item_data.sprite,
		_silas.position, _sea_bounds(), 8805)
	trap.trapped = true
	trap.set_max_health(SILAS_FISH.max_health)
	# The editor-placeable SeaNPC is the visible eel. This hidden actor
	# only provides its net hit target; the sequence tracks its identity.
	(trap.get_node("FishSprite") as Sprite2D).hide()
	_wild_fish.append(trap)
	_fish_data[trap] = SILAS_FISH
	_encounter.register_silas_trap(trap)


# World alone mutates its fish registry. EncounterSequence requests removal.
func _unregister_encounter_fish(fish: DivingWildFish) -> void:
	_wild_fish.erase(fish)
	_fish_data.erase(fish)


func enter_from_dock() -> void:
	if _player == null:
		push_warning("Sea needs World/Player to start a dive.")
		return
	_set_camera_bounds(true)
	_player.set_swimming(true, _sea_bounds())
	_encounter.on_dive_entered()


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
	_encounter.step(delta)
	# Reuse the original interaction bubble for the dock return.
	# The marker lives at the waterline; the player cannot swim above
	# the swim bounds, so its radius must work from BELOW the marker.
	if _player.position.distance_to(_exit.position) <= SURFACE_REACH \
			and not DialogueManager.is_active and not GameManager.is_modal_ui_open() \
			and not _net.is_busy() and not _combat.is_active():
		_exit_prompt.pop_in()
	else:
		_exit_prompt.pop_out()
	if _battle.is_active() and (DialogueManager.is_active or _combat.is_active()):
		_battle.stop()
	_silas_behavior.on_combat_update(delta, _silas.can_strike_target())
	if _combat.is_active():
		_combat.step(delta)
		if _combat.is_active():
			_sync_hooked_fish(delta)
			_perfect_parry_line_flash_left = maxf(0.0, _perfect_parry_line_flash_left - delta)
			_net.set_line_state(_combat.tension,
				_combat.phase == DivingCombat.Phase.STUN or _perfect_parry_line_flash_left > 0.0)
	for fish in _wild_fish:
		if not is_instance_valid(fish) or fish == _combat.target:
			continue
		fish.swim(delta, _player.position, false)
	if _story.has_silas_flag(&"silas_following"):
		_story.maybe_offer_companion_help(_player.position, _wild_fish)


func _sync_hooked_fish(delta: float) -> void:
	var fish: DivingWildFish = _combat.target
	if not is_instance_valid(fish):
		return
	if fish != _hooked_fish:
		_hooked_fish = fish
		_hooked_mover.reset()
	fish.position = _hooked_mover.step(delta, _player.position, fish.position, _combat.line_distance)
	if fish == _encounter.silas_trap:
		_silas.position = fish.position


# Open water for a hooked fish: below the waterline, above the sea floor, and
# clear of the Solids tiles (rock and ground). Left and right stay open.
func _is_open_water(point: Vector2) -> bool:
	if point.y < SEA_TOP + DivingWildFish.EDGE_MARGIN:
		return false
	if point.y > _sea_bounds().end.y - DivingWildFish.EDGE_MARGIN:
		return false
	if _solids == null:
		return true
	for probe in HOOKED_FISH_PROBES:
		# Fish positions are in FishActors space; the tiles have their own.
		var cell: Vector2i = _solids.local_to_map(_solids.to_local(_actors.to_global(point + probe)))
		# Only tiles the player also collides with (decor tiles have no shape).
		var tile: TileData = _solids.get_cell_tile_data(cell)
		if tile != null and tile.get_collision_polygons_count(0) > 0:
			return false
	return true


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
			if _encounter.cancel_if_scripted():
				return true
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
				if fish != _encounter.silas_trap or _story.can_net_silas():
					candidates.append(fish)
		var cast_started: bool = _net.cast_net(
			_player, _player.get_global_mouse_position(), candidates
		)
		if cast_started:
			_encounter.on_cast_started()
		return true
	if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _encounter.reel_if_scripted():
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
	if _encounter.handle_fish_hit(fish):
		return
	var data: FishData = _fish_data.get(fish) as FishData
	if data == null:
		_net.retract()
		return
	if _battle.is_active():
		_battle.stop()
	_combat.record_lost_fish = fish != _encounter.silas_trap
	if _combat.begin(fish, data, _player.position.distance_to(fish.position),
			_net.max_range, fish.health_ratio()):
		_player.busy = true
	else:
		_net.retract()


func _on_sea_parried(result: StringName) -> void:
	if result == &"perfect":
		_perfect_parry_line_flash_left = perfect_parry_line_flash_seconds
		# Show gold immediately, rather than waiting for the next frame.
		_net.set_line_state(_combat.tension, true)
	else:
		_perfect_parry_line_flash_left = 0.0


func _on_combat_finished(won: bool, fish: DivingWildFish) -> void:
	_perfect_parry_line_flash_left = 0.0
	_player.busy = false
	_net.reset_net()
	if not is_instance_valid(fish):
		return
	var data: FishData = _fish_data.get(fish) as FishData
	if won:
		if fish == _encounter.silas_trap:
			_encounter.finish_silas_rescue_from_combat()
		else:
			FishingManager.catch_fish(data)
			_wild_fish.erase(fish)
			_fish_data.erase(fish)
			fish.queue_free()
	else:
		fish.catch_cooldown = 1.3
		if fish == _encounter.silas_trap:
			_encounter.restore_silas_position()


func _on_silas_following_started() -> void:
	_silas.following = true
	print("[SEA COMBAT] Silas is now following Penni")


# Maintain the battle state in CompanionBattle, visual movement in SeaNPC,
# and fish health in DivingWildFish. No duplicate combat authority.
func _on_battle_started(fish: DivingWildFish) -> void:
	_combat_debug_status = "Sent Silas to " + String(fish.fish_name)
	print("[SEA COMBAT] " + _combat_debug_status + " at " + str(fish.global_position.round()))


func _on_battle_ended() -> void:
	_combat_debug_status = "Battle ended / recalled"
	print("[SEA COMBAT] " + _combat_debug_status)


func _on_battle_hit(on_fish: bool, damage: float) -> void:
	_silas.on_battle_hit(on_fish)
	print("[SEA COMBAT] %s hit for %.1f; companion HP %.1f/%0.1f" % [
		"Silas" if on_fish else "Fish", damage,
		_battle.health, _battle.stats.max_health])


func _on_battle_fish_knocked_out(fish: DivingWildFish) -> void:
	_wild_fish.erase(fish)
	_fish_data.erase(fish)
	_combat_debug_status = String(fish.fish_name) + " knocked out"
	print("[SEA COMBAT] " + _combat_debug_status)
	var fade: Tween = fish.create_tween()
	fade.tween_property(fish, "modulate:a", 0.0, 0.6)
	fade.parallel().tween_property(fish, "position:y", fish.position.y - 10.0, 0.6)
	fade.tween_callback(fish.queue_free)


func _on_battle_companion_knocked_out() -> void:
	_combat_debug_status = "Silas exhausted; rest to heal"
	print("[SEA COMBAT] " + _combat_debug_status)


func _try_companion_target(world_mouse: Vector2) -> bool:
	if not _story.has_silas_flag(&"silas_following"):
		_combat_debug_status = "Command ignored: Silas not recruited"
		print("[SEA COMBAT] " + _combat_debug_status)
		return false
	var chosen: DivingWildFish
	var nearest: float = 24.0
	for fish in _wild_fish:
		if not is_instance_valid(fish) or fish.trapped:
			continue
		if _player.position.distance_to(fish.position) > 145.0:
			continue
		var d: float = fish.position.distance_to(world_mouse)
		if d < nearest:
			nearest = d
			chosen = fish
	if chosen == _battle.target:
		_battle.stop()
		return true
	if chosen == null:
		if _battle.is_active():
			_battle.stop()
			return true
		_combat_debug_status = "No fish near right-click; range <=145"
		print("[SEA COMBAT] " + _combat_debug_status + " at " + str(world_mouse.round()))
		return false
	var data: FishData = _fish_data.get(chosen) as FishData
	if data != null and _silas_behavior.on_command(chosen, data):
		# A refusal is a handled command but must not count as starting combat.
		if _battle.is_active() and _battle.target == chosen:
			_story.on_companion_targeted()
		else:
			_combat_debug_status = "Silas refuses to hurt this fish again"
		return true
	_combat_debug_status = "FishData missing or companion cannot start battle"
	print("[SEA COMBAT] " + _combat_debug_status)
	return false


func _return_to_surface() -> void:
	if _player != null and _player.swimming:
		_exit_prompt.pop_out()
		_encounter.leave_sea()
		if _combat.is_active():
			_combat.release()
		if _battle.is_active():
			_battle.stop()
		surface_requested.emit()


# The transition owns physical surfacing. Only AFTER it reports completion
# do we ask the story whether this return needs a one-time character scene.
func on_surface_completed() -> void:
	_exit_prompt.pop_out()
	if _story.can_begin_silas_surface_reveal():
		_encounter.play_silas_surface_reveal()
