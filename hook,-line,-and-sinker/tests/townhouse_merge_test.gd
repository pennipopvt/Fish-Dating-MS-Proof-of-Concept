extends Node

# First-person townhouse rooms reuse DialogueUI and the real iris.
# The expanded sea remains untouched and NO interior actor lives in World.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const LOCKED_DOOR: Texture2D = preload("res://sprites/rooms/lockeddoor.png")
var failures: int = 0
var _stage: String = "startup"


func _watchdog() -> void:
	await get_tree().create_timer(16.0).timeout
	push_error("Townhouse integration timeout at: " + _stage)
	get_tree().quit(1)


func _ready() -> void:
	_watchdog()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var guide: SeaEditorGuide = sea.get_node("EditorGuide") as SeaEditorGuide
	var homes: Node2D = world.get_node("AvailableHomeList") as Node2D
	var player: Player = world.get_node("Player") as Player
	var view: NPCRoomView = main.get_node("NPCRoomView") as NPCRoomView
	var dialogue: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI
	# Tune the new Inspector controls to verify their runtime geometry.
	# The original outdoor portrait layout must return on room exit.
	var npc_portrait: TextureRect = dialogue.get_node("NPCPortrait") as TextureRect
	var land_rect: Vector4 = Vector4(
		npc_portrait.offset_left, npc_portrait.offset_top,
		npc_portrait.offset_right, npc_portrait.offset_bottom)
	dialogue.room_portrait_position = Vector2(64.0, -510.0)
	dialogue.room_portrait_scale = 1.25
	_check(world.has_node("Townhouse") and homes.get_child_count() == 4
		and not world.has_node("SilasRoom"),
		"Townhouse has four doors, no physical rooms or permanent interior NPCs")
	_check(guide.map_origin.x == -1792.0 and guide.map_size.x == 1984.0,
		"Existing sea level dimensions and spawners remain unchanged")
	var home: TransferDoor = homes.get_node("FreeHouseA") as TransferDoor
	_check(RecruitmentHandler.available_homes.size() == 4,
		"Room registry starts with four unoccupied doors")
	var doors_locked: bool = true
	for node in homes.get_children():
		var door: TransferDoor = node as TransferDoor
		if door == null or not door.locked or door.house.texture != LOCKED_DOOR:
			doors_locked = false
	_check(doors_locked, "All unoccupied doors use the locked-door artwork")
	_check(RecruitmentHandler.assign_home(SILAS) and RecruitmentHandler.is_resident(SILAS.npc_id),
		"Silas receives a room using only his NPCData, without a physical actor")
	_check(RecruitmentHandler.get_room_id(SILAS.npc_id) == home.get_room_id()
		and RecruitmentHandler.get_resident(home.get_room_id()) == SILAS
		and home.resident == SILAS and not home.locked,
		"Room assignment is authoritative in NPCManager and reflected by the door")
	_check(home.house.texture == SILAS.door.door,
		"Occupied door uses Silas's personal artwork")
	_check(not NPCManager.get_npc_state(SILAS.npc_id).has(AffectionManager.RECRUITED_DAY_KEY),
		"Giving Silas a room doesn't start a romance deadline")
	var spot: Vector2 = player.global_position
	_stage = "Opening room"
	home.interact(player)
	await get_tree().create_timer(1.45).timeout
	_check(view.visible and dialogue.visible and player.busy
		and bool(dialogue.get("_room_mode")),
		"The iris opens one first-person room using the existing DialogueUI")
	_check(player.global_position == spot,
		"Entering a room doesn't move or teleport the player")
	var penni_portrait: TextureRect = dialogue.get_node("PlayerPortrait") as TextureRect
	_check(not penni_portrait.visible and npc_portrait.visible
		and absf(npc_portrait.anchor_left - 0.5) < 0.001,
		"Room mode hides Penni's portrait and centers the enlarged NPC portrait")
	_check(is_equal_approx(npc_portrait.offset_left, -586.0)
		and is_equal_approx(npc_portrait.offset_top, -1510.0)
		and is_equal_approx(npc_portrait.offset_right, 714.0)
		and is_equal_approx(npc_portrait.offset_bottom, 490.0)
		and npc_portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"Editor position and uniform scale reframe the NPC without stretching its art")
	_check(DialogueManager.is_active and DialogueManager.current_npc == SILAS,
		"The resident's normal JSON dialogue starts in room mode")
	_stage = "Saying goodbye"
	var loops: int = 0
	while DialogueManager.is_active and not DialogueManager.is_awaiting_choice() and loops < 10:
		DialogueManager.advance()
		loops += 1
	var bye_index: int = -1
	var choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
	for i in range(choices.size()):
		if choices[i].text == "See you later!":
			bye_index = i
	_check(bye_index >= 0, "The existing dialogue offers a goodbye choice")
	if bye_index >= 0:
		DialogueManager.select_choice(bye_index)
		DialogueManager.advance() # Penni says goodbye.
		DialogueManager.advance() # Silas responds and requests the room exit.
	await get_tree().create_timer(1.45).timeout
	_check(not view.visible and not dialogue.visible and not player.busy
		and not bool(dialogue.get("_room_mode")),
		"Goodbye closes the same iris and restores the outdoor UI")
	_check(is_equal_approx(npc_portrait.anchor_left, 1.0)
		and is_equal_approx(npc_portrait.offset_left, land_rect.x)
		and is_equal_approx(npc_portrait.offset_top, land_rect.y)
		and is_equal_approx(npc_portrait.offset_right, land_rect.z)
		and is_equal_approx(npc_portrait.offset_bottom, land_rect.w),
		"Leaving the room restores the outdoor NPC portrait geometry")
	_check(player.global_position == spot,
		"Leaving returns Penni to the same exact outdoor world position")
	_check(RecruitmentHandler.assign_home(KUDA)
		and RecruitmentHandler.get_room_id(KUDA.npc_id) != home.get_room_id(),
		"A second resident takes a different room without an interior scene")
	_check(view.get_node_or_null("Backdrop") is ColorRect
		and (view.get_node("Backdrop") as ColorRect).color.a == 1.0,
		"Unfinished NPC backgrounds use an opaque fallback instead of showing the world")
	RecruitmentHandler.vacate_home(SILAS.npc_id)
	_check(home.locked and home.house.texture == LOCKED_DOOR
		and RecruitmentHandler.available_homes.has(home)
		and not RecruitmentHandler.is_resident(SILAS.npc_id),
		"Vacating a room resets its door and makes it available again")
	main.queue_free()
	print("townhouse_merge_test: PASS" if failures == 0 else
		"townhouse_merge_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
