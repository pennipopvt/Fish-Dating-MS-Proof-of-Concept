extends Node

signal fade_to()

var listening: bool = false
var available_homes: Array[Sprite2D] = []
var npc: NPCInteractable = null
# Keep the exact caught fish through the dialogue, even after the fishing
# controller clears its own state.
var pending_fish: FishData = null
var time_to_transfer: float = 0.8


func _ready() -> void:
	DialogueManager.conversation_finished.connect(check_for_recruitment)


func engage_listen(transfer: NPCInteractable, caught_fish: FishData = null) -> void:
	# Only the initial conversation after catching this NPC may recruit it.
	npc = transfer
	pending_fish = caught_fish
	listening = is_instance_valid(transfer)


func check_for_recruitment(finished_npc: NPCData) -> void:
	if not listening:
		return
	listening = false
	var caught_fish: FishData = pending_fish
	pending_fish = null
	var caught_actor: NPCInteractable = npc
	npc = null

	if finished_npc == null or not is_instance_valid(caught_actor) or caught_actor.npc != finished_npc:
		return

	var flags: Dictionary = NPCManager.get_npc_state(finished_npc.npc_id).get("flags", {})
	if not flags.get(&"Recruited", false):
		# A declined NPC returns to the fishing pool. Remove the temporary
		# world actor so repeated catches cannot spawn duplicate characters.
		caught_actor.queue_free()
		return

	# Only accepted NPCs leave the catch pool.
	FishingManager.remove_recruited_catch(caught_fish)

	if not _has_available_home():
		# Preserve the accepted NPC in the world instead of losing it.
		# Housing for a full village is a separate design decision.
		push_warning("RecruitmentHandler: no available home for " + finished_npc.display_name)
		return

	fade_to.emit()
	await get_tree().create_timer(time_to_transfer).timeout
	# Use the actor captured before the await. Other NPC conversations must
	# never redirect this recruitment to another character.
	if is_instance_valid(caught_actor):
		_place_actor_in_home(caught_actor, finished_npc.house)


func _has_available_home() -> bool:
	for home in available_homes:
		if is_instance_valid(home):
			return true
	return false


# Kept for the F9 dev panel, which directly assigns its selected NPC.
func house_recruit(new_house: Texture2D) -> void:
	_place_actor_in_home(npc, new_house)


func _place_actor_in_home(actor: NPCInteractable, new_house: Texture2D) -> void:
	if not is_instance_valid(actor):
		return
	# Skip homes removed by scene reloads rather than losing the NPC.
	while not available_homes.is_empty():
		var home: Sprite2D = available_homes.pop_front()
		if not is_instance_valid(home):
			continue
		actor.global_position = home.global_position
		if new_house != null:
			home.texture = new_house
		return
	push_warning("RecruitmentHandler: no valid home remains for " + actor.npc.display_name)
