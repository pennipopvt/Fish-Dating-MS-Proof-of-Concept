extends Control

# The ONE owner of the existing World/SubViewport and its UI.
# No story state, shader tween, bubble reconstruction, or diagnostic
# rendering lives here. The Dock still calls request_dive() on Main.
@onready var _world: Node2D = $SubViewportContainer/SubViewport/World
@onready var _world_player: Player = $SubViewportContainer/SubViewport/World/Player
@onready var _sea: DivingWorld = $SubViewportContainer/SubViewport/World/Sea
@onready var _transition: SeaDiveTransition = $TransitionLayer
@onready var _bubble_host: SeaSpeechBubbleHost = $SeaSpeechBubbleHost
@onready var _debug: SeaDebugPanel = $SeaDebugLayer
@onready var _water_debug: WaterRenderDebug = $WaterDebugLayer
@onready var _room_view: NPCRoomView = $NPCRoomView
var _opening: FishCoOpeningSequence

# Read-only compatibility properties for existing in-engine playtests.
# Actual state is held by the one owning component, not duplicated here.
var _underwater: bool:
	get: return _transition.underwater
var _transitioning: bool:
	get: return _transition.transitioning
var _contract_call_finished: bool:
	get: return _opening._contract_call_finished
var _first_dive_call_finished: bool:
	get: return _opening._first_dive_call_finished
var _intro_layer: CanvasLayer:
	get: return _opening
var _intro: FishCoIntro:
	get: return _opening.get_node_or_null("FishCoIntro") as FishCoIntro
var _sea_bubble_source: String:
	get: return _bubble_host.source


func _ready() -> void:
	_opening = get_node_or_null("IntroLayer") as FishCoOpeningSequence
	if _opening == null:
		# Repair a partially missing opening layer without duplicating
		# FishCoIntro in normal play.
		var old_layer: Node = get_node_or_null("IntroLayer")
		if old_layer != null:
			old_layer.name = "UnusableIntroLayer"
			old_layer.queue_free()
		_opening = FishCoOpeningSequence.new()
		_opening.name = "IntroLayer"
		_opening.layer = 9
		add_child(_opening)
	_transition.configure(_world, _world_player, _sea,
		$CanvasLayer/DialogueUI, $CanvasLayer/ShopMenu, _opening)
	_opening.configure(_world, _world_player, $CanvasLayer/ShopMenu, _transition)
	($IslandStoryDirector as IslandStoryDirector).configure(_world_player, _transition, _opening)
	_opening.dive_confirmed.connect(_transition.start_confirmed_dive)
	_bubble_host.configure(self, _sea.get_node_or_null("StoryDirector") as SeaStoryDirector)
	_room_view.configure($CanvasLayer/DialogueUI, _transition, _world_player,
		$IllustrationScene as IllustrationSceneController)
	for node in _world.get_node("AvailableHomeList").get_children():
		var door: TransferDoor = node as TransferDoor
		if door != null:
			door.room_requested.connect(_on_townhouse_room_requested)
	var player_door: TransferDoor = _world.get_node_or_null("PenniRoomDoor") as TransferDoor
	if player_door != null:
		player_door.room_requested.connect(_on_townhouse_room_requested)
	# Main only connects existing story, terminal UI, and world notice signals.
	# No tutorial flags or shop logic belong in the world transition.
	var terminal_menu: ShopMenu = $CanvasLayer/ShopMenu
	var terminal_actor: ShopInteractable = _world.get_node("Shop") as ShopInteractable
	terminal_menu.progression_notice_changed.connect(terminal_actor.set_progression_notice)
	terminal_menu.challenges_availability_changed.connect(
		terminal_actor.set_challenge_notice_enabled
	)
	(_sea.get_node("StoryDirector") as SeaStoryDirector).silas_townhouse_arrival_finished.connect(
		terminal_menu.unlock_post_dive_storage
	)
	terminal_actor.set_progression_notice(terminal_menu._pending_progression_notice())
	terminal_actor.set_challenge_notice_enabled(
		terminal_menu.is_page_unlocked(ShopMenu.Page.CHALLENGES)
	)
	_debug.configure(self, _world_player, _sea, _bubble_host)
	_water_debug.configure(_world, $SubViewportContainer/SubViewport, _world_player)
	_opening.start.call_deferred()


func _on_townhouse_room_requested(door: TransferDoor) -> void:
	if _transition.transitioning or DateManager.is_active():
		return
	if door.get_room_id() == &"penni_room":
		_room_view.open_player_room()
		return
	var resident: NPCData = RecruitmentHandler.get_resident(door.get_room_id())
	if resident == null:
		return
	# The room always opens first; NPCRoomView owns the short Yes/Not yet
	# invitation when this resident has a booking in the current period.
	# DateManager starts the outing only AFTER the room iris closes.
	_room_view.open_room(resident)


# A stable island Dock API. All confirmation belongs to the opening flow.
func request_dive(fisher: Player, dock: Node2D) -> void:
	_opening.request_dive(fisher, dock)


# Diving-only API; no character needs to exist in the world to be invited.
func invite_diving_companion(npc: NPCData) -> bool:
	return ($TransitionLayer/DivingParty as DivingParty).invite(npc)


func dismiss_diving_companion(npc_id: StringName) -> bool:
	return ($TransitionLayer/DivingParty as DivingParty).dismiss(npc_id)


# Single input boundary; debug controls and underwater input are delegated.
func _input(event: InputEvent) -> void:
	# The F3 DevPanel autoload owns every developer shortcut and menu.
	# SeaDebugPanel and WaterRenderDebug are read-only/visual diagnostic providers.
	if _world_player.swimming and _transition.underwater and not _transition.transitioning:
		if _sea.handle_input(event):
			get_viewport().set_input_as_handled()


# Existing debug/regression hooks delegate to their actual owners.
func _ensure_sea_speech_bubble() -> SeaSpeechBubble:
	return _bubble_host.ensure_bubble()


func _debug_skip_dialogue() -> void:
	_debug.skip_dialogue()
