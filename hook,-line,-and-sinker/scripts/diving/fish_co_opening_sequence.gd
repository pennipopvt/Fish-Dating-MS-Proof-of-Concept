extends CanvasLayer
class_name FishCoOpeningSequence

# Owns the Fish Co phone introduction, terminal prerequisite, and the
# dock's Yes/No choice. Does not animate world movement or own the iris.
signal dive_confirmed(dock: Node2D)

const FISH_CO_OPERATOR: NPCData = preload("res://resources/npcs/fish_co_operator.tres")
const DOCK_CONFIRM: NPCData = preload("res://resources/npcs/dock_dive_prompt.tres")
const FISH_CO_INTRO_SCENE: PackedScene = preload("res://scenes/fish_co_intro.tscn")

var _world: Node2D
var _world_player: Player
var _shop_menu: ShopMenu
var _transition: SeaDiveTransition
var _intro: FishCoIntro
var _intro_layer: CanvasLayer
var _contract_call_finished: bool = false
var _first_quota_opened: bool = false
var _first_dive_call_started: bool = false
var _first_dive_call_finished: bool = false
var _dock_confirmation_target: Node2D
var _dock_confirmation_yes: bool = false


func configure(world: Node2D, player: Player, shop: ShopMenu, transition: SeaDiveTransition) -> void:
	_world = world
	_world_player = player
	_shop_menu = shop
	_transition = transition
	_intro_layer = self
	_ensure_intro_nodes()
	hide()
	DialogueManager.conversation_finished.connect(_on_contract_conversation_finished)
	DialogueManager.conversation_finished.connect(_on_first_dive_conversation_finished)
	DialogueManager.choice_resolved.connect(_on_dock_choice_resolved)
	DialogueManager.conversation_finished.connect(_on_dock_confirmation_finished)
	ShopManager.shop_opened.connect(_on_first_quota_opened)
	ShopManager.shop_closed.connect(_on_first_quota_closed)


func start() -> void:
	_start_contract_call()


# Existing authored FishCoIntro takes priority; restore that same PackedScene
# if a hot reload dropped only its child, without cloning the world.
func _ensure_intro_nodes() -> void:
	_intro = get_node_or_null("FishCoIntro") as FishCoIntro
	if _intro == null:
		_intro = FISH_CO_INTRO_SCENE.instantiate() as FishCoIntro
		if _intro != null:
			_intro.name = "FishCoIntro"
			add_child(_intro)


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
	_transition.begin_intro_to_dock(_intro)


# The first terminal visit is the prerequisite for the second Fish Co call.
# Reuse ShopManager signals instead of inventing a second terminal or flag
# inside the menu; subsequent visits must never replay the call.
func _on_first_quota_opened() -> void:
	if _contract_call_finished and not _transition.transitioning and not _first_dive_call_started:
		_first_quota_opened = true


func _on_first_quota_closed() -> void:
	if not _first_quota_opened or _first_dive_call_started or _first_dive_call_finished:
		return
	_first_dive_call_started = true
	_start_first_dive_call.call_deferred()


func _start_first_dive_call() -> void:
	if not _first_dive_call_started or _first_dive_call_finished or _transition.transitioning or _transition.underwater:
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


# Debug (DevPanel F3): jump past the phone call, the first terminal visit and
# the first-dive call, leaving Penni on the dock with the dive prompt ready.
# Returns false when there is nothing left to skip or a transition is running.
func debug_skip_to_dive() -> bool:
	if _first_dive_call_finished or _transition.transitioning or _transition.underwater:
		return false
	# Mark every step done first so the conversation_finished handlers ignore
	# the dialogue we end below.
	_contract_call_finished = true
	_first_quota_opened = true
	_first_dive_call_started = true
	_first_dive_call_finished = true
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	if ShopManager.is_shop_open:
		_shop_menu.close()
		ShopManager.set_shop_open(false)
	if is_instance_valid(_intro):
		_intro.end()
	hide()
	var dock: Node2D = _world.get_node("Dock") as Node2D
	_world_player.global_position = dock.global_position + Vector2(22.0, 11.0)
	_world_player.animator.play(&"idle_l")
	var island_camera: Camera2D = _world_player.get_node("Camera2D") as Camera2D
	island_camera.reset_smoothing()
	island_camera.force_update_scroll()
	(_world.get_node("Shop") as ShopInteractable).set_intro_quota_notice(false)
	_finish_first_dive_call()
	return true


func request_dive(fisher: Player, dock: Node2D) -> void:
	if not _first_dive_call_finished or _transition.transitioning or _transition.underwater or fisher != _world_player:
		return
	if not GameManager.can_start_dive() or DialogueManager.is_active or GameManager.is_modal_ui_open():
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
		dive_confirmed.emit(dock)
