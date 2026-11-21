extends Node

# Ethan's townhouse integration must never replace Penni's sea geometry.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const LOCKED_DOOR: Texture2D = preload("res://sprites/rooms/lockeddoor.png")
var failures: int = 0
var _stage: String = "startup"


func _watchdog() -> void:
	await get_tree().create_timer(12.0).timeout
	push_error("Townhouse integration timeout at: " + _stage)
	get_tree().quit(1)


func _checkpoint(at: String) -> void:
	_stage = at
	print("[TOWNHOUSE TEST] " + at)



func _ready() -> void:
	_watchdog()
	_checkpoint("Constructing game")
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var water: ColorRect = world.get_node("Water") as ColorRect
	var room: Node2D = world.get_node("SilasRoom") as Node2D
	var guide: SeaEditorGuide = sea.get_node("EditorGuide") as SeaEditorGuide
	var homes: Node2D = world.get_node("AvailableHomeList") as Node2D
	_check(world.has_node("Townhouse") and homes.get_child_count() == 4,
		"Townhouse and four doors were added to the existing world")
	_check(room.global_position.y < guide.map_origin.y
		and room.global_position.y < water.global_position.y - 300.0,
		"Silas room is far above the sea and cannot overlap dive level art")
	_check(guide.map_origin.x == -1792.0 and guide.map_size.x == 1984.0,
		"Expanded sea dimensions and spawn geometry were preserved")
	var home: TransferDoor = homes.get_node("FreeHouseA") as TransferDoor
	_check(home != null and home.locked and RecruitmentHandler.available_homes.size() == 4,
		"Four available townhouse room doors start locked")
	var door_visuals_correct: bool = true
	for node in homes.get_children():
		var door: TransferDoor = node as TransferDoor
		var art: Sprite2D = door.get_node_or_null("Sprite") as Sprite2D if door != null else null
		if art == null or art.texture != LOCKED_DOOR or not door.locked:
			door_visuals_correct = false
	_check(door_visuals_correct,
		"Every exterior slot displays Ethan's locked-door sprite, not a house placeholder")
	_check(SILAS.door != null and SILAS.door.sceneLoc == Vector2(-1233, -520)
		and KUDA.door != null and KUDA.door.sceneLoc == Vector2.ZERO,
		"Silas has an isolated room; unfinished Kuda room stays locked")
	_checkpoint("Recruiting Silas")
	var actor: NPCInteractable = (load("res://prefabs/silas.tscn") as PackedScene).instantiate() as NPCInteractable
	world.add_child(actor)
	actor.npc = SILAS
	RecruitmentHandler.call("_move_actor_into_home", actor, home, SILAS.door)
	_check(not home.locked and home.transfer_loc == SILAS.door.sceneLoc
		and actor.is_queued_for_deletion(),
		"NPC recruitment updates room without leaving a stray world actor")
	_check(home.house.texture == SILAS.door.door,
		"Recruited Silas switches to Ethan's Silas-specific door artwork")
	var player: Player = world.get_node("Player") as Player
	var exit_door: TransferDoor = room.get_node("SilasHouse") as TransferDoor
	_check(not exit_door.locked and exit_door.transfer_loc == Vector2(313, 112),
		"Interior doorway leads back to town")
	_checkpoint("Entering townhouse door")
	home.interact(player)
	await get_tree().create_timer(0.85).timeout
	_check(player.global_position.distance_to(SILAS.door.sceneLoc) < 1.0 and not player.busy,
		"Townhouse door fades directly into Silas room")
	_checkpoint("Leaving townhouse room")
	exit_door.interact(player)
	await get_tree().create_timer(0.85).timeout
	_check(player.global_position == Vector2(313, 112) and not player.busy,
		"Room exit fades back to town")
	_checkpoint("Freeing room")
	AffectionManager.call("_free_home", SILAS.npc_id)
	_check(home.locked and RecruitmentHandler.available_homes.has(home),
		"Vacated room relocks and returns to available rooms")
	_checkpoint("Finished test")
	main.queue_free()
	print("townhouse_merge_test: PASS" if failures == 0 else
		"townhouse_merge_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
