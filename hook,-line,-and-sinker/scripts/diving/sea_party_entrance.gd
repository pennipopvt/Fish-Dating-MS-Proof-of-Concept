extends Node
class_name SeaPartyEntrance

signal dive_entries_finished

# Dive presentation only: temporary actors, jumps and fish/human poofs
# in BOTH directions. Housing, dialogue and story decisions stay elsewhere.
@export_range(0.1, 1.0, 0.05) var fade_seconds: float = 0.32
@export_range(0.0, 0.5, 0.05) var jump_stagger_seconds: float = 0.14
@export_group("Returning to Dock")
## Additional distance left into the sea for each successive fish.
@export_range(0.0, 48.0, 1.0) var surface_approach_spacing: float = 20.0
## Separate human landing spots along the dock, away from Penni.
@export_range(0.0, 48.0, 1.0) var surface_dock_spacing: float = 26.0
## A little deeper underwater for each successive companion.
@export_range(0.0, 24.0, 1.0) var surface_depth_spacing: float = 5.0
@export_range(0.0, 0.5, 0.05) var surface_stagger_seconds: float = 0.12

var _world: Node2D
var _player: Player
var _sea: DivingWorld
var _land_scenes: Dictionary = {} # Optional cutscene-specific overrides.
var _staged: Array[Dictionary] = []
var _fish_visuals: Array[Sprite2D] = []
var _entry_in_progress: bool = false
var _entries_remaining: int = 0


func configure(world: Node2D, player: Player, sea: DivingWorld) -> void:
	_world = world
	_player = player
	_sea = sea


func _motion(path_name: StringName) -> SeaMotionPath:
	return _sea.get_node("Points/" + String(path_name)) as SeaMotionPath


# Register additional NPC art directly with the diving system, not housing.
func register_land_scene(npc_id: StringName, scene: PackedScene) -> void:
	_land_scenes[npc_id] = scene


# Called by SeaDiveTransition immediately after dock dive confirmation.
func call_party_to_dock(party: Array[NPCData], dock: Node2D) -> void:
	clear()
	if party.is_empty():
		return
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, fade_seconds)
	_player.global_position = dock.global_position + Vector2(21.0, 11.0)
	_player.animator.play(&"idle_l")
	(_world.get_node("CameraController") as WorldCameraController).snap_to_player()
	for i in range(party.size()):
		var npc: NPCData = party[i]
		var actor: Node2D = NPCTemporaryActor.spawn(npc, _world,
			dock.global_position + Vector2(42.0 + 24.0 * i, 11.0),
			_land_scenes.get(npc.npc_id) as PackedScene)
		if actor == null:
			continue
		actor.name = "DiveGuest_" + String(npc.npc_id)
		_staged.append({"npc": npc, "actor": actor, "index": i})
	await fade.fade_to(0.0, fade_seconds)
	fade.queue_free()


# A single continuous dive path per companion. All guests use the same
# editable curve with separate destinations and short start-time staggers.
# Their human-to-fish transformation happens at the waterline, mid-flight.
func jump_party_in(_dock: Node2D, splash: Callable) -> void:
	_entry_in_progress = true
	_entries_remaining = 0
	var jump_path: SeaMotionPath = _motion(&"CompanionDiveJump")
	for info in _staged:
		var actor: Node2D = info["actor"] as Node2D
		if not is_instance_valid(actor):
			continue
		_entries_remaining += 1
		_animate_guest_dive(info, jump_path, splash)
		if jump_stagger_seconds > 0.0:
			await get_tree().create_timer(jump_stagger_seconds).timeout
	while _entries_remaining > 0:
		await get_tree().process_frame
	_staged.clear()
	_entry_in_progress = false
	dive_entries_finished.emit()


func entry_in_progress() -> bool:
	return _entry_in_progress


func _animate_guest_dive(info: Dictionary, jump_path: SeaMotionPath,
		splash: Callable) -> void:
	var actor: Node2D = info["actor"] as Node2D
	var index: int = int(info["index"])
	var destination: Vector2 = jump_path.authored_end() + Vector2(-18.0 * index, 7.0 * index)
	var state: Dictionary = {"converted": false, "fish": null}
	await jump_path.animate(actor, actor.global_position, destination,
		func(_time: float, _progress: float) -> void:
			_update_guest_dive(actor, info, state, splash))
	if not bool(state["converted"]):
		push_warning("CompanionDiveJump did not cross the sea surface; check its endpoint.")
		_transform_guest_to_fish(actor, info, state, splash)
	if is_instance_valid(actor):
		actor.queue_free()
	_entries_remaining -= 1


func _update_guest_dive(actor: Node2D, info: Dictionary,
		state: Dictionary, splash: Callable) -> void:
	if not is_instance_valid(actor):
		return
	var fish: Sprite2D = state.get("fish") as Sprite2D
	if is_instance_valid(fish):
		# The same tween continues under water, but moves fish art after
		# the splash instead of showing the human actor twice.
		fish.global_position = actor.global_position
	elif not bool(state["converted"]):
		var art: AnimatedSprite2D = actor.get_node_or_null("Sprite") as AnimatedSprite2D
		var visual_y: float = art.global_position.y if art != null else actor.global_position.y
		var surface_y: float = (_world.get_node("Water") as ColorRect).global_position.y
		if visual_y >= surface_y:
			_transform_guest_to_fish(actor, info, state, splash)


func _transform_guest_to_fish(actor: Node2D, info: Dictionary,
		state: Dictionary, splash: Callable) -> void:
	if bool(state["converted"]) or not is_instance_valid(actor):
		return
	state["converted"] = true
	var surface_y: float = (_world.get_node("Water") as ColorRect).global_position.y
	var splash_at := Vector2(actor.global_position.x, surface_y)
	splash.call(splash_at)
	var poof: AnimatedSprite2D = SeaPoofEffect.spawn(_world, splash_at)
	if is_instance_valid(poof):
		get_tree().create_timer(0.42).timeout.connect(poof.queue_free, CONNECT_ONE_SHOT)
	actor.hide()
	var npc: NPCData = info["npc"] as NPCData
	if npc == null or npc.underwater_sprite == null:
		return
	var fish := Sprite2D.new()
	fish.name = "DiveFish_" + String(npc.npc_id)
	fish.texture = npc.underwater_sprite
	fish.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fish.z_index = 6
	var width: float = npc.sea_visuals.follower_width if npc.sea_visuals != null else 24.0
	fish.scale = Vector2.ONE * (width / maxf(float(fish.texture.get_width()), 1.0))
	_world.add_child(fish)
	fish.global_position = actor.global_position
	state["fish"] = fish
	_fish_visuals.append(fish)


# Dock markers are feet positions. All surface art for a given NPC
# converges on the SAME rendered center of their actual human sprite.
# These per-index slots work for any roster up to DivingParty.MAX_COMPANIONS.
func surface_approach_position(at: Vector2, index: int) -> Vector2:
	return at + Vector2(-surface_approach_spacing * index, surface_depth_spacing * index)


func surface_dock_position(at: Vector2, index: int) -> Vector2:
	return at + Vector2(surface_dock_spacing * index, 0.0)


func stage_surface_actor(npc: NPCData, feet_at: Vector2, scene_name: String = "") -> Node2D:
	if npc == null:
		return null
	var actor: Node2D = NPCTemporaryActor.spawn(npc, _world, feet_at,
		_land_scenes.get(npc.npc_id) as PackedScene)
	if actor == null:
		return null
	actor.name = scene_name if not scene_name.is_empty() else "SurfaceGuest_" + String(npc.npc_id)
	actor.visible = false
	return actor


func surface_visual_center(actor: Node2D) -> Vector2:
	var art := actor.get_node_or_null("Sprite") as AnimatedSprite2D
	if art != null:
		return art.global_position
	return actor.global_position


# Shared for Silas's first arrival AND every ordinary party return.
# The jump ends at the human art's visual center, not its scene origin
# or feet marker (which may differ by half a sprite height).
func swim_and_jump_to_surface(fish: Node2D, _approach: Vector2,
		human_center: Vector2) -> void:
	if not is_instance_valid(fish):
		return
	# A single editable path now runs from underwater to the dock, with no
	# artificial pause at the old approach marker. Start from the fish's
	# real location and finish exactly at the staged human art's center.
	await _motion(&"CompanionSurface").animate(
		fish, fish.global_position, human_center)


func transform_surface_fish(fish: Node2D, actor: Node2D) -> void:
	if not is_instance_valid(fish) or not is_instance_valid(actor):
		return
	var center: Vector2 = surface_visual_center(actor)
	fish.global_position = center
	# SeaPoofEffect intentionally offsets its argument up 13 px; compensate
	# so the rendered poof, fish and new human share one actual screen location.
	var poof := SeaPoofEffect.spawn(_world, center + Vector2(0.0, 13.0))
	fish.hide()
	await get_tree().create_timer(0.17).timeout
	actor.show()
	await get_tree().create_timer(0.42).timeout
	if is_instance_valid(poof):
		poof.queue_free()


# Ordinary returns use the actual fish-form actors still in DivingWorld.
# The transition deliberately calls end_diving_party() ONLY afterward.
func surface_party(party: Array[NPCData], sea: DivingWorld,
		sea_approach: Vector2, dock_feet: Vector2) -> Array[Node2D]:
	var actors: Array[Node2D] = []
	for i in range(party.size()):
		var npc: NPCData = party[i]
		if npc == null:
			continue
		var fish_path: String = "NPCs/Silas" if npc.npc_id == &"test_npc" else (
			"NPCs/PartyFish_" + String(npc.npc_id))
		var fish: Node2D = sea.get_node_or_null(fish_path) as Node2D
		if fish == null or not fish.visible:
			push_warning("No active sea companion for surface animation: " + String(npc.npc_id))
			continue
		var actor: Node2D = stage_surface_actor(npc, surface_dock_position(dock_feet, i))
		if actor == null:
			continue
		actors.append(actor)
		await swim_and_jump_to_surface(fish, surface_approach_position(sea_approach, i),
			surface_visual_center(actor))
		await transform_surface_fish(fish, actor)
		if i + 1 < party.size() and surface_stagger_seconds > 0.0:
			await get_tree().create_timer(surface_stagger_seconds).timeout
	return actors


func clear_surface_actors(actors: Array[Node2D]) -> void:
	for actor in actors:
		if is_instance_valid(actor):
			actor.queue_free()


func clear() -> void:
	for info in _staged:
		var actor: Node2D = info.get("actor") as Node2D
		if is_instance_valid(actor):
			actor.queue_free()
	_staged.clear()
	for fish in _fish_visuals:
		if is_instance_valid(fish):
			fish.queue_free()
	_fish_visuals.clear()
