extends Node

signal fade_to()

var listening: bool = false
var available_homes: Array[Sprite2D] = []
var npc: NPCInteractable = null
var time_to_transfer: float = 0.8

func _ready() -> void:
	DialogueManager.conversation_finished.connect(check_for_recruitment)

func engage_listen(transfer: NPCInteractable) -> void:
	# Only the initial conversation after catching this NPC may recruit them.
	npc = transfer
	listening = is_instance_valid(transfer)

func check_for_recruitment(finished_npc: NPCData) -> void:
	if not listening:
		return
	# Clear the pending listener even if the player doesn't recruit the NPC.
	listening = false
	if finished_npc == null or not is_instance_valid(npc) or npc.npc != finished_npc:
		return

	var flags: Dictionary = NPCManager.get_npc_state(finished_npc.npc_id).get("flags", {})
	if not flags.get(&"Recruited", false):
		return

	if available_homes.is_empty():
		push_warning("RecruitmentHandler: no available homes for " + finished_npc.display_name)
		return

	fade_to.emit()
	await get_tree().create_timer(time_to_transfer).timeout
	if is_instance_valid(npc):
		house_recruit(finished_npc.house)
	npc = null

func house_recruit(new_house: Texture2D) -> void:
	if available_homes.is_empty() or not is_instance_valid(npc):
		return
	var home: Sprite2D = available_homes.pop_front()
	if not is_instance_valid(home):
		push_warning("RecruitmentHandler: target home is no longer valid.")
		return
	npc.global_position = home.global_position
	if new_house != null:
		home.texture = new_house
