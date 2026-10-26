
extends Node

func _ready() -> void:
	test_dialogue()

func test_shop() -> void:
	var trade: TradeData = ShopManager.trades[0]

	print("--- SHOP TEST ---")

	print("Starting casts: ", FishingManager.max_casts_per_session)
	print("Starting fish: ", FishingManager.current_storage.size())

	print("Can trade: ", ShopManager.can_trade(trade))
	print("Trade succeeded: ", ShopManager.make_trade(trade))

	print("New casts: ", FishingManager.max_casts_per_session)
	print("Remaining fish: ", FishingManager.current_storage.size())

	print("Can trade again: ", ShopManager.can_trade(trade))

func test_dialogue() -> void:
	var npc: NPCData = preload("res://resources/test_npc.tres")

	print("--- DIALOGUE TEST ---")

	# First conversation: choose "No!"
	print("\nFIRST CONVERSATION")
	test_conversation(npc, 1)

	# Second conversation: choose "Yes!"
	print("\nSECOND CONVERSATION")
	test_conversation(npc, 0)

	# The intro should no longer be available.
	print("\nTHIRD CONVERSATION")
	DialogueManager.start_conversation(npc)
	test_conversation(npc, 0)
	print("Conversation blocked: ", not DialogueManager.is_active)


func test_conversation(npc: NPCData, choice_index: int) -> void:
	DialogueManager.start_conversation(npc)

	if not DialogueManager.is_active:
		print("No dialogue available!")
		return

	# Display the opening line.
	var line : DialogueLineData = DialogueManager.get_current_line()
	print("NPC: ", line.text)

	# Advance to the choices.
	DialogueManager.advance()

	if DialogueManager.is_awaiting_choice():
		var choices : Array[DialogueChoiceData] = DialogueManager.get_choices()

		print("Player chooses: ", choices[choice_index].text)
		DialogueManager.select_choice(choice_index)

	# Display the resulting dialogue.
	line = DialogueManager.get_current_line()

	if line != null:
		print("NPC: ", line.text)
		DialogueManager.advance()

	print("Conversation ended: ", not DialogueManager.is_active)

	# Check the NPC's flags.
	var state : Dictionary = NPCManager.get_npc_state(npc.npc_id)
	print("Attraction: ", state["attraction"])
	print("MetPlayer: ", state["flags"].get(&"MetPlayer", false))
