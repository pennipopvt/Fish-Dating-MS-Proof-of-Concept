extends Control

# Keeps the existing island as the real overworld. Only the dock's fishing
# interaction changes: jump -> circular iris -> persistent diving sea.
const FISH_CO_OPERATOR: NPCData = preload("res://resources/npcs/fish_co_operator.tres")
const DOCK_CONFIRM: NPCData = preload("res://resources/npcs/dock_dive_prompt.tres")
const RIPPLE: Texture2D = preload("res://sprites/environment/medium_ripple_a.png")
const FISH_CO_INTRO_SCENE: PackedScene = preload("res://scenes/fish_co_intro.tscn")
const DIVE_DURATION: float = 0.43
const IRIS_DURATION: float = 0.52
const IRIS_OPEN_RADIUS: float = 2.6

@onready var _world: Node2D = $SubViewportContainer/SubViewport/World
@onready var _world_player: Player = $SubViewportContainer/SubViewport/World/Player
@onready var _sea: DivingWorld = $SubViewportContainer/SubViewport/World/Sea
@onready var _iris: ColorRect = $TransitionLayer/Iris
@onready var _dialogue_ui: DialogueUI = $CanvasLayer/DialogueUI
@onready var _shop_menu: ShopMenu = $CanvasLayer/ShopMenu
# A partially loaded/hot-reloaded scene can omit the optional intro subtree.
# Resolve it safely and restore only those nodes when they are missing.
@onready var _intro_layer: CanvasLayer = get_node_or_null("IntroLayer") as CanvasLayer
@onready var _intro: FishCoIntro = get_node_or_null("IntroLayer/FishCoIntro") as FishCoIntro

var _iris_material: ShaderMaterial
var _underwater: bool = false
var _transitioning: bool = false
var _shore_return_position: Vector2 = Vector2(56.0, 112.0)
var _contract_call_finished: bool = false
var _first_quota_opened: bool = false
var _first_dive_call_started: bool = false
var _first_dive_call_finished: bool = false
var _dock_confirmation_target: Node2D
var _dock_confirmation_yes: bool = false

# Diagnostic UI is created only under Main and starts hidden. F7 shows
# trigger and bubble state; press B while F7 is open to test the renderer.
var _sea_debug_layer: CanvasLayer
var _sea_debug_label: Label
var _sea_debug_elapsed: float = 0.0
var _sea_debug_last_transition: String = ""
var _sea_bubble_source: String = "uninitialized"


func _ready() -> void:
	_iris.hide()
	_iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_iris_material = (_iris.material as ShaderMaterial).duplicate() as ShaderMaterial
	_iris.material = _iris_material
	_set_iris_radius(IRIS_OPEN_RADIUS)
	_sea.surface_requested.connect(_on_surface_requested)
	# SeaStoryDirector is inside the game SubViewport, but this speech
	# bubble is in Main's outer UI CanvasLayer. Pass the real instance in
	# directly instead of trying to discover it across viewport parents.
	var story: SeaStoryDirector = _sea.get_node_or_null("StoryDirector") as SeaStoryDirector
	var speech: SeaSpeechBubble = _ensure_sea_speech_bubble()
	if story != null:
		story.bind_speech_bubble(speech)
	_setup_sea_debug()
	# The sea is a child of the one live World; there is only one music player.
	_ensure_intro_nodes()
	if _intro_layer != null:
		_intro_layer.hide()
	DialogueManager.conversation_finished.connect(_on_contract_conversation_finished)
	DialogueManager.conversation_finished.connect(_on_first_dive_conversation_finished)
	DialogueManager.choice_resolved.connect(_on_dock_choice_resolved)
	DialogueManager.conversation_finished.connect(_on_dock_confirmation_finished)
	ShopManager.shop_opened.connect(_on_first_quota_opened)
	ShopManager.shop_closed.connect(_on_first_quota_closed)
	_start_contract_call.call_deferred()




# The live F7 screenshot proved the actual Main/SeaSpeechBubble node was
# missing (not merely invisible). The authored scene is preferred, but
# don't let a missing/partially imported scene swallow the story event.
func _ensure_sea_speech_bubble() -> SeaSpeechBubble:
	var existing: Node = get_node_or_null("SeaSpeechBubble")
	if existing is SeaSpeechBubble and existing.is_node_ready():
		_sea_bubble_source = "authored scene"
		return existing as SeaSpeechBubble

	if existing != null:
		push_warning("[SEA UI] SeaSpeechBubble exists but is not a ready SeaSpeechBubble (class=%s); rebuilding." % existing.get_class())
		existing.name = "UnusableSeaSpeechBubble"
		existing.queue_free()
	else:
		push_warning("[SEA UI] Main/SeaSpeechBubble is missing; rebuilding it.")

	# First try the exact existing authored PackedScene. This is a runtime
	# load, not an extra scene dependency in Main.
	var resource: PackedScene = load("res://scenes/sea_speech_bubble.tscn") as PackedScene
	if resource != null:
		var node: Node = resource.instantiate()
		if node is SeaSpeechBubble and node.has_node("Call/Frame") and node.has_node("Call/Message") and node.has_node("Call/Tail") and node.has_node("Hint"):
			node.name = "SeaSpeechBubble"
			add_child(node)
			var result: SeaSpeechBubble = node as SeaSpeechBubble
			if result.is_node_ready():
				_sea_bubble_source = "recovered PackedScene"
				print("[SEA UI] Recovered original bubble scene under Main.")
				return result
			node.name = "UnreadySeaSpeechBubble"
			node.queue_free()
		else:
			node.free()

	# Last resort: make the SAME SeaSpeechBubble class and expected child
	# names in memory. It draws a plain fallback panel even when textures
	# or scene imports are unavailable.
	var bubble: SeaSpeechBubble = SeaSpeechBubble.new()
	bubble.name = "SeaSpeechBubble"
	bubble.layer = 8
	var call: Control = Control.new()
	call.name = "Call"
	call.size = Vector2(96.0, 38.0)
	call.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call.hide()
	bubble.add_child(call)

	var tail: TextureRect = TextureRect.new()
	tail.name = "Tail"
	tail.size = Vector2(24.0, 24.0)
	tail.pivot_offset = Vector2(12.0, 12.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tail.hide()
	call.add_child(tail)

	var fallback: Panel = Panel.new()
	fallback.name = "Fallback"
	fallback.size = call.size
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color.BLACK
	style.set_border_width_all(3)
	fallback.add_theme_stylebox_override("panel", style)
	call.add_child(fallback)

	var frame: NinePatchRect = NinePatchRect.new()
	frame.name = "Frame"
	frame.size = call.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.hide()
	call.add_child(frame)

	var message: Label = Label.new()
	message.name = "Message"
	message.position = Vector2(9.0, 6.0)
	message.size = Vector2(78.0, 26.0)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.add_theme_color_override("font_color", Color.BLACK)
	message.add_theme_font_size_override("font_size", 14)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	call.add_child(message)

	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.hide()
	bubble.add_child(hint)

	# Optional originals: never require these imports for a basic bubble.
	bubble.bubble_texture = load("res://sprites/ui/speech_bubble.png") as Texture2D
	bubble.tail_texture = load("res://sprites/ui/speech_marker.png") as Texture2D
	var pixel_font: Font = load("res://fonts/pixel_operator(1)/PixelOperator.ttf") as Font
	if pixel_font != null:
		message.add_theme_font_override("font", pixel_font)
	add_child(bubble)
	_sea_bubble_source = "runtime fallback"
	print("[SEA UI] Built fallback bubble under Main; ready=%s" % str(bubble.is_node_ready()))
	return bubble


# Debug controls are intentionally outside the SubViewport. in a dedicated
# hidden CanvasLayer, so a missing game-viewport widget can't hide diagnostics.
func _setup_sea_debug() -> void:
	_sea_debug_layer = CanvasLayer.new()
	_sea_debug_layer.name = "SeaDebugLayer"
	_sea_debug_layer.layer = 120
	_sea_debug_layer.visible = false
	add_child(_sea_debug_layer)

	var panel: Panel = Panel.new()
	panel.name = "Panel"
	panel.position = Vector2(10.0, 10.0)
	panel.size = Vector2(800.0, 535.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.015, 0.035, 0.06, 0.93)
	background.border_color = Color(0.5, 0.9, 1.0, 1.0)
	background.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", background)
	_sea_debug_layer.add_child(panel)

	_sea_debug_label = Label.new()
	_sea_debug_label.name = "Diagnostics"
	_sea_debug_label.position = Vector2(12.0, 10.0)
	_sea_debug_label.size = Vector2(775.0, 505.0)
	_sea_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sea_debug_label.add_theme_font_size_override("font_size", 17)
	panel.add_child(_sea_debug_label)


func _process(delta: float) -> void:
	if not _underwater and (_sea_debug_layer == null or not _sea_debug_layer.visible):
		return
	_sea_debug_elapsed += delta
	if _sea_debug_elapsed < 0.25:
		return
	_sea_debug_elapsed = 0.0
	_update_sea_debug()


func _update_sea_debug() -> void:
	var story: SeaStoryDirector = _sea.get_node_or_null("StoryDirector") as SeaStoryDirector
	var silas: Node2D = _sea.get_node_or_null("NPCs/Silas") as Node2D
	var raw_bubble: Node = get_node_or_null("SeaSpeechBubble")
	var ui: SeaSpeechBubble = raw_bubble as SeaSpeechBubble
	var call: Control
	var events: Dictionary = {}
	var speaker: Node
	var display: Node
	if ui != null:
		call = ui.get_node_or_null("Call") as Control
		speaker = ui.get("_speaker") as Node
		display = ui.get("_display") as Node
	if story != null:
		events = story.get("_events") as Dictionary
	var distance: float = _world_player.global_position.distance_to(silas.global_position) if silas != null else INF
	var near_silas: bool = distance <= 108.0
	var escaped: bool = bool(_sea.get("_first_fish_escape_finished"))
	var follow_x: float = float(_sea.get("_help_reveal_x"))
	var followed: bool = escaped and _world_player.position.x <= follow_x
	var line_broken: bool = bool(events.get(&"line_broken", false))
	var help_called: bool = bool(events.get(&"help_called", false))
	var bound: bool = story != null and ui != null and story.get("_speech_bubble") == ui
	var ready: bool = ui != null and ui.is_node_ready()
	var call_visible: bool = call != null and call.visible
	var call_on_tree: bool = call != null and call.is_visible_in_tree()
	var visible: bool = ui != null and ui.is_call_shown()
	var rect: Rect2 = call.get_global_rect() if call != null else Rect2()
	var battle: DivingCompanionBattle = _sea.get_node_or_null("CompanionBattle") as DivingCompanionBattle
	var fish: DivingWildFish = battle.target if battle != null and battle.is_active() else null
	var actor: SeaNPC = silas as SeaNPC
	var combat: DivingCombat = _sea.get_node_or_null("Combat") as DivingCombat

	var lines: PackedStringArray = PackedStringArray()
	lines.append("SEA DEBUG | F7 hide/show | B while open: UI TEST")
	lines.append("Swimming: %s   Main underwater: %s   UI parent: Main" % [
		str(_world_player.swimming), str(_underwater)])
	lines.append("Player: %s   Silas: %s" % [
		str(_world_player.global_position.round()),
		str(silas.global_position.round()) if silas != null else "MISSING"])
	lines.append("Silas distance: %.1f / 108   proximity trigger: %s" % [
		distance, str(near_silas)])
	lines.append("Line broke: %s   fish escaped: %s   followed left: %s" % [
		str(line_broken), str(escaped), str(followed)])
	lines.append("Player x: %.1f   follow threshold x: %.1f" % [
		_world_player.position.x, follow_x])
	lines.append("Expected help trigger now: %s   help_called flag: %s" % [
		str(followed or near_silas), str(help_called)])
	lines.append("Help UI pending: %s" % [
		str(story.get("_help_ui_pending")) if story != null else "MISSING"])
	lines.append("Story: %s   UI bound: %s   UI ready: %s" % [
		str(story != null), str(bound), str(ready)])
	lines.append("UI node: %s   source: %s" % [
		raw_bubble.get_class() if raw_bubble != null else "MISSING",
		_sea_bubble_source])
	lines.append("Call node visible: %s   in tree: %s   renderer says: %s" % [
		str(call_visible), str(call_on_tree), str(visible)])
	lines.append("Speaker valid: %s   display valid: %s" % [
		str(is_instance_valid(speaker)), str(is_instance_valid(display))])
	lines.append("Call screen rect: %s   viewport size: %s" % [
		str(rect), str(get_viewport_rect().size)])
	if ui != null:
		lines.append("Bubble: %s   active=%s" % [
			ui.bubble_debug_state(), str(ui.is_call_active())])
	lines.append("Silas following: %s   NPC refs (player/battle): %s/%s" % [
		str(actor.following) if actor != null else "MISSING",
		str(is_instance_valid(actor.get("_player"))) if actor != null else "false",
		str(is_instance_valid(actor.get("_battle"))) if actor != null else "false"])
	lines.append("Battle: %s   can fight: %s   exhausted: %s" % [
		str(battle.is_active()) if battle != null else "MISSING",
		str(battle.can_fight()) if battle != null else "false",
		str(battle.exhausted) if battle != null else "MISSING"])
	lines.append("Target: %s   fish HP: %.1f/%.1f   Silas HP: %.1f" % [
		String(fish.fish_name) if fish != null else "none",
		fish.health if fish != null else 0.0,
		fish.max_health if fish != null else 0.0,
		battle.health if battle != null else 0.0])
	lines.append("Silas movement: %s" % [
		actor.battle_debug_state() if actor != null else "MISSING"])
	var net: DivingNetProjectile = _sea.get_node_or_null("NetProjectile") as DivingNetProjectile
	lines.append("Net lesson: %s   reels=%d   line tension=%.2f" % [
		str(_sea.get("_scripted_reel_mode")),
		int(_sea.get("_scripted_reel_scrolls")),
		net.line_tension if net != null else 0.0])
	lines.append("Penni reaction=%s   Silas met/freed=%s/%s" % [
		str(story.has_event(&"penni_fish_reaction")) if story != null else "MISSING",
		str(story.has_silas_flag(&"silas_met")) if story != null else "MISSING",
		str(story.has_silas_flag(&"silas_freed")) if story != null else "MISSING"])
	lines.append("Combat: %s   last command: %s" % [
		str(combat.is_active()) if combat != null else "MISSING",
		str(_sea.get("_combat_debug_status"))])
	lines.append("Dialogue active: %s   modal UI: %s" % [
		str(DialogueManager.is_active), str(GameManager.is_modal_ui_open())])
	if _sea_debug_label != null:
		_sea_debug_label.text = "\n".join(lines)

	# Print only when discrete trigger/UI state changes, not on every frame.
	var transition: String = (
		"swim=%s near=%s escape=%s follow=%s broken=%s help=%s bound=%s shown=%s battle=%s"
		% [str(_world_player.swimming), str(near_silas), str(escaped),
			str(followed), str(line_broken), str(help_called),
			str(bound), str(visible), str(battle.is_active()) if battle != null else "MISSING"]
	)
	if transition != _sea_debug_last_transition:
		_sea_debug_last_transition = transition
		print("[SEA DEBUG] " + transition)


func _force_test_bubble() -> void:
	var ui: SeaSpeechBubble = get_node_or_null("SeaSpeechBubble") as SeaSpeechBubble
	if ui == null:
		ui = _ensure_sea_speech_bubble()
		var story: SeaStoryDirector = _sea.get_node_or_null("StoryDirector") as SeaStoryDirector
		if story != null:
			story.bind_speech_bubble(ui)
	if ui == null:
		push_error("[SEA DEBUG] B test failed: unable to create speech bubble")
		return
	ui.show_call("UI TEST: Help me!", false, 0.0)
	print("[SEA DEBUG] B test: ready=%s shown=%s Call rect=%s" % [
		str(ui.is_node_ready()), str(ui.is_call_shown()),
		str((ui.get_node("Call") as Control).get_global_rect())])
	if _sea_debug_layer != null:
		_sea_debug_layer.visible = true
	_update_sea_debug()


# The authored IntroLayer is preferred; don't duplicate it in normal play.
# If a partial scene import omitted it, recover the same FishCoIntro scene
# instead of crashing before the main menu/dialogue can initialize.
func _ensure_intro_nodes() -> void:
	_intro_layer = get_node_or_null("IntroLayer") as CanvasLayer
	if _intro_layer == null:
		_intro_layer = CanvasLayer.new()
		_intro_layer.name = "IntroLayer"
		_intro_layer.layer = 9
		add_child(_intro_layer)
	_intro = _intro_layer.get_node_or_null("FishCoIntro") as FishCoIntro
	if _intro == null:
		_intro = FISH_CO_INTRO_SCENE.instantiate() as FishCoIntro
		if _intro != null:
			_intro.name = "FishCoIntro"
			_intro_layer.add_child(_intro)


func _start_contract_call() -> void:
	# The opening assumes Penni has already entered the competition. She
	# learns she is employed through the phone call, not a separate signup.
	if _contract_call_finished:
		return
	_world_player.busy = true
	_shop_menu.set_quota_only(true)
	if _intro_layer == null or _intro == null:
		_ensure_intro_nodes()
	if _intro_layer != null and _intro != null:
		_intro_layer.show()
		_intro.play()
	else:
		push_warning("Fish Co intro backdrop unavailable; continuing the phone call.")
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
	if is_instance_valid(_intro):
		_intro.end()
	if is_instance_valid(_intro_layer):
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

	# No second world, teleport or viewport switch. The camera follows
	# Penni from the dock through the same surface into the ocean.
	_underwater = true
	GameManager.diving_session_active = true
	_dialogue_ui.set_underwater_mode(true)
	var entry_marker: Marker2D = _sea.get_node_or_null("Points/Entry") as Marker2D
	var entry: Vector2 = entry_marker.global_position if entry_marker != null else _sea.to_global(Vector2(55, 182))
	var island_camera: Camera2D = _world_player.get_node("Camera2D") as Camera2D
	var descent: Tween = create_tween().set_parallel(true)
	descent.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	descent.tween_property(_world_player, "global_position", entry, 0.85)
	descent.tween_property(island_camera, "position", Vector2.ZERO, 0.85)
	await descent.finished
	_world_player.animator.rotation = 0.0
	_sea.enter_from_dock()
	_world_player.busy = false
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


# Main receives mouse events before SubViewportContainer can consume them.
# Delegate underwater gameplay input to Sea; all land controls stay unchanged.
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_F7:
			if _sea_debug_layer != null:
				_sea_debug_layer.visible = not _sea_debug_layer.visible
				_update_sea_debug()
			print("[SEA DEBUG] F7 diagnostics: %s" % str(_sea_debug_layer.visible))
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_B and _sea_debug_layer != null and _sea_debug_layer.visible:
			_force_test_bubble()
			get_viewport().set_input_as_handled()
			return
	if _world_player.swimming and _underwater and not _transitioning:
		if _sea.handle_input(event):
			get_viewport().set_input_as_handled()


func _on_surface_requested() -> void:
	if _transitioning or not _underwater:
		return
	_transitioning = true
	_world_player.busy = true
	_surface_from_dive()


func _surface_from_dive() -> void:
	# Return through the SAME water surface. Sky stays visible in the camera;
	# there is no fade-to-black or replacement scene.
	var island_camera: Camera2D = _world_player.get_node("Camera2D") as Camera2D
	var ascent: Tween = create_tween().set_parallel(true)
	ascent.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ascent.tween_property(_world_player, "global_position", _shore_return_position, 0.85)
	ascent.tween_property(island_camera, "position", Vector2(0.0, -22.0), 0.85)
	await ascent.finished
	_world_player.set_swimming(false)
	_world_player.animator.rotation = 0.0
	_world_player.animator.play(&"idle_l")
	_underwater = false
	GameManager.diving_session_active = false
	_sea.call("_set_camera_bounds", false)
	_dialogue_ui.set_underwater_mode(false)
	# A dive costs one ordinary time action on surfacing.
	GameManager.spend_actions(1)

	_transitioning = false
	_world_player.busy = false


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
