extends SceneTree

# Run from the Godot project directory:
# godot --headless --path . -s res://tests/recruitment_pool_test.gd
#
# Confirm that the recruitment flag (not the catch itself) removes the
# corresponding NPC fish from all future casts and bait odds.

const SILAS: FishData = preload("res://resources/fish/test_silas.tres")
const NORMAL_FISH: FishData = preload("res://resources/fish/easy_test_fish.tres")
const NPC_SCENE: PackedScene = preload("res://prefabs/test_npc.tscn")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var old_pool: Array[FishData] = FishingManager.possible_catches.duplicate()
	var actor: NPCInteractable = NPC_SCENE.instantiate() as NPCInteractable
	get_root().add_child(actor)

	var same_npc: FishData = FishData.new()
	same_npc.fish_id = &"other_variant_of_silas"
	same_npc.npc_data = SILAS.npc_data
	same_npc.states.append(FishEscapeState.new())
	var test_pool: Array[FishData] = [SILAS, NORMAL_FISH, same_npc, SILAS]
	FishingManager.possible_catches = test_pool

	# Provide a temporary home so successful recruitment runs through the
	# normal transfer path without a missing-home warning.
	var temporary_home: Sprite2D = Sprite2D.new()
	get_root().add_child(temporary_home)
	RecruitmentHandler.available_homes.append(temporary_home)

	var npc_id: StringName = actor.npc.npc_id
	var had_npc_state: bool = NPCManager.npc_states.has(npc_id)
	var original_state: Dictionary = NPCManager.get_npc_state(npc_id).duplicate(true)
	var flags: Dictionary = NPCManager.get_npc_state(npc_id)["flags"]
	flags.erase(&"Recruited")

	# Declining keeps the fish catchable, but despawns the temporary actor.
	RecruitmentHandler.engage_listen(actor, SILAS)
	DialogueManager.conversation_finished.emit(actor.npc)
	_expect(FishingManager.possible_catches.size() == 4, "declining recruitment keeps NPC in catch pool")
	_expect(FishingManager.get_bait_odds(null).has(SILAS), "unrecruited NPC still appears in bait odds")
	_expect(actor.is_queued_for_deletion(), "declined NPC is removed from world to avoid duplicates")
	_expect(not RecruitmentHandler.listening and RecruitmentHandler.pending_fish == null, "declined recruitment clears its listener")

	# A newly caught instance can now be recruited normally.
	var recruited_actor: NPCInteractable = NPC_SCENE.instantiate() as NPCInteractable
	get_root().add_child(recruited_actor)
	flags[&"Recruited"] = true
	RecruitmentHandler.engage_listen(recruited_actor, SILAS)
	DialogueManager.conversation_finished.emit(recruited_actor.npc)
	_expect(FishingManager.possible_catches.size() == 1, "recruitment removes every matching NPC entry")
	_expect(FishingManager.possible_catches[0] == NORMAL_FISH, "normal fish remains catchable")
	_expect(not FishingManager.get_bait_odds(null).has(SILAS), "recruited NPC disappears from bait odds")
	_expect(not FishingManager.get_bait_odds(null).has(same_npc), "all NPC variants disappear from odds")
	_expect(FishingManager.get_random_catch() == NORMAL_FISH, "only remaining normal fish can be hooked")
	await get_tree().create_timer(RecruitmentHandler.time_to_transfer + 0.1).timeout
	_expect(recruited_actor.global_position.is_equal_approx(temporary_home.global_position), "recruited NPC is moved to the reserved home")
	_expect(not RecruitmentHandler.available_homes.has(temporary_home), "occupied home is no longer available")

	# With no house left, an accepted NPC stays in the world instead of
	# being dropped on the floor or left as a stale global pointer.
	var homeless_actor: NPCInteractable = NPC_SCENE.instantiate() as NPCInteractable
	get_root().add_child(homeless_actor)
	RecruitmentHandler.engage_listen(homeless_actor, SILAS)
	DialogueManager.conversation_finished.emit(homeless_actor.npc)
	_expect(not homeless_actor.is_queued_for_deletion(), "accepted NPC remains in world when houses are full")
	_expect(RecruitmentHandler.npc == null and not RecruitmentHandler.listening, "no-home path clears pending listener")

	# An ordinary non-NPC fish must never be deleted by this API.
	FishingManager.remove_recruited_catch(NORMAL_FISH)
	FishingManager.remove_recruited_catch(null)
	_expect(FishingManager.possible_catches.size() == 1, "non-NPC removals are ignored")

	FishingManager.possible_catches = old_pool
	if had_npc_state:
		NPCManager.npc_states[npc_id] = original_state
	else:
		NPCManager.npc_states.erase(npc_id)
	RecruitmentHandler.available_homes.erase(temporary_home)
	temporary_home.queue_free()
	actor.queue_free()
	recruited_actor.queue_free()
	homeless_actor.queue_free()

	print("FAILED: %d" % failures if failures > 0 else "All recruitment pool tests passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
