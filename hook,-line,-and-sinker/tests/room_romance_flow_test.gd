extends Node

# Run from the project root:
# godot --headless --path . res://tests/room_romance_flow_test.tscn
# Checks night preludes, both skip/show outcomes and automatic room exit.
# Regular room visits only continue to topics when the player chooses to.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0
var stage: String = "startup"


func _watchdog() -> void:
	await get_tree().create_timer(75.0).timeout
	push_error("room_romance_flow_test timed out at: " + stage)
	get_tree().quit(1)


func _ready() -> void:
	_watchdog()
	await _run_route(SILAS, true)
	await _run_route(KUDA, false)
	await _run_failed_prelude()
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("room_romance_flow_test: PASS" if failures == 0 else
		"room_romance_flow_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _run_route(npc: NPCData, skip_scene: bool) -> void:
	stage = npc.display_name + " setup"
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var view: NPCRoomView = main.get_node("NPCRoomView") as NPCRoomView
	var illustration: IllustrationSceneController = main.get_node("IllustrationScene") as IllustrationSceneController
	var state: Dictionary = NPCManager.get_npc_state(npc.npc_id)
	var flags: Dictionary = state["flags"]
	flags[&"Recruited"] = true

	stage = npc.display_name + " gift"
	player.held_item = npc.desired_gift
	var accepted: bool = NPCManager.accept_gift(npc, player, npc.desired_gift.item_id)
	_check(accepted and player.held_item == null, npc.display_name + " receives the correct gift")
	_check(int(state.get("gift_received_day", -1)) == 1,
		npc.display_name + " remembers the gift's calendar day")
	_check(NPCManager.get_encounter_json_path(npc) != _invitation_path(npc),
		npc.display_name + " cannot invite Penni on the gift day")
	GameManager.rest() # Day 1 afternoon
	GameManager.rest() # Day 1 night
	_check(NPCManager.get_encounter_json_path(npc) != _invitation_path(npc),
		"Gift still does not unlock invitation that evening")
	GameManager.rest() # Day 2 morning
	_check(NPCManager.get_encounter_json_path(npc) == _invitation_path(npc),
		npc.display_name + " can invite Penni the following day")

	stage = npc.display_name + " invitation"
	DialogueManager.start_conversation(npc, _invitation_path(npc))
	for i in range(40):
		if not DialogueManager.is_active:
			break
		if DialogueManager.is_awaiting_choice():
			DialogueManager.select_choice(0)
		else:
			DialogueManager.advance()
	_check(bool(flags.get(npc.invitation_accepted_flag, false)),
		"Accepting an invitation sets the character's existing flag")
	_check(illustration._active_npc == null,
		"Accepting the invitation never starts the adult illustration immediately")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()

	GameManager.rest() # Day 2 afternoon
	GameManager.rest() # Day 2 night
	_check(RecruitmentHandler.assign_home(npc), npc.display_name + " is assigned a room")
	var door: TransferDoor = null
	var homes: Node2D = world.get_node("AvailableHomeList") as Node2D
	for actor in homes.get_children():
		var candidate: TransferDoor = actor as TransferDoor
		if candidate != null and candidate.get_room_id() == RecruitmentHandler.get_room_id(npc.npc_id):
			door = candidate
			break
	_check(door != null, npc.display_name + " has a playable townhouse door")
	if door == null:
		main.queue_free()
		await get_tree().process_frame
		return

	stage = npc.display_name + " night prelude"
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(view.visible and DialogueManager.is_active and bool(view.get("_prelude_active")),
		"Entering the invited room at night begins the emotional prelude, not the illustration")
	_finish_graph_choices([0, 0, 0])
	# Iris plus illustration fade must finish before Show / Skip.
	var ready: bool = false
	for i in range(60):
		if illustration._active_npc == npc and not illustration._transitioning:
			ready = true
			break
		await get_tree().create_timer(0.1).timeout
	_check(ready, "The warning has fully finished fading before user input")
	_check(view.visible and illustration._active_npc == npc,
		"Arriving at night starts the invited character's scene inside the room")
	_check((illustration.get_node("WarningScreen") as ColorRect).visible,
		"Nighttime scene first displays the opt-in warning")

	if skip_scene:
		illustration._on_skip_pressed()
	else:
		illustration._on_show_pressed()
		for i in range(60):
			if DialogueManager.is_active and DialogueManager.current_npc == npc:
				break
			await get_tree().create_timer(0.1).timeout
		_check(DialogueManager.is_active and DialogueManager.current_npc == npc,
			"Choosing Show starts the character's authored illustration dialogue")
		if DialogueManager.is_active:
			DialogueManager.end_conversation()

	stage = npc.display_name + " overnight interlude"
	var interlude: CenterContainer = illustration.get_node("FadeLayer/OvernightInterlude") as CenterContainer
	var interlude_label: Label = interlude.get_node("Content/SleepText") as Label
	var interlude_continue: Button = interlude.get_node("Content/ContinueButton") as Button
	for i in range(60):
		if bool(illustration.get("_interlude_active")):
			break
		await get_tree().create_timer(0.1).timeout
	_check(interlude.visible and bool(illustration.get("_interlude_active")),
		"Show and Skip both lead to the overnight black-screen interlude")
	_check(interlude_label.text == npc.overnight_transition_text,
		"The interlude uses the NPC's editor-configurable overnight text")
	_check(GameManager.get_day() == 2 and GameManager.is_period(GameManager.Times.NIGHT),
		"The clock stays at night until the interlude is continued")
	_check(not DialogueManager.is_active,
		"The morning-after dialogue does not appear underneath the interlude")
	# Press the same Continue button a player sees before proceeding.
	if bool(illustration.get("_interlude_active")):
		interlude_continue.pressed.emit()

	stage = npc.display_name + " morning"
	for i in range(60):
		if GameManager.get_day() == 3 and DialogueManager.is_active:
			break
		await get_tree().create_timer(0.1).timeout
	_check(GameManager.get_day() == 3 and GameManager.is_period(GameManager.Times.MORNING),
		"Watching or skipping advances precisely one night to the next morning")
	_check(view.visible and bool(main.get_node("CanvasLayer/DialogueUI").get("_room_mode")),
		"Morning-after presentation remains in the same room")
	_check(DialogueManager.is_active and DialogueManager.current_npc == npc,
		"Existing morning-after JSON plays with the resident on screen")
	_check(not flags.get(npc.romance_complete_flag, false),
		"Romance reward is not granted before the morning conversation finishes")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	_check(bool(flags.get(npc.romance_complete_flag, false)),
		"Completing the morning dialogue grants the romance completion flag")
	_check(BobberManager.get_unlocked_bobbers().has(BobberManager.get_bobber(npc.romance_reward_id)),
		"Morning dialogue grants the character's existing bobber reward")

	stage = npc.display_name + " automatic room exit"
	for i in range(50):
		if not view.visible and not player.busy and not bool(view.get("_closing")):
			break
		await get_tree().create_timer(0.1).timeout
	_check(not view.visible and not player.busy and not bool(view.get("_closing")),
		"The morning-after conversation automatically returns Penni to the world")
	_check(not DialogueManager.is_active,
		"No repeat greeting begins after receiving the morning-after reward")
	# Reenter normally: post-romance JSON offers Something else..., and leaving
	# doesn't depend on looping another greeting.
	stage = npc.display_name + " repeat room visit"
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(DialogueManager.is_active, "Reentering later starts an ordinary conversation")
	_advance_to_choices()
	var choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
	var ask_more: int = -1
	for i in range(choices.size()):
		if choices[i].text == "Something else...":
			ask_more = i
	_check(ask_more >= 0, "Repeat visits include an explicit Something else... option")
	if ask_more >= 0:
		DialogueManager.select_choice(ask_more)
	_advance_to_choices()
	_check(DialogueManager.is_awaiting_choice(),
		"The extra conversation continues without replaying the greeting")
	# End the conversation, simulating a normal goodbye; no automatic restart.
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(50):
		if not view.visible:
			break
		await get_tree().create_timer(0.1).timeout
	_check(not view.visible and not DialogueManager.is_active,
		"An ordinary room conversation ends and closes without looping")
	main.queue_free()
	await get_tree().process_frame


func _invitation_path(npc: NPCData) -> String:
	return "res://dialogue/silas_invitation.json" if npc == SILAS \
		else "res://dialogue/kuda_invitation.json"


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1


# Select successive prelude choices, advancing each spoken line before the
# next choice. This exercises the authored graph, not a shortcut scene flag.
func _finish_graph_choices(indices: Array[int]) -> void:
	var choice_step: int = 0
	for i in range(120):
		if not DialogueManager.is_active:
			break
		if DialogueManager.is_awaiting_choice():
			if choice_step >= indices.size():
				push_error("Unexpected extra choice while navigating prelude")
				break
			DialogueManager.select_choice(indices[choice_step])
			choice_step += 1
		else:
			DialogueManager.advance()
	_check(choice_step == indices.size(), "Prelude traverses the expected choices")


func _advance_to_choices() -> void:
	for i in range(35):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			return
		DialogueManager.advance()


func _run_failed_prelude() -> void:
	stage = "failed prelude setup"
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var npc: NPCData = SILAS
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var view: NPCRoomView = main.get_node("NPCRoomView") as NPCRoomView
	var illustration: IllustrationSceneController = main.get_node("IllustrationScene") as IllustrationSceneController
	var state: Dictionary = NPCManager.get_npc_state(npc.npc_id)
	state["flags"][&"Recruited"] = true
	state["flags"][npc.invitation_accepted_flag] = true
	GameManager.rest()
	GameManager.rest() # Night, day 1
	_check(RecruitmentHandler.assign_home(npc), "Failure scenario resident assigned")
	var door: TransferDoor
	for node in world.get_node("AvailableHomeList").get_children():
		var candidate: TransferDoor = node as TransferDoor
		if candidate != null and candidate.get_room_id() == RecruitmentHandler.get_room_id(npc.npc_id):
			door = candidate
			break
	if door == null:
		_check(false, "Failure scenario door exists")
		main.queue_free()
		await get_tree().process_frame
		return
	stage = "failed prelude"
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(DialogueManager.is_active and bool(view.get("_prelude_active")),
		"Failure scenario starts the prelude")
	_finish_graph_choices([2]) # Pushy choice: Silas asks to stop.
	for i in range(50):
		if not view.visible and not player.busy:
			break
		await get_tree().create_timer(0.1).timeout
	_check(not view.visible and not player.busy and illustration._active_npc == null,
		"Misreading the mood closes the room without starting the adult scene")
	_check(GameManager.get_day() == 1 and GameManager.is_period(GameManager.Times.NIGHT),
		"An unsuccessful evening does not advance the clock")
	_check(bool(state["flags"].get(npc.invitation_accepted_flag, false)) \
		and not state["flags"].get(npc.romance_complete_flag, false),
		"Invitation remains available, but the romance is not completed")
	# No instant retries at the door on the same night.
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(not bool(view.get("_prelude_active")) and illustration._active_npc == null,
		"Unsuccessful evening cannot be repeated immediately that night")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await get_tree().create_timer(1.2).timeout
	GameManager.rest()
	GameManager.rest()
	GameManager.rest() # Day 2 night
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(bool(view.get("_prelude_active")),
		"Accepting a new day allows another invitation visit at night")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await get_tree().create_timer(1.2).timeout
	main.queue_free()
	await get_tree().process_frame
