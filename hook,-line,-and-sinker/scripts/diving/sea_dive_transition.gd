extends CanvasLayer
class_name SeaDiveTransition

signal surface_completed

# Owns ONLY the physical one-world transitions: iris, dock jump,
# sea descent and surfacing. FishCoOpeningSequence handles choices.
const RIPPLE: Texture2D = preload("res://sprites/environment/medium_ripple_a.png")
const IRIS_DURATION: float = 0.52
const IRIS_OPEN_RADIUS: float = 2.6
# The editable Sea/MotionPaths nodes own all dive/jump geometry and timing.

@onready var _iris: ColorRect = $Iris
@onready var _party: DivingParty = $DivingParty
@onready var _party_entrance: SeaPartyEntrance = $PartyEntrance
var _iris_material: ShaderMaterial
var _world: Node2D
var _world_player: Player
var _camera_controller: WorldCameraController
var _sea: DivingWorld
var _dialogue_ui: DialogueUI
var _shop_menu: ShopMenu
var _opening: CanvasLayer
var underwater: bool = false
var transitioning: bool = false
var _dive_has_splashed: bool = false
var shore_return_position: Vector2 = Vector2(56.0, 112.0)


func _ready() -> void:
	_iris.hide()
	_iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_iris_material = (_iris.material as ShaderMaterial).duplicate() as ShaderMaterial
	_iris.material = _iris_material
	_set_iris_radius(IRIS_OPEN_RADIUS)


func configure(world: Node2D, player: Player, sea: DivingWorld,
		dialogue_ui: DialogueUI, shop: ShopMenu, opening: CanvasLayer) -> void:
	_world = world
	_world_player = player
	_camera_controller = world.get_node("CameraController") as WorldCameraController
	_sea = sea
	_dialogue_ui = dialogue_ui
	_shop_menu = shop
	_opening = opening
	_party.configure(_sea.get_node("StoryDirector") as SeaStoryDirector)
	_party_entrance.configure(_world, _world_player, _sea)
	(_sea.get_node("EncounterSequence") as SeaEncounterSequence).set_surface_presentation(_party_entrance)
	_sea.surface_requested.connect(_on_surface_requested)
	_sea.oxygen_return_requested.connect(_on_oxygen_return_requested)
	_sea.companion_care_requested.connect(_on_companion_care_requested)
	_sea.kuda_recruited.connect(_on_kuda_recruited)
	surface_completed.connect(_sea.on_surface_completed)
	# Story can request fish/human portraits for a conversation without
	# teaching this physical transition about any particular character.
	(_sea.get_node("StoryDirector") as SeaStoryDirector).dialogue_mode_requested.connect(
		_dialogue_ui.set_underwater_mode
	)


# Recruitment during a dive adds one follower right away. Other party
# members are untouched, and the roster persists for subsequent dives.
func _on_kuda_recruited() -> void:
	if not _party.invite(DivingParty.KUDA):
		return
	if underwater and not transitioning:
		var members: Array[NPCData] = _party.members()
		_sea.add_diving_party_member(DivingParty.KUDA, members.size() - 1)


func begin_intro_to_dock(intro: FishCoIntro) -> void:
	if transitioning:
		return
	transitioning = true
	_world_player.busy = true
	_transition_contract_to_dock(intro)


func _transition_contract_to_dock(intro: FishCoIntro) -> void:
	await _close_iris(Vector2(0.5, 0.5))
	if is_instance_valid(intro):
		intro.end()
	if is_instance_valid(_opening):
		_opening.hide()

	# The existing island and dock are already loaded under the backdrop.
	# This is not a new scene or a duplicate starting environment.
	var dock: Node2D = _world.get_node("Dock") as Node2D
	_world_player.global_position = dock.global_position + Vector2(22.0, 11.0)
	_world_player.z_index = 0
	_world_player.animator.play(&"idle_l")
	_camera_controller.snap_to_player()
	var terminal: ShopInteractable = _world.get_node("Shop") as ShopInteractable
	terminal.set_intro_quota_notice(true)

	await _open_iris(_normalized_screen_position(_world_player))
	transitioning = false
	_world_player.busy = false



func start_confirmed_dive(dock: Node2D) -> void:
	if transitioning or underwater or not GameManager.begin_dive_period():
		return
	transitioning = true
	# Keep the quota-only terminal during the first dive. Main unlocks
	# Storage only once Silas's first shore reveal dialogue has finished.
	dock.call("mark_dive_started")
	_world_player.busy = true
	shore_return_position = dock.global_position + Vector2(21.0, 11.0)
	_begin_dive(dock)


func _begin_dive(dock: Node2D) -> void:
	# A single editable jump goes from the dock to deep water. The splash,
	# swimming pose and water visuals transition at the real waterline, not
	# after a separate descent animation.
	var members: Array[NPCData] = _party.members()
	await _party_entrance.call_party_to_dock(members, dock)
	var jump_path: SeaMotionPath = _motion(&"PenniDiveJump")
	_dive_has_splashed = false
	_world_player.animator.play(&"walk_l")
	await jump_path.animate(_world_player, _world_player.global_position,
		Vector2.INF, _update_dive_jump_visual)
	if not _dive_has_splashed:
		push_warning("PenniDiveJump does not cross the sea surface; check its Path2D endpoint.")
		_on_dive_splash((_world.get_node("Water") as ColorRect).global_position.y)
	if _party_entrance.entry_in_progress():
		await _party_entrance.dive_entries_finished

	_party_entrance.clear()
	_world_player.animator.rotation = 0.0
	_sea.enter_from_dock()
	if (_sea.get_node("StoryDirector") as SeaStoryDirector).has_silas_flag(&"silas_surface_transformed"):
		_sea.activate_diving_party(members)
	_world_player.busy = false
	transitioning = false


func _motion(path_name: StringName) -> SeaMotionPath:
	return _sea.get_node("Points/" + String(path_name)) as SeaMotionPath


func _update_dive_jump_visual(_time: float, progress: float) -> void:
	# One authored path controls Penni's position. The existing world
	# shader already uses real water depth for its reflection/tint.
	var surface_y: float = (_world.get_node("Water") as ColorRect).global_position.y
	var visual_center_y: float = _world_player.global_position.y + _world_player.animator.position.y
	if not _dive_has_splashed and visual_center_y >= surface_y:
		_on_dive_splash(surface_y)
	if not _dive_has_splashed:
		_world_player.animator.rotation = -0.25 * sin(PI * progress)
	else:
		_world_player.animator.rotation = 0.0

func _on_dive_splash(surface_y: float) -> void:
	if _dive_has_splashed:
		return
	_dive_has_splashed = true
	_world_player.animator.rotation = 0.0
	_spawn_splash(Vector2(_world_player.global_position.x, surface_y))
	_sea.play_sfx(&"dive")
	underwater = true
	GameManager.diving_session_active = true
	_dialogue_ui.set_underwater_mode(true)
	_world_player.set_swimming(true, _sea._sea_bounds())
	_camera_controller.set_underwater_mode(true)
	# Companions follow using their own single continuous dive path,
	# starting just after Penni enters the water.
	_party_entrance.jump_party_in(null, Callable(self, "_spawn_splash"))


func _spawn_splash(at: Vector2) -> void:
	var splash := Sprite2D.new()
	splash.texture = RIPPLE
	splash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	splash.z_index = 20
	splash.global_position = at
	splash.scale = Vector2(0.7, 0.35)
	_world.add_child(splash)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(splash, "scale", Vector2(1.55, 0.7), 0.37)
	tween.tween_property(splash, "modulate:a", 0.0, 0.37)
	tween.chain().tween_callback(splash.queue_free)



func _on_surface_requested() -> void:
	if transitioning or not underwater:
		return
	transitioning = true
	_world_player.busy = true
	_surface_from_dive()


func _surface_from_dive() -> void:
	# Return through the SAME water surface. Sky stays visible in the camera;
	# there is no fade-to-black or replacement scene.
	var surface_path := _motion(&"PenniSurface")
	await surface_path.animate(_world_player, _world_player.global_position,
		shore_return_position)
	_world_player.last_direction = 1.0 # Face inland when returning from the sea.
	_world_player.set_swimming(false)
	_camera_controller.set_underwater_mode(false)
	_world_player.animator.rotation = 0.0
	_world_player.animator.play(&"idle_r")
	underwater = false
	_sea.call("_set_camera_bounds", false)
	_dialogue_ui.set_underwater_mode(false)
	# Catch safety is settled BEFORE the terminal and story process the return.
	(_sea.get_node("SeaDiveInventory") as SeaDiveInventory).secure_catch()
	(_sea.get_node("SeaOxygen") as SeaOxygen).end_dive()
	# Every completed dive uses the remaining morning/afternoon/night period.
	GameManager.finish_dive_period()

	var story := _sea.get_node("StoryDirector") as SeaStoryDirector
	# First Silas shore reveal retains its authored jump/poof. Every other
	# standard return uses the shared party entrance as before.
	if not story.can_begin_silas_surface_reveal() and not _party.members().is_empty():
		var approach := _sea.get_node("Points/SilasSurfaceApproach") as Marker2D
		var dock_wait := _sea.get_node("Points/SilasDockWait") as Marker2D
		var humans: Array[Node2D] = await _party_entrance.surface_party(
			_party.members(), _sea, approach.global_position, dock_wait.global_position)
		await _resolve_shore_stories(humans)
		await _clear_returning_party(humans)
	else:
		_sea.end_diving_party()

	transitioning = false
	_world_player.busy = false
	surface_completed.emit()


func _on_oxygen_return_requested() -> void:
	if transitioning or not underwater:
		return
	transitioning = true
	_world_player.busy = true
	_blackout_from_oxygen()


func _on_companion_care_requested(npc: NPCData) -> void:
	if transitioning or not underwater or npc == null:
		return
	transitioning = true
	_world_player.busy = true
	_blackout_from_oxygen(npc)


# An emergency care trip shares blackout's physical return, then supplies
# its own first-land dialogue instead of saying Penni was unconscious.
# The same on_party_surfaced hook still owns room assignment.
func _resolve_shore_stories(humans: Array[Node2D],
		recovered_from_blackout: bool = false,
		first_land_ids: Array[StringName] = [],
		cared_for: NPCData = null) -> void:
	var story := _sea.get_node("StoryDirector") as SeaStoryDirector
	var dock_cast: Array[NPCData] = []
	for actor in humans:
		var guest: NPCInteractable = actor as NPCInteractable
		if is_instance_valid(guest) and guest.npc != null and guest.visible:
			dock_cast.append(guest.npc)
	if cared_for != null:
		await story.play_first_land_care_dialogue(cared_for, dock_cast)
	elif recovered_from_blackout:
		await story.play_oxygen_blackout_recovery(dock_cast, first_land_ids)
	await _sea.on_party_surfaced(humans, first_land_ids)


# Normal shore returns already fade to send fish back to their rooms.
# Reuse that same exit fade for blackout returns and Kuda's townhouse scene.
func _clear_returning_party(humans: Array[Node2D]) -> void:
	if humans.is_empty():
		_sea.end_diving_party()
		return
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, _party_entrance.fade_seconds)
	_sea.end_diving_party()
	_party_entrance.clear_surface_actors(humans)
	await fade.fade_to(0.0, _party_entrance.fade_seconds)
	fade.queue_free()


func _blackout_from_oxygen(cared_for: NPCData = null) -> void:
	# Shared fade for both failures: oxygen blackout or Penni carrying an
	# injured first-time companion to shore. Both cost the dive's catch/time.
	# The latter NEVER plays the "Penni woke up" rescue dialogue.
	var returning: Array[NPCData] = _party.members()
	var story := _sea.get_node("StoryDirector") as SeaStoryDirector
	var silas_first_land_care: bool = cared_for == story.silas_data \
		and story.can_begin_silas_surface_reveal()
	if cared_for != null and not returning.has(cared_for):
		returning.append(cared_for)
	var first_land_ids: Array[StringName] = []
	if story.can_begin_silas_surface_reveal():
		first_land_ids.append(story.silas_data.npc_id)
		if not returning.has(story.silas_data):
			returning.push_front(story.silas_data)
	for npc in returning:
		if npc.npc_id == story.kuda_data.npc_id and story.can_begin_kuda_surface_reveal():
			first_land_ids.append(npc.npc_id)
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, 0.45)
	(_sea.get_node("SeaDiveInventory") as SeaDiveInventory).lose_catch()
	(_sea.get_node("SeaOxygen") as SeaOxygen).end_dive()
	_world_player.global_position = shore_return_position
	_world_player.last_direction = 1.0 # Inland after being rescued, too.
	_world_player.set_swimming(false)
	_world_player.animator.rotation = 0.0
	_world_player.animator.play(&"idle_r")
	_camera_controller.set_underwater_mode(false)
	_camera_controller.snap_to_player()
	underwater = false
	_sea.call("_set_camera_bounds", false)
	_dialogue_ui.set_underwater_mode(false)
	GameManager.finish_dive_period()

	# Under the fade, returning fish reach land and transform. In the
	# emergency-care version Penni brought the injured fish herself.
	var humans: Array[Node2D] = []
	var dock_wait := _sea.get_node("Points/SilasDockWait") as Marker2D
	for i in range(returning.size()):
		var npc: NPCData = returning[i]
		if silas_first_land_care and npc == story.silas_data:
			# Silas has NOT transformed yet. Keep his real fish actor on the
			# sea side so the original shore jump and poof can happen.
			continue
		var actor: Node2D = _party_entrance.stage_surface_actor(
			npc, _party_entrance.surface_dock_position(
				dock_wait.global_position, i))
		if actor != null:
			actor.show()
			humans.append(actor)
	# Usual oxygen/Kuda rescues still stage everyone as human. The special
	# Silas-care return must not hide his fish before the first-land jump.
	if not silas_first_land_care:
		_sea.end_diving_party()
	await fade.fade_to(0.0, 0.55)
	fade.queue_free()
	if silas_first_land_care:
		# Penni came up to find help, but Silas followed her. Reuse the
		# entire original entrance-to-land choreography and its dialogue:
		# approach, jump, warning, poof, introduction and townhouse.
		await (_sea.get_node("EncounterSequence") as SeaEncounterSequence).play_silas_surface_reveal(true)
		first_land_ids.erase(story.silas_data.npc_id)
	if not humans.is_empty():
		await _resolve_shore_stories(humans, cared_for == null, first_land_ids,
			null if silas_first_land_care else cared_for)
		await _clear_returning_party(humans)
	elif silas_first_land_care:
		_sea.end_diving_party()
	transitioning = false
	_world_player.busy = false
	surface_completed.emit()


# Reuse the same iris for non-diving cutscenes and room overlays.
# The caller changes what is visible only while the screen is closed.
func iris_swap(content_swap: Callable, screen_center: Vector2 = Vector2(0.5, 0.5)) -> void:
	if transitioning:
		return
	transitioning = true
	await _close_iris(screen_center)
	content_swap.call()
	await _open_iris(screen_center)
	transitioning = false


func _normalized_screen_position(actor: Node2D) -> Vector2:
	# The boat/intro iris still uses the single island-world viewport.
	var point: Vector2 = actor.get_global_transform_with_canvas().origin
	var view_size: Vector2 = Vector2(actor.get_viewport().get_visible_rect().size)
	return Vector2(
		clampf(point.x / maxf(view_size.x, 1.0), 0.0, 1.0),
		clampf(point.y / maxf(view_size.y, 1.0), 0.0, 1.0)
	)


func _close_iris(at: Vector2) -> void:
	_configure_iris(at)
	_iris.show()
	await _animate_iris(IRIS_OPEN_RADIUS, 0.0)


func _open_iris(at: Vector2) -> void:
	_configure_iris(at)
	await _animate_iris(0.0, IRIS_OPEN_RADIUS)
	_iris.hide()


func _configure_iris(at: Vector2) -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	_iris_material.set_shader_parameter("center_uv", at)
	_iris_material.set_shader_parameter(
		"aspect_ratio", view_size.x / maxf(view_size.y, 1.0)
	)


func _animate_iris(start_radius: float, end_radius: float) -> void:
	_set_iris_radius(start_radius)
	var tween: Tween = create_tween()
	tween.tween_method(_set_iris_radius, start_radius, end_radius, IRIS_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _set_iris_radius(value: float) -> void:
	_iris_material.set_shader_parameter("radius", value)
