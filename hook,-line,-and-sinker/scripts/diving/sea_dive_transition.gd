extends CanvasLayer
class_name SeaDiveTransition

signal surface_completed

# Owns ONLY the physical one-world transitions: iris, dock jump,
# sea descent and surfacing. FishCoOpeningSequence handles choices.
const RIPPLE: Texture2D = preload("res://sprites/environment/medium_ripple_a.png")
const DIVE_DURATION: float = 0.43
const IRIS_DURATION: float = 0.52
const IRIS_OPEN_RADIUS: float = 2.6
# Penni dives facing left: the leap carries her this far forward before the
# splash, and she drifts a little further forward while sinking.
const DIVE_FORWARD: float = 18.0
const SINK_FORWARD: float = 10.0

@onready var _iris: ColorRect = $Iris
var _iris_material: ShaderMaterial
var _world: Node2D
var _world_player: Player
var _sea: DivingWorld
var _dialogue_ui: DialogueUI
var _shop_menu: ShopMenu
var _opening: CanvasLayer
var underwater: bool = false
var transitioning: bool = false
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
	_sea = sea
	_dialogue_ui = dialogue_ui
	_shop_menu = shop
	_opening = opening
	_sea.surface_requested.connect(_on_surface_requested)
	_sea.oxygen_return_requested.connect(_on_oxygen_return_requested)
	surface_completed.connect(_sea.on_surface_completed)
	# Story can request fish/human portraits for a conversation without
	# teaching this physical transition about any particular character.
	(_sea.get_node("StoryDirector") as SeaStoryDirector).dialogue_mode_requested.connect(
		_dialogue_ui.set_underwater_mode
	)


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
	_world_player.animator.play(&"idle_l")
	var island_camera: Camera2D = _world_player.get_node("Camera2D") as Camera2D
	island_camera.reset_smoothing()
	island_camera.force_update_scroll()
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
	var jump_start: Vector2 = _world_player.global_position
	# Splash a little ahead of where Penni stands (same waterline as before).
	var landing := Vector2(jump_start.x - DIVE_FORWARD, dock.global_position.y + 46.0)
	_world_player.animator.play(&"walk_l")
	var jump: Tween = create_tween()
	jump.tween_method(
		_update_dive_jump.bind(jump_start, landing),
		0.0, 1.0, DIVE_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await jump.finished
	_spawn_splash(landing)
	_sea.play_sfx(&"dive")

	# No second world, teleport or viewport switch. The camera follows
	# Penni from the dock through the same surface into the ocean.
	underwater = true
	GameManager.diving_session_active = true
	_dialogue_ui.set_underwater_mode(true)
	var entry_marker: Marker2D = _sea.get_node_or_null("Points/Entry") as Marker2D
	var entry: Vector2 = entry_marker.global_position if entry_marker != null else _sea.to_global(Vector2(55, 182))
	entry = _dive_target_below(landing + Vector2(-SINK_FORWARD, 0.0), entry.y)
	var island_camera: Camera2D = _world_player.get_node("Camera2D") as Camera2D
	var descent: Tween = create_tween().set_parallel(true)
	descent.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	descent.tween_property(_world_player, "global_position", entry, 0.85)
	descent.tween_property(island_camera, "position", Vector2.ZERO, 0.85)
	await descent.finished
	_world_player.animator.rotation = 0.0
	_sea.enter_from_dock()
	_world_player.busy = false
	transitioning = false


# Where Penni sinks to after the splash: down from the given point, as
# deep as the Entry marker's depth but stopping above any rock under her.
func _dive_target_below(splash: Vector2, depth: float) -> Vector2:
	var top: float = DivingWorld.SEA_TOP + DivingWildFish.EDGE_MARGIN
	var y: float = maxf(depth, top)
	while y > top and not _sea.call("_is_open_water", _sea.to_local(Vector2(splash.x, y))):
		y -= 2.0
	return Vector2(splash.x, y)


func _update_dive_jump(t: float, start: Vector2, landing: Vector2) -> void:
	# A readable leap above the dock before splashing below its waterline.
	_world_player.global_position = start.lerp(landing, t) + Vector2(0.0, -29.0 * sin(PI * t))
	_world_player.animator.rotation = -0.25 * sin(PI * t)


func _spawn_splash(at: Vector2) -> void:
	_world_player.animator.rotation = 0.0
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
	var island_camera: Camera2D = _world_player.get_node("Camera2D") as Camera2D
	var ascent: Tween = create_tween().set_parallel(true)
	ascent.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ascent.tween_property(_world_player, "global_position", shore_return_position, 0.85)
	ascent.tween_property(island_camera, "position", Vector2(0.0, -22.0), 0.85)
	await ascent.finished
	_world_player.set_swimming(false)
	_world_player.animator.rotation = 0.0
	_world_player.animator.play(&"idle_l")
	underwater = false
	_sea.call("_set_camera_bounds", false)
	_dialogue_ui.set_underwater_mode(false)
	# Catch safety is settled BEFORE the terminal and story process the return.
	(_sea.get_node("SeaDiveInventory") as SeaDiveInventory).secure_catch()
	(_sea.get_node("SeaOxygen") as SeaOxygen).end_dive()
	# Every completed dive uses the remaining morning/afternoon/night period.
	GameManager.finish_dive_period()

	transitioning = false
	_world_player.busy = false
	surface_completed.emit()


func _on_oxygen_return_requested() -> void:
	if transitioning or not underwater:
		return
	transitioning = true
	_world_player.busy = true
	_blackout_from_oxygen()


func _blackout_from_oxygen() -> void:
	# The ScreenFade already used by beds/relationship scenes gives the
	# failure a simple blackout. We do not perform the ordinary swim ascent.
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, 0.45)
	(_sea.get_node("SeaDiveInventory") as SeaDiveInventory).lose_catch()
	(_sea.get_node("SeaOxygen") as SeaOxygen).end_dive()
	_world_player.global_position = shore_return_position
	_world_player.set_swimming(false)
	_world_player.animator.rotation = 0.0
	_world_player.animator.play(&"idle_l")
	var island_camera: Camera2D = _world_player.get_node("Camera2D") as Camera2D
	island_camera.position = Vector2(0.0, -22.0)
	island_camera.reset_smoothing()
	island_camera.force_update_scroll()
	underwater = false
	_sea.call("_set_camera_bounds", false)
	_dialogue_ui.set_underwater_mode(false)
	GameManager.finish_dive_period()
	await fade.fade_to(0.0, 0.55)
	fade.queue_free()
	transitioning = false
	_world_player.busy = false
	surface_completed.emit()


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
