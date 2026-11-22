extends Node

# Shared world dialogue, conditional cast, UI identity, no interruption while
# anybody is fighting, priority and event de-duplication.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const MULLET: FishData = preload("res://resources/fish/mullet.tres")
const JSON_PATH := "res://tests/fixtures/group_world_dialogue.json"
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var player: Player = world.get_node("Player") as Player
	var ui: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI
	var queue: SeaWorldDialogueQueue = sea.get_node("WorldDialogueQueue") as SeaWorldDialogueQueue
	_check(queue != null, "Sea owns one reusable dialogue-event queue")
	if queue == null:
		get_tree().quit(1)
		return
	var group: Array[NPCData] = [SILAS, KUDA]
	var silas_only: Array[NPCData] = [SILAS]
	# Group authored dialogue without Kuda omits his lines, not the graph.
	DialogueManager.request_conversation(SILAS, JSON_PATH, null, silas_only)
	_check(DialogueManager.is_active and ui.visible, "Existing dialogue UI opens")
	_check(ui.get_node("%NameLabel").text == "Silas", "Silas speaks using his own name")
	_check((ui.get_node("%NPCPortrait") as TextureRect).texture == SILAS.portrait,
		"Silas portrait uses his original art")
	DialogueManager.advance()
	ui.call("_refresh")
	_check(DialogueManager.get_current_line() != null and
		DialogueManager.get_current_line().speaker == DialogueLineData.Speaker.PLAYER,
		"Absent Kuda line is omitted when he is not in the cast")
	DialogueManager.end_conversation()
	DialogueManager.request_conversation(SILAS, JSON_PATH, null, group)
	_check(DialogueManager.get_current_line().speaker_id == SILAS.npc_id,
		"Silas is explicitly selected without changing relationship ownership")
	DialogueManager.advance()
	ui.call("_refresh")
	_check(DialogueManager.current_npc == SILAS and
		DialogueManager.get_current_line().speaker_id == KUDA.npc_id,
		"Kuda speaks but Silas remains the conversation's relationship context")
	_check(ui.get_node("%NameLabel").text == "Kuda" and
		(ui.get_node("%NPCPortrait") as TextureRect).texture == KUDA.portrait,
		"Portrait and name switch to Kuda in the existing UI")
	DialogueManager.advance()
	ui.call("_refresh")
	_check(ui.get_node("%NameLabel").text == "Penni", "Penni speaks in the same group")
	DialogueManager.end_conversation()

	# Party combat prevents the queued conversation from interrupting.
	player.set_swimming(true, sea._sea_bounds())
	sea.activate_diving_party(group)
	var battle: DivingCompanionBattle = sea.get_node("PartyCommands").battle_for(SILAS.npc_id)
	var fish: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(30.0, 12.0), 531, 0.0, 0.0, 0.0) as DivingWildFish
	_check(battle != null and battle.start(fish, MULLET), "Companion combat begins")
	_check(queue.enqueue(&"low_priority", SILAS, JSON_PATH, group, 1) and
		queue.enqueue(&"high_priority", SILAS, JSON_PATH, group, 20),
		"Distinct world conversations can be queued with priorities")
	_check(not queue.enqueue(&"high_priority", SILAS, JSON_PATH, group, 20),
		"Duplicate world event is rejected")
	queue._process(0.0)
	_check(queue.pending_count() == 2 and not DialogueManager.is_active,
		"No conversation can start while a party member is fighting")
	battle.stop()
	queue._process(0.0)
	_check(DialogueManager.is_active and queue.get("_active_id") == &"high_priority",
		"Highest priority world event begins when combat finishes")
	DialogueManager.end_conversation()
	queue._process(0.0)
	_check(DialogueManager.is_active and queue.get("_active_id") == &"low_priority",
		"Next queued conversation begins after the previous one ends")
	DialogueManager.end_conversation()
	_check(not queue.enqueue(&"high_priority", SILAS, JSON_PATH, group, 20),
		"Completed world event does not replay in the same dive")
	queue.begin_new_dive()
	_check(queue.enqueue(&"high_priority", SILAS, JSON_PATH, group, 20),
		"New dive can schedule new events without stale queue state")
	queue.clear_pending()
	sea.end_diving_party()
	player.set_swimming(false)
	main.queue_free()
	await get_tree().process_frame
	print("group_world_dialogue_test: PASS" if failures == 0 else
		"group_world_dialogue_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
