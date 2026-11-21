extends Node

# Ethan's townhouse integration must never replace Penni's sea geometry.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
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
	_check(SILAS.door != null and SILAS.door.sceneLoc == Vector2(-1233, -520)
		and KUDA.door != null and KUDA.door.sceneLoc == Vector2.ZERO,
		"Silas has an isolated room; unfinished Kuda room stays locked")
	var actor: NPCInteractable = (load("res://prefabs/silas.tscn") as PackedScene).instantiate() as NPCInteractable
	world.add_child(actor)
	actor.npc = SILAS
	RecruitmentHandler.call("_move_actor_into_home", actor, home, SILAS.door)
	_check(not home.locked and home.transfer_loc == SILAS.door.sceneLoc
		and actor.is_queued_for_deletion(),
		"NPC recruitment updates room without leaving a stray world actor")
	var player: Player = world.get_node("Player") as Player
	var exit_door: TransferDoor = room.get_node("SilasHouse") as TransferDoor
	_check(not exit_door.locked and exit_door.transfer_loc == Vector2(313, 112),
		"Interior doorway leads back to town")
	home.interact(player)
	await get_tree().create_timer(0.85).timeout
	_check(player.global_position.distance_to(SILAS.door.sceneLoc) < 1.0 and not player.busy,
		"Townhouse door fades directly into Silas room")
	exit_door.interact(player)
	await get_tree().create_timer(0.85).timeout
	_check(player.global_position == Vector2(313, 112) and not player.busy,
		"Room exit fades back to town")
	AffectionManager.call("_free_home", SILAS.npc_id)
	_check(home.locked and RecruitmentHandler.available_homes.has(home),
		"Vacated room relocks and returns to available rooms")
	main.queue_free()
	print("townhouse_merge_test: PASS" if failures == 0 else
		"townhouse_merge_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
