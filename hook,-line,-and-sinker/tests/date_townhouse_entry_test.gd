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

	var original_player_position: Vector2 = player.global_position
	# The actual door now opens the NPC's room, asks if Penni is ready,
	# and hands over to the EXISTING date transition only after Yes.
	door.interact(player)
	for i in range(30):
		if view.visible and DialogueManager.is_active:
			break
		await get_tree().create_timer(0.1).timeout
	_check(view.visible and DialogueManager.current_npc == npc,
		"%s's door opens the correct resident's room first" % npc.display_name)
	_check(not DateManager.is_active(), "A date never auto-starts without confirmation")
	if DialogueManager.is_active:
		DialogueManager.advance()
	_check(DialogueManager.is_awaiting_choice()
		and DialogueManager.get_choices().size() == 2,
		"Room asks whether to go on the scheduled date, with Yes and Not yet")
	if DialogueManager.is_awaiting_choice():
		DialogueManager.select_choice(0)
		DialogueManager.advance()
		DialogueManager.advance()
	for i in range(40):
		if DateManager.is_active():
			break
		await get_tree().create_timer(0.1).timeout
	_check(DateManager.is_active() and DateManager.get("_active") == date,
		"%s's Yes choice starts the booked date after closing the room" % npc.display_name)
	_check(not view.visible, "Date takes over only once room overlay closes")
	_check(player.busy, "Movement is locked during the date")
	for i in range(40):
		if DialogueManager.is_active and bool(DateManager.get("_in_dialogue")):
			break
		await get_tree().create_timer(0.1).timeout
	_check(DialogueManager.is_active and bool(DateManager.get("_in_dialogue"))
		and DialogueManager.current_npc == npc,
		"%s's real date dialogue begins after the transition" % npc.display_name)
	var guest: Node2D = DateManager.get("_date_actor") as Node2D
	_check(is_instance_valid(guest) and guest.is_visible_in_tree(),
		"%s appears as a visible temporary actor during the date" % npc.display_name)
	if is_instance_valid(guest):
		var sprite: AnimatedSprite2D = guest.get_node_or_null("Sprite") as AnimatedSprite2D
		_check(sprite != null and sprite.visible and sprite.sprite_frames != null,
			"%s uses the real animated human sprite, not a placeholder" % npc.display_name)
		_check(guest is NPCInteractable and (guest as NPCInteractable).npc == npc,
			"Date actor belongs to the correct NPC")
		var venue: Node2D = DateManager.get("_venue") as Node2D
		if venue == null:
			for loc in get_tree().get_nodes_in_group(DateManager.LOCATION_GROUP):
				if loc is DateLocation and (loc as DateLocation).location_id == date.location_id:
					venue = loc as Node2D
					break
		var spot: Marker2D = venue.get_node_or_null("NpcSpot") as Marker2D if venue != null else null
		if date_id == &"kuda_ship":
			var boat_art: IntroBoatSprite = venue.get_node_or_null("Sprite") as IntroBoatSprite
			_check(venue.scene_file_path == "res://prefabs/intro_boat.tscn"
				and boat_art != null and boat_art.is_playing()
				and boat_art.sprite_sheet == load("res://sprites/environment/boat.png"),
				"Kuda date uses the identical animated opening boat, not the placeholder ship")
			_check(venue.global_position == date.venue_position
				and venue.global_position == Vector2(2250, 124),
				"Kuda date returns to the original intro boat location")
			_check(player.z_index > boat_art.z_index and guest.z_index > boat_art.z_index,
				"Penni and Kuda remain visible above the animated boat")
		if sprite != null and sprite.sprite_frames != null and spot != null:
			var frame: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
			var feet_y: float = guest.global_position.y + sprite.position.y + frame.get_height() * sprite.scale.y * 0.5
			_check(absf(feet_y - (spot.global_position.y + date.npc_feet_offset.y)) < 0.1,
				"Date actor's feet align with the scene's NpcSpot")

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
	_check(player.z_index == 0, "Date restores Penni's original draw order")
	_check(DateManager.get("_venue") == null, "Temporary boat is removed when date finishes")
	_check(DateManager.get("_date_actor") == null,
		"Temporary date actor is cleared on completion")
	_check(player.global_position.distance_to(original_player_position) < 0.1,
		"Penni returns to her original world position")
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
