extends Node

# Kuda remembers a rude reply at his night invitation, gives Penni a chance
# to apologize, and does not restart intimacy until a later night.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const HURT_FLAG: StringName = &"barracuda_prelude_hurt"
var failures: int = 0
var stage: String = "startup"


func _ready() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await get_tree().create_timer(40.0).timeout
	push_error("Kuda prelude follow-up timed out at: " + stage)
	get_tree().quit(1)


func _run() -> void:
	_watchdog()
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var view: NPCRoomView = main.get_node("NPCRoomView") as NPCRoomView
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var state: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)
	var flags: Dictionary = state["flags"]
	flags[&"Recruited"] = true
	flags[KUDA.invitation_accepted_flag] = true
	_check(RecruitmentHandler.assign_home(KUDA), "Kuda is housed with a valid invitation")
	var door: TransferDoor = null
	for child in world.get_node("AvailableHomeList").get_children():
		var candidate := child as TransferDoor
		if candidate != null and candidate.get_room_id() == RecruitmentHandler.get_room_id(KUDA.npc_id):
			door = candidate
			break
	_check(door != null, "Kuda's room door is available")
	if door == null:
		_finish(main)
		return

	GameManager.rest()
	GameManager.rest()
	stage = "nighttime rejection"
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(view.visible and bool(view.get("_prelude_active")) and DialogueManager.is_active,
		"First nighttime visit starts the existing romance prelude")
	_advance_to_choices()
	var rude: int = _choice_index("This better be worth the trouble.")
	_check(rude >= 0, "Rude prelude choice is available")
	if rude >= 0:
		DialogueManager.select_choice(rude)
	for i in range(30):
		if not DialogueManager.is_active:
			break
		DialogueManager.advance()
	_check(bool(flags.get(HURT_FLAG, false)),
		"The hurt state is set after Kuda tells Penni to leave")
	_check(not bool(flags.get(KUDA.romance_complete_flag, false)),
		"Rejecting a pushy answer never completes romance")
	await _wait_for_room_exit(view)
	_check(not view.visible and not player.busy, "Kuda closes the room as before")

	stage = "acknowledgment"
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(not bool(view.get("_prelude_active")) and DialogueManager.is_active,
		"Returning the same night opens conversation, not an immediate romance retry")
	var line: DialogueLineData = DialogueManager.get_current_line()
	_check(line != null and line.text == "…Oh. You're back.",
		"Kuda acknowledges being hurt instead of resetting to his standard greeting")
	_advance_to_choices()
	_check(_choice_index("Can we talk about what happened?") >= 0,
		"The remembered argument is the highest-priority conversation topic")
	_select_choice("Can we talk about what happened?")
	_advance_to_choices()
	_select_choice("I didn't think you'd take it so seriously.")
	_advance_to_choices()
	_check(bool(flags.get(HURT_FLAG, false)),
		"Dismissing his feelings doesn't clear the unresolved argument")
	DialogueManager.end_conversation()
	await _wait_for_room_exit(view)

	stage = "apology"
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_advance_to_choices()
	_select_choice("Can we talk about what happened?")
	_advance_to_choices()
	_select_choice("I was being a jerk. I'm sorry.")
	_advance_to_choices()
	_check(not bool(flags.get(HURT_FLAG, false)),
		"Finishing the apology clears the story flag via authored JSON effects")
	_check(DialogueManager.is_awaiting_choice(),
		"After apologizing, Penni can keep chatting instead of being ejected")
	DialogueManager.end_conversation()
	await _wait_for_room_exit(view)
	_check(int(state.get("romance_prelude_attempt_day", -1)) == GameManager.get_day(),
		"Reconciliation does not permit intimacy again immediately that same night")

	stage = "same-night follow-up"
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(not bool(view.get("_prelude_active")) and DialogueManager.is_active
		and DialogueManager.get_current_line().text == "Hey.",
		"After reconciliation, the normal greeting returns without an instant retry")
	DialogueManager.end_conversation()
	await _wait_for_room_exit(view)

	stage = "next night"
	GameManager.rest()
	GameManager.rest()
	GameManager.rest()
	door.interact(player)
	await get_tree().create_timer(1.25).timeout
	_check(bool(view.get("_prelude_active")) and DialogueManager.is_active,
		"A future night can start the existing romance buildup again")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await _wait_for_room_exit(view)
	_finish(main)


func _choice_index(title: String) -> int:
	var choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
	for i in range(choices.size()):
		if choices[i].text == title:
			return i
	return -1


func _select_choice(title: String) -> void:
	var index: int = _choice_index(title)
	_check(index >= 0, "Conversation choice available: " + title)
	if index >= 0:
		DialogueManager.select_choice(index)


func _advance_to_choices() -> void:
	for i in range(55):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			return
		DialogueManager.advance()


func _wait_for_room_exit(view: NPCRoomView) -> void:
	for i in range(45):
		if not view.visible and not bool(view.get("_closing")):
			return
		await get_tree().create_timer(0.1).timeout


func _finish(main: Control) -> void:
	main.queue_free()
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("kuda_prelude_followup_test: PASS" if failures == 0 else
		"kuda_prelude_followup_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
