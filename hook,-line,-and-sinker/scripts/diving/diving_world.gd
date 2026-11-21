extends Node2D
class_name DivingWorld

# Sea is an editable piece of the existing World. Only orchestration belongs
# here: fish/net/combat are separate reusable nodes; one-time beats belong to
# StoryDirector. We never create a second Player or Camera2D.
signal surface_requested
signal oxygen_return_requested
signal kuda_recruited

const OXYGEN_HUD_SCENE: PackedScene = preload("res://prefabs/sea_oxygen_hud.tscn")

const SEA_TOP: float = 154.0
const SURFACE_REACH: float = 44.0
const SILAS_FISH: FishData = preload("res://resources/fish/silas.tres")
const WILD_FISH_SCRIPT = preload("res://scripts/diving/wild_fish.gd")
const FISH_COMBAT_VISUAL_SCENE: PackedScene = preload("res://prefabs/sea_fish_combat_visual.tscn")

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
@onready var _population: SeaPopulation = $SeaPopulation
@onready var _oxygen: SeaOxygen = $SeaOxygen
@onready var _dive_inventory: SeaDiveInventory = $SeaDiveInventory
@onready var _actors: Node2D = $FishActors
@onready var _story: SeaStoryDirector = $StoryDirector
@onready var _net: DivingNetProjectile = $NetProjectile
@onready var _combat: DivingCombat = $Combat
@onready var _silas: SeaNPC = $NPCs/Silas
@onready var _battle: DivingCompanionBattle = $NPCs/Silas/CompanionBattle
@onready var _silas_behavior: SilasCombatBehavior = $NPCs/Silas/CombatBehavior
@onready var _commands: SeaPartyCommands = $PartyCommands
@onready var _encounter: SeaEncounterSequence = $EncounterSequence
@onready var _kuda: SeaKudaEncounter = $KudaEncounter

var _player: Player
var _camera: Camera2D
var _oxygen_hud: SeaOxygenHud
var _cue: SeaTutorialCue
var _wild_fish: Array[DivingWildFish] = []
# Only fish spawned by editable habitat regions are replaced each period.
# Authored tutorial actors and Silas's hidden encounter stay untouched.
var _habitat_fish: Array[DivingWildFish] = []
var _fish_data: Dictionary = {}
var _combat_debug_status: String = "No companion command yet"
var _party_fish: Array[SeaPartyFollower] = []
var _party_dive_active: bool = false
var _perfect_parry_line_flash_left: float = 0.0
# Keeps the hooked fish in open water during the fight (see _is_open_water).
# Loaded by path (like WILD_FISH_SCRIPT) so it works before the editor has
# registered the HookedFishMover class name.
const HOOKED_FISH_MOVER_SCRIPT = preload("res://scripts/diving/hooked_fish_mover.gd")
var _hooked_mover := HOOKED_FISH_MOVER_SCRIPT.new()
var _hooked_fish: DivingWildFish
# Sea sound effects (prefabs/sea_sfx.tscn; empty slots are silent).
const SEA_SFX_SCENE = preload("res://prefabs/sea_sfx.tscn")
var _sfx: Node
var _last_combat_phase: int = -1
@onready var _solids: TileMapLayer = get_node_or_null("Solids") as TileMapLayer
# The sea now uses editable SeaTerrain polygons instead of Solids tiles.
# These are the same baked collision polygons that block the player and net.
# Cache their bounds once: fish query open water many times per frame.
var _terrain_colliders: Array[CollisionPolygon2D] = []
var _terrain_bounds: Array[Rect2] = []
# Samples around each fish's center, not only its center pixel.
const HOOKED_FISH_PROBES: Array[Vector2] = [
	Vector2.ZERO, Vector2(-6.0, 0.0), Vector2(6.0, 0.0), Vector2(0.0, -4.0), Vector2(0.0, 4.0)
]


func _ready() -> void:
	_player = get_parent().get_node_or_null("Player") as Player
	if _player != null:
		_camera = _player.get_node_or_null("Camera2D") as Camera2D
	_cache_terrain_colliders()
	_hooked_mover.is_open = _is_open_water
	_sfx = SEA_SFX_SCENE.instantiate()
	add_child(_sfx)
	_install_tutorial_cue()
	_install_oxygen_hud()
	_oxygen.oxygen_changed.connect(_update_oxygen_hud)
	_oxygen.oxygen_depleted.connect(_on_oxygen_depleted)
	_story.first_companion_catch_completed.connect(_on_first_companion_catch_oxygen)
	_encounter.configure(_player, _story, _net, _silas, _cue)
	_encounter.fish_remove_requested.connect(_unregister_encounter_fish)
	_kuda.configure(_player, _story, _spawn_wild_fish,
		_unregister_encounter_fish, _is_open_water)
	_kuda.first_hook_dialogue_finished.connect(_start_kuda_fight)
	_kuda.recruited.connect(_on_kuda_recruited)
	_net.fish_hit.connect(_on_fish_hit)
	_combat.finished.connect(_on_combat_finished)
	_combat.parried.connect(_on_sea_parried)
	_story.silas_following_started.connect(_on_silas_following_started)
	_story.first_companion_catch_completed.connect(_queue_habitat_population)
	_population.spawn_requested.connect(_on_population_spawn_requested)
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


# The tutorial cue stays on the camera, but oxygen is real screen-space UI:
# a CanvasLayer in the sea's 320x180 SubViewport, never on Penni/Camera2D.
func _install_oxygen_hud() -> void:
	_oxygen_hud = get_node_or_null("SeaOxygenHud") as SeaOxygenHud
	if _oxygen_hud == null:
		_oxygen_hud = OXYGEN_HUD_SCENE.instantiate() as SeaOxygenHud
		add_child(_oxygen_hud)
	_update_oxygen_hud(_oxygen.ratio(), _oxygen.enabled)


func _update_oxygen_hud(fraction: float, is_enabled: bool) -> void:
	if _oxygen_hud != null:
		_oxygen_hud.show_oxygen(fraction, is_enabled, _oxygen.warning_fraction)


func _on_first_companion_catch_oxygen() -> void:
	# Full oxygen begins AFTER the first Silas-assisted catch.
	_oxygen.activate()


func _on_oxygen_depleted() -> void:
	# The same transition owns the physical return; the oxygen component
	# only supplies the failure event. No separate underwater world.
	_encounter.leave_sea()
	if _combat.is_active():
		_combat.release()
	if _battle.is_active():
		_battle.stop()
	_net.reset_net()
	oxygen_return_requested.emit()


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
		var fish: DivingWildFish = _spawn_wild_fish(data, spawn.position,
			spawn.random_seed, spawn.preferred_player_distance, spawn.alert_distance,
			spawn.flee_speed)
		if spawn.is_first_dive_fish:
			if _encounter.tutorial_fish != null:
				push_warning("[SEA STORY] Multiple fish spawns marked as first-dive fish.")
			else:
				_encounter.register_tutorial_fish(fish)


# Both authored tutorial spawns and procedural habitats use this ONE normal
# fish setup/registration path. The invisible Silas rescue target stays special.
func _spawn_wild_fish(data: FishData, where: Vector2, random_seed: int,
		preferred_distance: float, alert: float, flee: float) -> DivingWildFish:
	var fish: DivingWildFish = WILD_FISH_SCRIPT.new() as DivingWildFish
	_actors.add_child(fish)
	fish.setup(data.fish_id, data.item_data.sprite, where, _sea_bounds(), random_seed)
	fish.is_open = _is_open_water
	fish.set_max_health(data.max_health)
	fish.preferred_player_distance = preferred_distance
	fish.flee_radius = maxf(alert, preferred_distance)
	fish.flee_speed = flee
	_wild_fish.append(fish)
	_fish_data[fish] = data
	return fish


func _queue_habitat_population() -> void:
	# Defer until the caught tutorial fish has been removed from the registry.
	# The next available frame is still the same first dive.
	_populate_habitats.call_deferred()


func _populate_habitats() -> void:
	if _population.has_generated_for_current_period() or _camera == null:
		return
	var positions: Array[Vector2] = []
	for fish in _wild_fish:
		if is_instance_valid(fish):
			positions.append(fish.position)
	positions.append(_player.position)
	_population.generate_after_tutorial(_camera, _sea_bounds(),
		_is_open_water, positions)


func _on_population_spawn_requested(data: FishData, where: Vector2,
		seed_value: int, habitat: SeaSpawnRegion) -> void:
	var fish: DivingWildFish = _spawn_wild_fish(data, where, seed_value,
		habitat.preferred_player_distance, habitat.alert_distance, habitat.flee_speed)
	_habitat_fish.append(fish)


# Only invoked once Penni has reached water on a DIFFERENT period.
# Never replace hooked fish or an active Silas battle, and never respawn
# scripted/tutorial entities. Ordinary fish left over from the previous
# time period are replaced at new random positions.
func _refresh_habitats_for_new_period() -> void:
	if _population.has_generated_for_current_period():
		return
	if _combat.is_active() or _battle.is_active():
		return
	for fish in _habitat_fish:
		if not is_instance_valid(fish):
			continue
		_wild_fish.erase(fish)
		_fish_data.erase(fish)
		fish.queue_free()
	_habitat_fish.clear()
	_populate_habitats()


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
	_dive_inventory.begin_dive()
	_oxygen.begin_dive(_story.has_event(&"first_companion_catch"))
	# The first dive remains scripted until Silas helps with a catch.
	# Every subsequent period gets a fresh habitat population only on entry,
	# once the descent finishes and the camera is already in the sea.
	if _story.has_event(&"first_companion_catch"):
		_refresh_habitats_for_new_period()
	_encounter.on_dive_entered()
	_kuda.activate()


# Return Silas's original companion battle actor on subsequent dives.
# Other school members get fish-form followers without any housing scenes.
func activate_diving_party(members: Array[NPCData]) -> void:
	end_diving_party()
	_commands.clear()
	_party_dive_active = true
	var silas_in_party: bool = false
	for i in range(members.size()):
		var npc: NPCData = members[i]
		if npc == null:
			continue
		add_diving_party_member(npc, i)
		if npc.npc_id == _story.silas_data.npc_id:
			silas_in_party = true
	var flags: Dictionary = NPCManager.get_npc_state(_story.silas_data.npc_id)["flags"]
	flags[&"silas_following"] = silas_in_party


# Add a newly recruited fish DURING the dive without recreating other
# companions or resetting their positions/health.
func add_diving_party_member(npc: NPCData, index: int) -> void:
	if npc == null or npc.underwater_sprite == null or _player == null:
		return
	_party_dive_active = true
	if npc.npc_id == _story.silas_data.npc_id:
		_silas.global_position = _player.global_position + Vector2(-24.0 - index * 16.0, 8.0)
		_silas.show()
		_silas.following = true
		_commands.register_member(npc, _silas, _battle, _silas_behavior)
		return
	var node_name: String = "PartyFish_" + String(npc.npc_id)
	if $NPCs.get_node_or_null(node_name) != null:
		return
	var follower := SeaPartyFollower.new()
	follower.name = node_name
	$NPCs.add_child(follower)
	follower.setup(npc, _player, index)
	follower.global_position = _player.global_position + Vector2(-24.0 - index * 16.0, 8.0)
	_party_fish.append(follower)
	if follower.battle != null and follower.behavior != null:
		_commands.register_member(npc, follower, follower.battle, follower.behavior)
		follower.battle.started.connect(_on_extra_battle_started.bind(npc.npc_id))
		follower.battle.hit.connect(_on_extra_battle_hit.bind(follower, follower.battle))
		follower.battle.fish_knocked_out.connect(_on_battle_fish_knocked_out)
		follower.battle.companion_knocked_out.connect(
			_on_extra_companion_knocked_out.bind(npc.npc_id))


func end_diving_party() -> void:
	# Covers the tutorial's Silas-only party as well as roster-backed dives.
	_commands.clear()
	if not _party_dive_active:
		return
	_party_dive_active = false
	if _battle.is_active():
		_battle.stop()
	_silas.following = false
	_silas.hide()
	var flags: Dictionary = NPCManager.get_npc_state(_story.silas_data.npc_id)["flags"]
	flags[&"silas_following"] = false
	for follower in _party_fish:
		if is_instance_valid(follower):
			follower.queue_free()
	_party_fish.clear()


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
		if _sfx != null:
			_sfx.set_swimming(false)
		return
	# Oxygen pauses during dialogue and menus so reading is never punished,
	# but otherwise continues draining during fishing combat.
	if not DialogueManager.is_active and not GameManager.is_modal_ui_open():
		_oxygen.step(delta, to_local(_player.global_position).y)
	_sfx.set_swimming(not _player.busy and _player.velocity.length() > 8.0)
	_encounter.step(delta)
	# Kuda and his prey are real WildFish actors but use authored chase
	# steering rather than the generic autonomous swim routine.
	# Do not drive a hooked prey, but ALWAYS update the encounter when
	# no prey exists. The old null == null comparison stopped the entire
	# chase after Kuda killed his prey, preventing all replacements.
	if not _combat.is_active() or _combat.target != _kuda.prey:
		_kuda.step(delta)
	# Reuse the original interaction bubble for the dock return.
	# The marker lives at the waterline; the player cannot swim above
	# the swim bounds, so its radius must work from BELOW the marker.
	if _player.position.distance_to(_exit.position) <= SURFACE_REACH \
			and not DialogueManager.is_active and not GameManager.is_modal_ui_open() \
			and not _net.is_busy() and not _combat.is_active():
		_exit_prompt.pop_in()
	else:
		_exit_prompt.pop_out()
	# Multiple fights stay independent. Pause damage while reading dialogue;
	# netting/reeling one fish only recalls its own attacker.
	if not DialogueManager.is_active and not GameManager.is_modal_ui_open():
		_commands.step(delta)
	if _combat.is_active():
		_combat.step(delta)
		_play_combat_phase_sfx()
		if _combat.is_active():
			_sync_hooked_fish(delta)
			_perfect_parry_line_flash_left = maxf(0.0, _perfect_parry_line_flash_left - delta)
			_net.set_line_state(_combat.tension,
				_combat.phase == DivingCombat.Phase.STUN or _perfect_parry_line_flash_left > 0.0)
	for fish in _wild_fish:
		if not is_instance_valid(fish) or fish == _combat.target \
				or _kuda.controls_fish(fish):
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


# Terrain can be nested in arbitrary editor folders (e.g. "Sea Terrain")
# or inside other decoration nodes. Find every instance once at scene load;
# do not require level designers to keep spline instances as direct children.
# Their runtime collision polygons remain the single authoritative geometry.
func _cache_terrain_colliders() -> void:
	_terrain_colliders.clear()
	_terrain_bounds.clear()
	_collect_terrain_colliders(self)


func _collect_terrain_colliders(parent: Node) -> void:
	for child in parent.get_children():
		if child is SeaTerrain:
			var collider: CollisionPolygon2D = child.get_node_or_null(
				"StaticBody2D/CollisionPolygon2D") as CollisionPolygon2D
			if collider != null and collider.polygon.size() >= 3:
				var body: StaticBody2D = collider.get_parent() as StaticBody2D
				if body != null and (body.collision_layer & 2) != 0:
					var polygon: PackedVector2Array = collider.polygon
					var bounds := Rect2(polygon[0], Vector2.ZERO)
					for vertex in polygon:
						bounds = bounds.expand(vertex)
					_terrain_colliders.append(collider)
					_terrain_bounds.append(bounds)
		_collect_terrain_colliders(child)


# Wild swimmers, hooked fish and habitat spawning all share this query.
# Their actors are Node2D fish, not CharacterBody2D, so the engine cannot
# push them out of a StaticBody2D automatically.
func _is_open_water(point: Vector2) -> bool:
	if point.y < SEA_TOP + DivingWildFish.EDGE_MARGIN:
		return false
	if point.y > _sea_bounds().end.y - DivingWildFish.EDGE_MARGIN:
		return false
	for probe in HOOKED_FISH_PROBES:
		# Fish positions are in FishActors space. Both old tiles and new
		# terrain polygons have independent local transforms.
		var world_point: Vector2 = _actors.to_global(point + probe)
		if _solids != null:
			var cell: Vector2i = _solids.local_to_map(_solids.to_local(world_point))
			var tile: TileData = _solids.get_cell_tile_data(cell)
			if tile != null and tile.get_collision_polygons_count(0) > 0:
				return false
		for i in range(_terrain_colliders.size()):
			var collider: CollisionPolygon2D = _terrain_colliders[i]
			if not is_instance_valid(collider) or collider.disabled:
				continue
			var local_point: Vector2 = collider.to_local(world_point)
			if _terrain_bounds[i].has_point(local_point) and Geometry2D.is_point_in_polygon(
					local_point, collider.polygon):
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
			play_sfx(&"reel")
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
	if _kuda.on_net_hit(fish):
		return
	_begin_fish_combat(fish)


func _start_kuda_fight(fish: DivingWildFish) -> void:
	if is_instance_valid(fish):
		_begin_fish_combat(fish)


func _begin_fish_combat(fish: DivingWildFish) -> void:
	var data: FishData = _fish_data.get(fish) as FishData
	if data == null:
		_net.retract()
		return
	_commands.recall_target(fish)
	_combat.record_lost_fish = fish != _encounter.silas_trap and fish != _kuda.kuda
	if _combat.begin(fish, data, _player.position.distance_to(fish.position),
			_net.max_range, fish.health_ratio()):
		# Presentation belongs to the fish actor; it reads existing combat
		# phases and doesn't introduce new timers into DivingCombat.
		var visuals: SeaFishCombatVisual = fish.get_node_or_null("CombatVisual") as SeaFishCombatVisual
		if visuals == null:
			visuals = FISH_COMBAT_VISUAL_SCENE.instantiate() as SeaFishCombatVisual
			fish.add_child(visuals)
		visuals.bind_combat(_combat)
		_player.busy = true
		_last_combat_phase = -1
		play_sfx(&"hook")
	else:
		_net.retract()


func _on_sea_parried(result: StringName) -> void:
	if result == &"perfect" or result == &"close":
		play_sfx(&"counter")
	if result == &"perfect":
		_perfect_parry_line_flash_left = perfect_parry_line_flash_seconds
		# Show gold immediately, rather than waiting for the next frame.
		_net.set_line_state(_combat.tension, true)
	else:
		_perfect_parry_line_flash_left = 0.0


func _on_combat_finished(won: bool, fish: DivingWildFish) -> void:
	play_sfx(&"catch" if won else &"lose")
	_perfect_parry_line_flash_left = 0.0
	_player.busy = false
	_net.reset_net()
	if not is_instance_valid(fish):
		return
	if fish == _kuda.kuda:
		if won:
			_kuda.on_caught()
		else:
			fish.catch_cooldown = 1.3
			_kuda.on_escape()
		return
	var data: FishData = _fish_data.get(fish) as FishData
	if won:
		if fish == _encounter.silas_trap:
			_encounter.finish_silas_rescue_from_combat()
		else:
			_story.on_first_companion_catch(fish)
			# Record species discovery/challenges immediately, but the fish
			# remains carried until the dive is successfully completed.
			FishingManager.catch_fish(data, false)
			_dive_inventory.record_fish(data)
			_wild_fish.erase(fish)
			_fish_data.erase(fish)
			fish.queue_free()
	else:
		fish.catch_cooldown = 1.3
		if fish == _encounter.silas_trap:
			_encounter.restore_silas_position()


func _on_silas_following_started() -> void:
	_silas.following = true
	# During the tutorial Silas can fight before the first shore scene
	# formally creates his DivingParty roster.
	_commands.register_member(_story.silas_data, _silas, _battle, _silas_behavior)
	print("[SEA COMBAT] Silas is now following Penni")


# Maintain the battle state in CompanionBattle, visual movement in SeaNPC,
# and fish health in DivingWildFish. No duplicate combat authority.
func _on_kuda_recruited() -> void:
	kuda_recruited.emit()


func _on_battle_started(fish: DivingWildFish) -> void:
	_combat_debug_status = "Sent Silas to " + String(fish.fish_name)
	print("[SEA COMBAT] " + _combat_debug_status + " at " + str(fish.global_position.round()))


func _on_battle_ended() -> void:
	_combat_debug_status = "Battle ended / recalled"
	print("[SEA COMBAT] " + _combat_debug_status)


func _on_battle_hit(on_fish: bool, damage: float) -> void:
	play_sfx(&"battle_hit")
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


func _on_extra_battle_started(fish: DivingWildFish, npc_id: StringName) -> void:
	_combat_debug_status = String(npc_id) + " sent to " + String(fish.fish_name)
	print("[SEA COMBAT] " + _combat_debug_status)


func _on_extra_battle_hit(on_fish: bool, damage: float,
		actor: SeaPartyFollower, battle: DivingCompanionBattle) -> void:
	play_sfx(&"battle_hit")
	actor.on_battle_hit(on_fish)
	print("[SEA COMBAT] %s hit for %.1f; HP %.1f/%.1f" % [
		"Companion" if on_fish else "Wild fish", damage, battle.health,
		battle.stats.max_health])


func _on_extra_companion_knocked_out(npc_id: StringName) -> void:
	_combat_debug_status = String(npc_id) + " exhausted; rest to heal"
	print("[SEA COMBAT] " + _combat_debug_status)


func _try_companion_target(world_mouse: Vector2) -> bool:
	if _commands.party_order().is_empty():
		_combat_debug_status = "Command ignored: no active companions"
		return false
	var chosen: DivingWildFish
	var nearest: float = 24.0
	for fish in _wild_fish:
		if not is_instance_valid(fish) or fish.trapped:
			continue
		# An already-assigned fish can be recalled from farther away.
		# Otherwise an out-of-range target looked like empty water and
		# accidentally recalled the *whole* party.
		if _commands.owner_of_target(fish) == &"" \
				and _player.position.distance_to(fish.position) > 145.0:
			continue
		var d: float = fish.position.distance_to(world_mouse)
		if d < nearest:
			nearest = d
			chosen = fish
	if chosen == null:
		# No targets: recall everyone and restore the original party order.
		return _commands.recall_all()
	if _commands.recall_target(chosen):
		# Recalling one attacker leaves every other ongoing fight intact.
		return true
	var next_id: StringName = _commands.next_available_id()
	if next_id == &"":
		_combat_debug_status = "Every available companion is already attacking"
		return false
	if next_id == _story.silas_data.npc_id and _kuda.protects_from_silas(chosen):
		# Silas won't interrupt Kuda's scripted hunt or hurt the hunted prey.
		_story.on_silas_refuses_kuda_hunt()
		return true
	var data: FishData = _fish_data.get(chosen) as FishData
	if data == null:
		return false
	if not _commands.send_next(chosen, data):
		return false
	# The combat behavior can refuse a target (e.g. Silas's safety limit)
	# without consuming his queue slot.
	if _commands.owner_of_target(chosen) == _story.silas_data.npc_id:
		_story.on_companion_targeted()
	elif _commands.owner_of_target(chosen) == &"":
		_combat_debug_status = "Companion refused to attack"
	return true

func _return_to_surface() -> void:
	if _player != null and _player.swimming:
		if not _story.can_surface():
			_story.on_surface_blocked()
			return
		play_sfx(&"surface")
		_oxygen.pause()
		_exit_prompt.pop_out()
		_encounter.leave_sea()
		if _combat.is_active():
			_combat.release()
		if _battle.is_active():
			_battle.stop()
		surface_requested.emit()


# After shared fish-to-human poofs, dispatch first-time shore scenes to the
# character encounter that owns them. Keep their actors visible for dialogue.
func on_party_surfaced(surface_actors: Array[Node2D]) -> void:
	await _kuda.play_first_surface_reveal(surface_actors)


# The transition owns physical surfacing. Only AFTER it reports completion
# do we ask the story whether this return needs a one-time character scene.
func on_surface_completed() -> void:
	_exit_prompt.pop_out()
	# Encounters are recreated at each subsequent dive; never leave the
	# Kuda chase running ashore or respawn him once he has joined the party.
	_kuda.end_dive()
	if _story.can_begin_silas_surface_reveal():
		_encounter.play_silas_surface_reveal()


# Sea sound hub; SeaDiveTransition also calls this for the dive splash.
func play_sfx(event: StringName) -> void:
	if _sfx != null:
		_sfx.play(event)


# Windup and attack sounds when the hooked fish enters those phases.
func _play_combat_phase_sfx() -> void:
	if not _combat.is_active() or _combat.phase == _last_combat_phase:
		return
	_last_combat_phase = _combat.phase
	if _combat.phase == DivingCombat.Phase.WINDUP:
		play_sfx(&"windup")
	elif _combat.phase == DivingCombat.Phase.ATTACK:
		play_sfx(&"attack")
