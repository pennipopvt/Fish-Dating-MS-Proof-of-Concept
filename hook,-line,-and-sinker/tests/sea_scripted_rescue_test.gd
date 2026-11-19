extends SceneTree

# Checks the one-off trapped-Silas rescue, independently of normal fish combat.
# Run from the project root with: godot --headless --path . -s res://tests/sea_scripted_rescue_test.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = MAIN.instantiate()
	get_root().add_child(main)
	await process_frame
	var sea: DivingWorld = main.get_node("SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var player: Player = main.get_node("SubViewportContainer/SubViewport/World/Player") as Player
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var encounter: SeaEncounterSequence = sea.get_node("EncounterSequence") as SeaEncounterSequence
	var silas: SeaNPC = sea.get_node("NPCs/Silas") as SeaNPC
	var net: DivingNetProjectile = sea.get_node("NetProjectile") as DivingNetProjectile
	var combat: DivingCombat = sea.get_node("Combat") as DivingCombat
	var target: DivingWildFish = encounter.silas_trap
	_check(is_instance_valid(target), "An invisible rescue target exists at Silas")
	if target == null:
		main.queue_free()
		quit(1)
		return

	# A separate scene/story system authorizes the rescue after talking.
	var flags: Dictionary = NPCManager.get_npc_state(story.silas_data.npc_id)["flags"]
	flags[&"silas_met"] = true
	_check(story.can_net_silas(), "Story flags permit the rescue net")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	player.set_swimming(true, sea.call("_sea_bounds"))
	player.position = silas.position + Vector2(62.0, 0.0)
	var previous_distance: float = player.position.distance_to(target.position)
	encounter.call("_start_silas_rescue")
	_check(player.busy and encounter.reel_mode == &"silas_rescue",
		"Rescue starts a dedicated noncombat reel")
	_check(not combat.is_active(), "Normal fish combat never starts for trapped Silas")

	for i in range(16):
		if encounter.reel_mode != &"silas_rescue":
			break
		encounter.call("_reel_scripted_target")
		_check(is_zero_approx(net.line_tension),
			"Rescue reel generates no fish tension")
		if encounter.reel_mode == &"silas_rescue":
			var distance: float = player.position.distance_to(silas.position)
			_check(distance < previous_distance, "Silas moves only toward Penni")
			previous_distance = distance

	_check(story.has_silas_flag(&"silas_freed"), "Rescue completes through the original story manager")
	_check(not player.busy and encounter.reel_mode == &"",
		"Rescue finishes without leaving movement locked")
	_check(not combat.is_active() and not net.is_busy(),
		"Net resets and normal combat remains untouched")
	_check(encounter.silas_trap == null,
		"Temporary invisible rescue hit target is removed")
	_check(DialogueManager.is_active and DialogueManager.current_npc == story.silas_data,
		"Rescue opens Silas's existing dialogue UI")
	var first_line: DialogueLineData = DialogueManager.get_current_line()
	_check(first_line != null and first_line.text == "Ah—I'm free!",
		"Rescue introduction begins with the new dialogue")
	_check(not story.has_silas_flag(&"silas_following") and not silas.following,
		"Silas waits for the introduction before becoming a companion")
	var dialogue_steps: int = 0
	while DialogueManager.is_active and not DialogueManager.is_awaiting_choice() and dialogue_steps < 24:
		DialogueManager.advance()
		dialogue_steps += 1
	_check(DialogueManager.is_awaiting_choice() and DialogueManager.get_choices().size() == 2,
		"Introduction offers two Penni responses")
	if DialogueManager.is_awaiting_choice():
		DialogueManager.select_choice(0)
		dialogue_steps = 0
		while DialogueManager.is_active and dialogue_steps < 24:
			DialogueManager.advance()
			dialogue_steps += 1
	_check(not DialogueManager.is_active,
		"Introduction can complete through the normal dialogue system")
	_check(story.has_silas_flag(&"silas_following") and silas.following,
		"Silas follows only after the introduction finishes")

	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	main.queue_free()
	await process_frame
	print("FAILED: %d" % failures if failures > 0 else "Scripted rescue tests passed")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	print(("  PASS  " if condition else "  FAIL  ") + description)
	if not condition:
		failures += 1
