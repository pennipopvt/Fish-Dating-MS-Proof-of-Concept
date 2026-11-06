extends Node

signal fade_to()
#i did this while so sleepy i hope it makes sense

var listening: bool = false
var available_homes: Array[Sprite2D] = []
var npc : Area2D
var time_to_transfer: float = 0.8

func _ready() -> void:
	#listens for when a dialogue is complete taking the npc data for housing
	#and for flag checking
	DialogueManager.conversation_finished.connect(check_for_recruitment)


func engage_listen(transfer: Area2D) -> void:
	#triggered by fishing controller after having caught an npc fish
	listening = true
	npc = transfer

func check_for_recruitment(npc: NPCData) -> void:
	if(!listening): return
	
	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id).get("flags", {})
	
	#leaves room for failed recruitment to not settle a fish
	if flags.get(&"Recruited", true):
		#abuse illustration scenes existing fade to black >:D
		fade_to.emit()
		#uh wait
		await get_tree().create_timer(time_to_transfer).timeout
		house_recruit(npc.house)
		listening = false

func house_recruit(new_house: Texture2D) -> void:
	if(available_homes.is_empty() || npc == null): 
		return
	npc.global_position = available_homes[0].global_position
	available_homes[0].texture = new_house
	available_homes.remove_at(0)
	#places the npc in the first available house
