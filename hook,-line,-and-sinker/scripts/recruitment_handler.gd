extends Node

# Recruitment owns temporary NPC placement and the FIFO housing queue.
# NPCManager owns story flags; FishingManager owns the catch pool.
signal fade_to()
signal npc_waiting_for_home(actor: NPCInteractable)
signal npc_moved_into_home(actor: NPCInteractable, home: Sprite2D)

var listening: bool = false
var available_homes: Array[Sprite2D] = []
var waiting_npcs: Array[NPCInteractable] = []
# Kept for the developer panel's direct house_recruit shortcut.
var npc: NPCInteractable = null
# Capture the exact fish across FishingController.exit_fishing().
var pending_fish: FishData = null
var time_to_transfer: float = 0.8
var dock_wait_offset: Vector2 = Vector2(24.0, 0.0)
var dock_wait_spacing: float = 16.0

var _transfer_in_progress: bool = false
var _reserved_home: Sprite2D = null
var _transfer_generation: int = 0


func _ready() -> void:
	DialogueManager.conversation_finished.connect(check_for_recruitment)


func _process(_delta: float) -> void:
	# Also handles a house added directly to available_homes by older code.
	if not _transfer_in_progress and not waiting_npcs.is_empty() and _has_available_home():
		_try_place_waiting_npcs()


func engage_listen(transfer: NPCInteractable, caught_fish: FishData = null) -> void:
	# Only the initial conversation after catching this NPC may recruit it.
	npc = transfer
	pending_fish = caught_fish
	listening = _actor_valid(transfer)


func check_for_recruitment(finished_npc: NPCData) -> void:
	if not listening:
		return
	listening = false
	var caught_fish: FishData = pending_fish
	pending_fish = null
	var caught_actor: NPCInteractable = npc
	npc = null

	if finished_npc == null or not _actor_valid(caught_actor) or caught_actor.npc != finished_npc:
		return

	var flags: Dictionary = NPCManager.get_npc_state(finished_npc.npc_id).get("flags", {})
	if not flags.get(&"Recruited", false):
		# Declined NPCs remain in the catch pool for another chance.
		# Barracuda visibly hops back into the water on either failed path.
		if finished_npc.npc_id == &"barracuda":
			_barracuda_return_to_water(caught_actor)
		else:
			caught_actor.queue_free()
		return

	# Acceptance is permanent for this session, even before a house exists.
	FishingManager.remove_recruited_catch(caught_fish)
	_enqueue_accepted_actor(caught_actor)



# Barracuda's exit uses the existing world waterline rather than a new
# animation asset. He hops away from the dock and sinks off-screen, then
# despawns. Future catches still use the special return encounter.
func _barracuda_return_to_water(actor: NPCInteractable) -> void:
	if not _actor_valid(actor):
		return
	var start: Vector2 = actor.global_position
	var water := actor.get_parent().get_node_or_null("Water") as ColorRect
	var water_y: float = water.global_position.y if water != null else start.y + 40.0
	var landing := Vector2(start.x - 20.0, maxf(water_y + 18.0, start.y + 38.0))
	var jump := Vector2(start.x - 11.0, start.y - 13.0)
	var tween := actor.create_tween()
	tween.tween_property(actor, "global_position", jump, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor, "global_position", landing, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(actor.queue_free)


# Called by AvailableHomeInfo whenever the world sets up its empty houses.
func set_available_homes(homes: Array[Sprite2D]) -> void:
	available_homes.clear()
	for home in homes:
		if _home_valid(home) and not available_homes.has(home) and home != _reserved_home:
			available_homes.append(home)
	_try_place_waiting_npcs()


# Call this when building a new house, or after a previously occupied house
# has genuinely been vacated. Do not register a still-occupied house.
func register_available_home(home: Sprite2D) -> void:
	if not _home_valid(home) or home == _reserved_home or available_homes.has(home):
		return
	available_homes.append(home)
	_try_place_waiting_npcs()


# Cancel outstanding asynchronous transfers before a developer reset/reload.
func reset_runtime_state() -> void:
	_transfer_generation += 1
	if _home_valid(_reserved_home) and not available_homes.has(_reserved_home):
		available_homes.push_front(_reserved_home)
	_reserved_home = null
	_transfer_in_progress = false
	waiting_npcs.clear()
	listening = false
	npc = null
	pending_fish = null


func _enqueue_accepted_actor(actor: NPCInteractable) -> void:
	if not _actor_valid(actor):
		return
	if not waiting_npcs.has(actor):
		waiting_npcs.append(actor)
		_position_waiting_actor(actor)
		npc_waiting_for_home.emit(actor)
	_try_place_waiting_npcs()


func _position_waiting_actor(actor: NPCInteractable) -> void:
	# The caught NPC already appears at the dock. Anchor later queue entries
	# there too, instead of leaving them wherever their dialogue ended.
	var dock: Node2D = actor.get_parent().get_node_or_null("Dock") as Node2D
	if dock != null:
		var place: int = maxi(0, waiting_npcs.find(actor))
		actor.global_position = dock.global_position + dock_wait_offset + Vector2(dock_wait_spacing * place, 0.0)


func _try_place_waiting_npcs() -> void:
	if _transfer_in_progress:
		return
	while not waiting_npcs.is_empty():
		var actor: NPCInteractable = waiting_npcs.front()
		if not _actor_valid(actor):
			waiting_npcs.pop_front()
			continue
		var home: Sprite2D = _take_available_home()
		if home == null:
			return
		waiting_npcs.pop_front()
		_transfer_in_progress = true
		_reserved_home = home
		_transfer_actor(actor, home, _transfer_generation)
		return


func _transfer_actor(actor: NPCInteractable, home: Sprite2D, generation: int) -> void:
	# Reserve the house before the fade so parallel recruitments can't claim it.
	fade_to.emit()
	await get_tree().create_timer(maxf(0.0, time_to_transfer)).timeout
	if generation != _transfer_generation:
		return
	_reserved_home = null
	if _actor_valid(actor) and _home_valid(home):
		_move_actor_into_home(actor, home, actor.npc.house if actor.npc != null else null)
	else:
		# Preserve the place in line if the house disappears mid-transfer.
		if _home_valid(home) and not available_homes.has(home):
			available_homes.push_front(home)
		if _actor_valid(actor):
			waiting_npcs.push_front(actor)
			_position_waiting_actor(actor)
	_transfer_in_progress = false
	_try_place_waiting_npcs()


func _has_available_home() -> bool:
	for home in available_homes:
		if _home_valid(home):
			return true
	return false


func _take_available_home() -> Sprite2D:
	while not available_homes.is_empty():
		var home: Sprite2D = available_homes.pop_front()
		if _home_valid(home):
			return home
	return null


# Kept for the F9 dev panel, which supplies npc and an optional house sprite.
func house_recruit(new_house: Texture2D) -> void:
	var actor: NPCInteractable = npc
	if not _actor_valid(actor):
		return
	# Respect NPCs who were already waiting when using debug shortcuts.
	if _transfer_in_progress or not waiting_npcs.is_empty():
		_enqueue_accepted_actor(actor)
		return
	var home: Sprite2D = _take_available_home()
	if home == null:
		_enqueue_accepted_actor(actor)
		return
	_move_actor_into_home(actor, home, new_house)


func _move_actor_into_home(actor: NPCInteractable, home: Sprite2D, new_house: Texture2D) -> void:
	if not _actor_valid(actor) or not _home_valid(home):
		return
	actor.global_position = home.global_position
	if new_house != null:
		home.texture = new_house
	npc_moved_into_home.emit(actor, home)


func _actor_valid(actor: NPCInteractable) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion()


func _home_valid(home: Sprite2D) -> bool:
	return is_instance_valid(home) and not home.is_queued_for_deletion()
