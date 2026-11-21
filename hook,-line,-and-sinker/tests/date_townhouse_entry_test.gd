extends Node

# Real entrance test: booked dates must start by using the resident's door,
# because recruited NPCs do not keep outdoor NPCInteractable actors.
# godot --headless --path . res://tests/date_townhouse_entry_test.tscn

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")

var failures: int = 0
var stage: String = ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_date(SILAS, &"silas_beach")
	await _check_date(KUDA, &"kuda_ship")
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("date_townhouse_entry_test: PASS" if failures == 0 else
		"date_townhouse_entry_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check_date(npc: NPCData, date_id: StringName) -> void:
	stage = npc.display_name
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var view: NPCRoomView = main.get_node("NPCRoomView") as NPCRoomView
	var date: DateData = DateManager.get_date(date_id)
	_check(date != null, "%s date resource is registered" % npc.display_name)
	if date == null:
		main.queue_free()
		await get_tree().process_frame
		return

	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
	flags[npc.romance_complete_flag] = true
	_check(RecruitmentHandler.assign_home(npc), "%s has a townhouse room" % npc.display_name)
	var door: TransferDoor = null
	for child in world.get_node("AvailableHomeList").get_children():
		var candidate := child as TransferDoor
		if candidate != null and candidate.get_room_id() == RecruitmentHandler.get_room_id(npc.npc_id):
			door = candidate
			break
	_check(door != null and not door.locked, "%s has an unlocked resident door" % npc.display_name)
	if door == null:
		main.queue_free()
		await get_tree().process_frame
		return

	_check(DateManager.book_at(date, GameManager.get_day(), GameManager.Times.AFTERNOON),
		"%s can book an afternoon date" % npc.display_name)
	_check(not DateManager.is_booking_ready(date), "Date is not ready in the morning")
	GameManager.rest()
	_check(DateManager.get_ready_booking_for_npc(npc.npc_id) == date,
		"Date becomes ready at its first afternoon action")

	# This is the player's real interaction path. It must start the booked date,
	# not open another ordinary room conversation.
	door.interact(player)
	_check(DateManager.is_active() and DateManager.get("_active") == date,
		"%s's door starts the booked date" % npc.display_name)
	_check(not view.visible, "The room overlay does not replace the date")
	_check(player.busy, "Movement is locked during the date")
	for i in range(40):
		if DialogueManager.is_active and bool(DateManager.get("_in_dialogue")):
			break
		await get_tree().create_timer(0.1).timeout
	_check(DialogueManager.is_active and bool(DateManager.get("_in_dialogue"))
		and DialogueManager.current_npc == npc,
		"%s's real date dialogue begins after the transition" % npc.display_name)

	# Complete the authored four-choice date and verify its results.
	for i in range(200):
		if not DialogueManager.is_active:
			break
		if DialogueManager.is_awaiting_choice():
			DialogueManager.select_choice(0)
		else:
			DialogueManager.advance()
	_check(not DialogueManager.is_active, "%s date dialogue reaches its ending" % npc.display_name)
	for i in range(40):
		if not DateManager.is_active():
			break
		await get_tree().create_timer(0.1).timeout
	_check(not DateManager.is_active(), "The date finishes and releases its slot")
	_check(bool(flags.get(date.get_completed_flag(), false)), "Completed date flag is set")
	_check(not DateManager.is_booked(date), "Booking is cleared on completion")
	_check(GameManager.is_period(GameManager.Times.NIGHT),
		"Completed afternoon date advances to night")
	_check(AffectionManager.get_affection(npc.npc_id) > NPCManager.START_AFFECTION,
		"Date outcome rewards the shared affection score")
	_check(not player.busy, "Player regains movement after the date")
	main.queue_free()
	await get_tree().process_frame
	if DateManager.is_booked(date):
		DateManager.cancel_booking(date)
	if DialogueManager.is_active:
		DialogueManager.end_conversation()


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
