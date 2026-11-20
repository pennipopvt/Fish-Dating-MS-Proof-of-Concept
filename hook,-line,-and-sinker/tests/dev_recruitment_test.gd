extends Node

# Run in Godot project:
# godot --headless --path . res://tests/dev_recruitment_test.tscn
# Tests the F9 shortcut's real recruitment path for Silas and Kuda.

const SILAS_FISH: FishData = preload("res://resources/fish/silas.tres")
const KUDA_FISH: FishData = preload("res://resources/fish/kuda.tres")

var failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var original_pool: Array[FishData] = FishingManager.possible_catches.duplicate()
	var original_states: Dictionary = NPCManager.npc_states.duplicate(true)
	var original_homes: Array[Sprite2D] = RecruitmentHandler.available_homes.duplicate()
	RecruitmentHandler.reset_runtime_state()
	RecruitmentHandler.available_homes.clear()
	NPCManager.npc_states.clear()
	FishingManager.possible_catches = [SILAS_FISH, KUDA_FISH]

	var home := Sprite2D.new()
	home.global_position = Vector2(80, 90)
	add_child(home)
	RecruitmentHandler.register_available_home(home)

	var silas := SILAS_FISH.npc_data.instantiate() as NPCInteractable
	var kuda := KUDA_FISH.npc_data.instantiate() as NPCInteractable
	add_child(silas)
	add_child(kuda)
	_expect(not RecruitmentHandler.recruit_actor_for_debug(silas, KUDA_FISH),
		"Cannot recruit the wrong NPC using another fish resource")
	_expect(RecruitmentHandler.recruit_actor_for_debug(silas, SILAS_FISH),
		"Silas shortcut successfully recruits an NPC")
	_expect(not RecruitmentHandler.recruit_actor_for_debug(silas, SILAS_FISH),
		"Repeated recruitment cannot duplicate Silas or reserve another home")
	_expect(RecruitmentHandler.recruit_actor_for_debug(kuda, KUDA_FISH),
		"Kuda shortcut successfully recruits independently")
	_expect(ShopManager.gifts_unlocked,
		"Recruiting the first NPC permanently reveals gifts for this run")
	_expect(not FishingManager.possible_catches.has(SILAS_FISH)
		and not FishingManager.possible_catches.has(KUDA_FISH),
		"Both recruited fish leave the fishing catch pool")
	_expect(bool(NPCManager.get_npc_state(silas.npc.npc_id)["flags"].get(&"Recruited", false)),
		"Silas's own recruited flag is set")
	_expect(bool(NPCManager.get_npc_state(kuda.npc.npc_id)["flags"].get(&"Recruited", false)),
		"Kuda's own recruited flag is set")
	_expect(NPCManager.get_npc_state(silas.npc.npc_id).has(AffectionManager.RECRUITED_DAY_KEY)
		and NPCManager.get_npc_state(kuda.npc.npc_id).has(AffectionManager.RECRUITED_DAY_KEY),
		"Both fish start their actual recruitment deadline")
	_expect(RecruitmentHandler.waiting_npcs.has(kuda),
		"Kuda waits for an available house while Silas is moving in")
	await get_tree().create_timer(RecruitmentHandler.time_to_transfer + 0.15).timeout
	_expect(silas.global_position.is_equal_approx(home.global_position),
		"Silas moves into the assigned house")

	var second_home := Sprite2D.new()
	second_home.global_position = Vector2(150, 90)
	add_child(second_home)
	RecruitmentHandler.register_available_home(second_home)
	await get_tree().create_timer(RecruitmentHandler.time_to_transfer + 0.15).timeout
	_expect(kuda.global_position.is_equal_approx(second_home.global_position),
		"Kuda moves into the next available house")
	_expect(RecruitmentHandler.waiting_npcs.is_empty(),
		"Both recruits exit the waiting queue after getting homes")

	var tabs := DevPanel.get("_tabs") as TabContainer
	var names: Array[String] = []
	for i in tabs.get_tab_count():
		names.append(str(tabs.get_tab_control(i).name))
	_expect(not names.has("Talk"), "Outdated Story tab is removed")
	_expect(names.has("Flags") and tabs.get_tab_title(names.find("Flags")) == "NPCs",
		"NPC tools are consolidated under the NPCs tab")

	RecruitmentHandler.reset_runtime_state()
	RecruitmentHandler.available_homes = original_homes
	FishingManager.possible_catches = original_pool
	NPCManager.npc_states = original_states
	silas.queue_free()
	kuda.queue_free()
	home.queue_free()
	second_home.queue_free()
	print("dev_recruitment_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _expect(ok: bool, message: String) -> void:
	if ok:
		print("  ok   ", message)
	else:
		failures += 1
		push_error("  FAIL " + message)
