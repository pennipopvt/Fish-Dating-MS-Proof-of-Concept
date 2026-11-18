extends Control

# Keeps the existing island as the real overworld. Only the dock's fishing
# interaction changes: jump -> circular iris -> persistent diving lagoon.
const SILAS_SCENE: PackedScene = preload("res://prefabs/silas.tscn")
const SILAS_FISH_DATA: FishData = preload("res://resources/fish/silas.tres")
const FISH_CO_OPERATOR: NPCData = preload("res://resources/npcs/fish_co_operator.tres")
const DOCK_CONFIRM: NPCData = preload("res://resources/npcs/dock_dive_prompt.tres")
const RIPPLE: Texture2D = preload("res://sprites/environment/medium_ripple_a.png")
const POOF_SHEET: Texture2D = preload("res://sprites/characters/poof.png")
const DIVE_DURATION: float = 0.43
const IRIS_DURATION: float = 0.52
const IRIS_OPEN_RADIUS: float = 2.6

@onready var _world: Node2D = $SubViewportContainer/SubViewport/World
@onready var _world_player: Player = $SubViewportContainer/SubViewport/World/Player
@onready var _diving_layer: CanvasLayer = $DivingLayer
@onready var _diving_scene: Control = $DivingLayer/DivingPrototype
@onready var _lagoon: DivingWorld = $DivingLayer/DivingPrototype/SubViewportContainer/SubViewport/Lagoon
@onready var _iris: ColorRect = $TransitionLayer/Iris
@onready var _music: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var _dialogue_ui: DialogueUI = $CanvasLayer/DialogueUI
@onready var _shop_menu: ShopMenu = $CanvasLayer/ShopMenu
@onready var _intro_layer: CanvasLayer = $IntroLayer
@onready var _intro: FishCoIntro = $IntroLayer/FishCoIntro

var _iris_material: ShaderMaterial
var _underwater: bool = false
var _transitioning: bool = false
var _shore_return_position: Vector2 = Vector2(56.0, 112.0)
var _silas_actor: NPCInteractable
var _silas_recruited: bool = false
var _contract_call_finished: bool = false
var _first_quota_opened: bool = false
var _first_dive_call_started: bool = false
var _first_dive_call_finished: bool = false
var _dock_confirmation_target: Node2D
var _dock_confirmation_yes: bool = false


func _ready() -> void:
	_diving_layer.visible = false
	_diving_layer.process_mode = Node.PROCESS_MODE_DISABLED
	_iris.hide()
	_iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_iris_material = (_iris.material as ShaderMaterial).duplicate() as ShaderMaterial
	_iris.material = _iris_material
	_set_iris_radius(IRIS_OPEN_RADIUS)
	_lagoon.set_embedded_mode(true)
	_lagoon.surface_requested.connect(_on_surface_requested)
	# Both scenes currently use the same theme. Keep one copy playing.
	(_diving_scene.get_node("Music") as AudioStreamPlayer).stop()
	DialogueManager.conversation_finished.connect(_on_reveal_conversation_finished)
	_intro_layer.hide()
	DialogueManager.conversation_finished.connect(_on_contract_conversation_finished)
	DialogueManager.conversation_finished.connect(_on_first_dive_conversation_finished)
	DialogueManager.choice_resolved.connect(_on_dock_choice_resolved)
	DialogueManager.conversation_finished.connect(_on_dock_confirmation_finished)
	ShopManager.shop_opened.connect(_on_first_quota_opened)
	ShopManager.shop_closed.connect(_on_first_quota_closed)
	_start_contract_call.call_deferred()


func _start_contract_call() -> void:
	# The opening assumes Penni has already entered the competition. She
	# learns she is employed through the phone call, not a separate signup.
	if _contract_call_finished:
		return
	_world_player.busy = true
	_shop_menu.set_quota_only(true)
	_intro_layer.show()
	_intro.play()
	# The same DialogueManager/DialogueUI, NPCData, and graph loader used for
	# every other conversation. Speaker tags in the JSON distinguish Penni
	# from the Fish Co representative while both normal portraits remain.
	DialogueManager.request_conversation(FISH_CO_OPERATOR, "res://dialogue/fish_co_phone_intro.json")
	if not DialogueManager.is_active:
		push_error("Fish Co. introductory dialogue failed to open.")
		_on_contract_call_finished()


func _on_contract_conversation_finished(npc: NPCData) -> void:
	if _contract_call_finished or npc != FISH_CO_OPERATOR:
		return
	_on_contract_call_finished()


func _on_contract_call_finished() -> void:
	# Close the SAME iris used for diving, switch from boat to dock while
	# black, then reveal the island. Don't auto-open the terminal: its
	# familiar exclamation bubble guides the player's first interaction.
	_contract_call_finished = true
	_transitioning = true
	_world_player.busy = true
	_transition_contract_to_dock()


func _transition_contract_to_dock() -> void:
	await _close_iris(Vector2(0.5, 0.5))
	_intro.end()
	_intro_layer.hide()

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
	_transitioning = false
	_world_player.busy = false


# The first terminal visit is the prerequisite for the second Fish Co call.
# Reuse ShopManager signals instead of inventing a second terminal or flag
# inside the menu; subsequent visits must never replay the call.
func _on_first_quota_opened() -> void:
	if _contract_call_finished and not _transitioning and not _first_dive_call_started:
		_first_quota_opened = true


func _on_first_quota_closed() -> void:
	if not _first_quota_opened or _first_dive_call_started or _first_dive_call_finished:
		return
	_first_dive_call_started = true
	_start_first_dive_call.call_deferred()


func _start_first_dive_call() -> void:
	if not _first_dive_call_started or _first_dive_call_finished or _transitioning or _underwater:
		return
	if DialogueManager.is_active or ShopManager.is_shop_open:
		return
	_world_player.busy = true
	DialogueManager.request_conversation(
		FISH_CO_OPERATOR, "res://dialogue/fish_co_first_dive.json"
	)
	if not DialogueManager.is_active:
		push_error("Fish Co. first-dive onboarding dialogue could not open.")
		# Don't leave Penni permanently locked if dialogue data is missing.
		_finish_first_dive_call()


func _on_first_dive_conversation_finished(npc: NPCData) -> void:
	if npc != FISH_CO_OPERATOR or not _first_dive_call_started or _first_dive_call_finished:
		return
	_finish_first_dive_call()


func _finish_first_dive_call() -> void:
	_first_dive_call_finished = true
	_world_player.busy = false
	var dock: Node2D = _world.get_node("Dock") as Node2D
	# Existing InteractPrompt is visible from a distance the first time,
	# then returns to ordinary proximity behavior once diving begins.
	dock.call("set_first_dive_prompt", true)


# Called by Dock.interact using the real world Player and Dock instances.
func request_dive(fisher: Player, dock: Node2D) -> void:
	if not _first_dive_call_finished or _transitioning or _underwater or fisher != _world_player:
		return
	if not GameManager.can_act() or DialogueManager.is_active or GameManager.is_modal_ui_open():
		return
	if _dock_confirmation_target != null:
		return
	# A normal dialogue graph provides the Yes/No choice; the player does
	# not dive until the Yes choice finishes through DialogueManager.
	_dock_confirmation_target = dock
	_dock_confirmation_yes = false
	DialogueManager.request_conversation(
		DOCK_CONFIRM, "res://dialogue/dock_dive_confirmation.json"
	)
	if not DialogueManager.is_active:
		_dock_confirmation_target = null


func _on_dock_choice_resolved(npc: NPCData, choice: Dictionary) -> void:
	if npc != DOCK_CONFIRM or _dock_confirmation_target == null:
		return
	_dock_confirmation_yes = str(choice.get("dive_decision", "")) == "yes"


func _on_dock_confirmation_finished(npc: NPCData) -> void:
	if npc != DOCK_CONFIRM or _dock_confirmation_target == null:
		return
	var dock: Node2D = _dock_confirmation_target
	var confirmed: bool = _dock_confirmation_yes
	_dock_confirmation_target = null
	_dock_confirmation_yes = false
	if confirmed:
		_start_confirmed_dive(dock)


func _start_confirmed_dive(dock: Node2D) -> void:
	if _transitioning or _underwater:
		return
	_transitioning = true
	# Other terminal pages become available only once the player actually
	# chooses to dive, never when they merely read the dock prompt.
	_shop_menu.set_quota_only(false)
	dock.call("mark_dive_started")
	_world_player.busy = true
	_shore_return_position = dock.global_position + Vector2(21.0, 11.0)
	_begin_dive(dock)


func _begin_dive(dock: Node2D) -> void:
	var jump_start: Vector2 = _world_player.global_position
	var landing: Vector2 = dock.global_position + Vector2(-11.0, 46.0)
	_world_player.animator.play(&"walk_l")
	var jump: Tween = create_tween()
	jump.tween_method(
		_update_dive_jump.bind(jump_start, landing),
		0.0, 1.0, DIVE_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await jump.finished
	_spawn_splash(landing)
	# Use the real camera-transformed position of the impact, not a fixed
	# screen center: this is where the black circle must close around.
	await _close_iris(_normalized_screen_position(_world_player))

	_world_player.hide()
	_diving_layer.visible = true
	_dialogue_ui.set_underwater_mode(true)
	_lagoon.enter_from_dock()
	_underwater = true
	GameManager.diving_session_active = true
	await _open_iris(_normalized_screen_position(_lagoon.get_node("Player") as Node2D))
	_diving_layer.process_mode = Node.PROCESS_MODE_INHERIT
	_transitioning = false


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


func _on_surface_requested(with_silas: bool) -> void:
	if _transitioning or not _underwater:
		return
	_transitioning = true
	# Freeze underwater movement and net clicks while the circle closes.
	_diving_layer.process_mode = Node.PROCESS_MODE_DISABLED
	_surface_from_dive(with_silas)


func _surface_from_dive(with_silas: bool) -> void:
	await _close_iris(_normalized_screen_position(_lagoon.get_node("Player") as Node2D))
	_diving_layer.visible = false
	_diving_layer.process_mode = Node.PROCESS_MODE_DISABLED
	_dialogue_ui.set_underwater_mode(false)
	_world_player.global_position = _shore_return_position
	_world_player.show()
	_world_player.animator.rotation = 0.0
	_world_player.animator.play(&"idle_l")
	_underwater = false
	GameManager.diving_session_active = false
	# A full dive spends one normal-world action, not one per net capture.
	GameManager.spend_actions(1)

	var reveal_silas: bool = with_silas and not _silas_recruited and not is_instance_valid(_silas_actor)
	if reveal_silas:
		_place_silas_on_dock()
	await _open_iris(_normalized_screen_position(_world_player))
	if reveal_silas:
		await _show_silas_transformation()
	_transitioning = false
	_world_player.busy = false


func _place_silas_on_dock() -> void:
	_silas_actor = SILAS_SCENE.instantiate() as NPCInteractable
	_world.add_child(_silas_actor)
	_silas_actor.global_position = _shore_return_position + Vector2(33.0, 0.0)
	var human: AnimatedSprite2D = _silas_actor.get_node("Sprite") as AnimatedSprite2D
	human.hide()


func _show_silas_transformation() -> void:
	if not is_instance_valid(_silas_actor):
		return
	# Show the same four-frame poof sprite as the original catch sequence,
	# but this time it happens because Silas CHOSE to accompany Penni.
	var frames := SpriteFrames.new()
	frames.add_animation(&"transform")
	frames.set_animation_loop(&"transform", false)
	frames.set_animation_speed(&"transform", 12.0)
	for i in range(4):
		var cutout := AtlasTexture.new()
		cutout.atlas = POOF_SHEET
		cutout.region = Rect2(float(i * 32), 0.0, 32.0, 32.0)
		frames.add_frame(&"transform", cutout)
	var poof := AnimatedSprite2D.new()
	poof.sprite_frames = frames
	poof.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	poof.z_index = 25
	_world.add_child(poof)
	poof.global_position = _silas_actor.global_position + Vector2(0, -14)
	poof.play(&"transform")
	await poof.animation_finished
	poof.queue_free()
	if not is_instance_valid(_silas_actor):
		return
	(_silas_actor.get_node("Sprite") as AnimatedSprite2D).show()
	# Reuse the original game's dialogue portrait/UI while giving the new
	# diving encounter its own first-on-land lines (not the caught-fish story).
	DialogueManager.request_conversation(
		_silas_actor.npc, "res://dialogue/silas_surface_reveal.json"
	)


func _on_reveal_conversation_finished(npc: NPCData) -> void:
	if npc == null or npc.npc_id != &"test_npc" or _silas_recruited:
		return
	if not is_instance_valid(_silas_actor):
		return
	# The same recruitment/housing mechanism as the original fishing game.
	# This removes Silas from the ordinary catch pool and enables his town
	# interactions after he agrees to live above water.
	if RecruitmentHandler.recruit_actor_for_debug(_silas_actor, SILAS_FISH_DATA):
		_silas_recruited = true


func _normalized_screen_position(actor: Node2D) -> Vector2:
	# Both the island and diving area render into separate 320x180 viewports
	# which fill the same display. Normalizing canvas coordinates maps the
	# actual splash/player position to the iris's fullscreen ColorRect UV.
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
	var view_size: Vector2 = get_viewport_rect().size
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
