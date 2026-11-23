extends Node

# After the first uncatchable line-break fish, the authored mullet for the
# Silas-assisted catch must spawn only after the Silas rescue conversation.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var encounter: SeaEncounterSequence = sea.get_node("EncounterSequence") as SeaEncounterSequence
	var mullet_marker: DivingFishSpawn = sea.get_node("FishSpawns/MulletAfterSilas") as DivingFishSpawn
	var cast_fish: DivingWildFish = encounter.tutorial_fish
	_check(mullet_marker.spawn_after_silas_rescue and not mullet_marker.is_first_dive_fish,
		"MulletAfterSilas has an editor-visible rescue gate")
	var initial_fish: Array = sea.get("_wild_fish")
	_check(initial_fish.size() == 2 and initial_fish.has(cast_fish)
		and initial_fish.has(encounter.silas_trap),
		"Before Silas, the only fish are the scripted first fish and hidden rescue target")
	_check(sea.get("_pending_silas_rescue_spawns").size() == 1,
		"Exactly one authored follow-up mullet is waiting for rescue")

	# If Penni reaches Silas out of order, the first fish may still be
	# present, but it can never enter normal catch combat.
	story.get("_events")[&"help_called"] = true
	_check(encounter.handle_fish_hit(cast_fish)
		and not (sea.get_node("Combat") as DivingCombat).is_active(),
		"Opening fish cannot be caught through regular combat before Silas")

	var flags: Dictionary = NPCManager.get_npc_state(story.silas_data.npc_id)["flags"]
	flags[&"silas_freed"] = true
	sea.call("_on_silas_following_started")
	var spawned_fish: Array = sea.get("_wild_fish")
	var follow_up: DivingWildFish = null
	for fish in spawned_fish:
		if fish != cast_fish and fish != encounter.silas_trap:
			follow_up = fish
	_check(spawned_fish.size() == 3 and follow_up != null
		and follow_up.fish_name == mullet_marker.species.fish_id
		and follow_up.position.distance_to(mullet_marker.position) < 0.1,
		"Rescuing Silas creates exactly the editor-positioned follow-up mullet")
	sea.call("_on_silas_following_started")
	_check(sea.get("_wild_fish").size() == 3,
		"Re-entering the rescue callback never duplicates the mullet")
	main.queue_free()
	await get_tree().process_frame
	print("sea_silas_spawn_gate_test: PASS" if failures == 0 else
		"sea_silas_spawn_gate_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, explanation: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + explanation)
	if not condition:
		failures += 1
