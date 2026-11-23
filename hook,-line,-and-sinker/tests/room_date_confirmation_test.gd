extends Node

# Real Main/World/Dialogue/DateManager flow: overlapping dates can be booked,
# each resident offers their own Yes/Not yet prompt inside the same room view,
# and NPC spot placement remains editor-tunable.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var opening: FishCoOpeningSequence = main.get_node("IntroLayer") as FishCoOpeningSequence
	_check(opening.debug_skip_to_dive(), "Intro skip enables the ordinary room interactions")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	GameManager.reset_clock()
	var silas_date: DateData = DateManager.get_date(&"silas_beach")
	var kuda_date: DateData = DateManager.get_date(&"kuda_ship")
	var room: NPCRoomView = main.get_node("NPCRoomView") as NPCRoomView
	var silas: NPCData = silas_date.npc
	var kuda: NPCData = kuda_date.npc
	var silas_flags: Dictionary = NPCManager.get_npc_state(silas.npc_id)["flags"]
	var kuda_flags: Dictionary = NPCManager.get_npc_state(kuda.npc_id)["flags"]
	silas_flags[&"Recruited"] = true
	silas_flags[&"silas_route_complete"] = true
	kuda_flags[&"Recruited"] = true
	kuda_flags[&"barracuda_route_complete"] = true
	_check(DateManager.book_next_period(silas_date, GameManager.Times.AFTERNOON, 1,
		GameManager.Times.MORNING), "Silas's afternoon date is booked")
	_check(DateManager.book_next_period(kuda_date, GameManager.Times.AFTERNOON, 1,
		GameManager.Times.MORNING), "Kuda's date can use the same afternoon")
	GameManager.rest()
	_check(DateManager.is_booking_ready(silas_date) and DateManager.is_booking_ready(kuda_date),
		"Both resident-specific bookings are ready at once")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()

	# No means Penni can still choose the other appointment, without
	# consuming any actions or losing the first booking.
	room.open_room(silas)
	await get_tree().create_timer(1.2).timeout
	_check(DialogueManager.current_npc == silas and DialogueManager.is_active,
		"Visiting Silas's room asks whether to leave for HIS date")
	DialogueManager.advance()
	_check(DialogueManager.is_awaiting_choice() and DialogueManager.get_choices().size() == 2,
		"Room dialogue uses standard Yes/Not yet choice UI")
	DialogueManager.select_choice(1)
	DialogueManager.advance()
	DialogueManager.advance()
	await get_tree().create_timer(1.25).timeout
	_check(not DateManager.is_active() and DateManager.is_booked(silas_date)
		and DateManager.is_booked(kuda_date),
		"Not yet closes the room without cancelling either booking or starting a date")

	var custom_offset := Vector2(0.0, 9.0)
	kuda_date.npc_feet_offset = custom_offset
	room.open_room(kuda)
	await get_tree().create_timer(1.2).timeout
	_check(DialogueManager.current_npc == kuda and DialogueManager.is_active,
		"Visiting Kuda's room asks about KUDA's own date, not Silas's")
	DialogueManager.advance()
	_check(DialogueManager.is_awaiting_choice(), "Kuda has the same confirmation choices")
	DialogueManager.select_choice(0)
	DialogueManager.advance()
	DialogueManager.advance()
	await get_tree().create_timer(2.25).timeout
	_check(DateManager.is_active() and DateManager.get("_active") == kuda_date,
		"Yes closes the room and starts Kuda's existing venue and date dialogue")
	var venue: Node2D = DateManager.get("_venue") as Node2D
	var actor: Node2D = DateManager.get("_date_actor") as Node2D
	_check(venue != null and actor != null, "Original venue and temporary date NPC are present")
	if venue != null and actor != null:
		_check(venue.scene_file_path == "res://prefabs/intro_boat.tscn"
			and venue.get_node("Sprite") is IntroBoatSprite,
			"Kuda's scheduled date instantiates the original animated boat")
		var penni: Player = main.get_node("SubViewportContainer/SubViewport/World/Player") as Player
		var date_cast_layer: Marker2D = venue.get_node_or_null("DateCastLayer") as Marker2D
		var boat_sprite: IntroBoatSprite = venue.get_node("Sprite") as IntroBoatSprite
		_check(penni.z_index > boat_sprite.z_index
			and actor.z_index > boat_sprite.z_index
			and (date_cast_layer == null or penni.z_index == date_cast_layer.z_index),
			"Both date characters appear above the boat art")
		var expected_feet: Vector2 = (venue.get_node("NpcSpot") as Marker2D).global_position + custom_offset
		var art: AnimatedSprite2D = actor.get_node_or_null("Sprite") as AnimatedSprite2D
		var actor_feet: Vector2 = actor.global_position
		if art != null and art.sprite_frames != null:
			var frame: Texture2D = art.sprite_frames.get_frame_texture(art.animation, art.frame)
			if frame != null and art.centered:
				actor_feet.y += art.position.y + frame.get_height() * 0.5 * art.scale.y
		_check(actor_feet.distance_to(expected_feet) < 1.0,
			"NPC stands at the date venue's editable feet marker plus its resource offset")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await get_tree().create_timer(1.25).timeout
	_check(not DateManager.is_booked(silas_date),
		"Completing one overlapping date advances the period and expires the other")
	kuda_date.npc_feet_offset = Vector2.ZERO

	main.queue_free()
	await get_tree().process_frame
	print("room_date_confirmation_test: PASS" if failures == 0 else
		"room_date_confirmation_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, explanation: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + explanation)
	if not ok:
		failures += 1
