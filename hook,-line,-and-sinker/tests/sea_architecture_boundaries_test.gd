extends SceneTree

# Verify scene boundaries following the Main refactor.
# godot --headless --path . -s res://tests/sea_architecture_boundaries_test.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	get_root().add_child(main)
	await process_frame

	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var opening: FishCoOpeningSequence = main.get_node("IntroLayer") as FishCoOpeningSequence
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var host: SeaSpeechBubbleHost = main.get_node("SeaSpeechBubbleHost") as SeaSpeechBubbleHost
	var debug: SeaDebugPanel = main.get_node("SeaDebugLayer") as SeaDebugPanel
	var bubble: SeaSpeechBubble = main.get_node("SeaSpeechBubble") as SeaSpeechBubble
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var encounter: SeaEncounterSequence = sea.get_node("EncounterSequence") as SeaEncounterSequence

	_check(main.has_method("request_dive") and not main.has_method("_begin_dive")
		and not main.has_method("_start_contract_call")
		and not main.has_method("_update_sea_debug"),
		"Main exposes only the dock entry point and delegates major workflows")
	_check(opening != null and opening.get_parent() == main
		and opening.get_node("FishCoIntro") is FishCoIntro,
		"Fish Co dialogue and IntroLayer presentation share one component")
	_check(transition != null and transition.get_node("Iris") is ColorRect
		and transition.get("_world_player") == player
		and transition.get("_sea") == sea,
		"TransitionLayer owns the one camera's dive and surfacing flow")
	_check(opening.dive_confirmed.is_connected(
		Callable(transition, "start_confirmed_dive")),
		"Confirmed dock choice reaches the physical transition by signal")
	_check(sea.surface_requested.is_connected(
		Callable(transition, "_on_surface_requested")),
		"Surface request reaches the transition component only")
	_check(host != null and host.get_parent() == main and bubble != null
		and host.source != "uninitialized" and story.get("_speech_bubble") == bubble,
		"Main's editable speech bubble remains bound via one UI host")
	_check(debug != null and not debug.visible
		and debug.get_node("Panel/SkipDialogue") is Button,
		"F7 developer controls are authored and initially hidden")
	_check((debug.get_node("Panel/SkipDialogue") as Button).pressed.is_connected(
		Callable(debug, "skip_dialogue")),
		"Skip Dialogue belongs to the debug component, not Main")
	_check(main.get("_intro_layer") == opening
		and main.get("_intro") == opening.get_node("FishCoIntro"),
		"Existing playtests can inspect the composed opening")
	_check(not bool(main.get("_underwater"))
		and not bool(main.get("_transitioning"))
		and main.get("_world") == world
		and main.get("_sea") == sea,
		"Only one World and Player exist; Main reflects transition state")
	_check(not sea.has_node("SeaDebugLayer") and not world.has_node("SeaSpeechBubble"),
		"Developer UI and speech remain outside the world SubViewport")
	_check(encounter != null and not sea.has_method("_start_first_fish_escape")
		and not sea.has_method("_start_silas_rescue"),
		"EncounterSequence owns scripted first-fish and Silas choreography")
	_check(encounter.fish_remove_requested.is_connected(
		Callable(sea, "_unregister_encounter_fish")),
		"Encounter requests world fish removal via a signal")
	_check(not encounter.has_method("_spawn_editor_fish")
		and sea.has_method("_spawn_editor_fish"),
		"World still owns fish spawning")
	_check(story.get("_events") is Dictionary and encounter.get("_story") == story,
		"StoryDirector remains the event and dialogue authority")

	main.queue_free()
	await process_frame
	print("FAILED: %d" % failures if failures > 0 else "Sea architecture boundaries passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, description: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + description)
	if not ok:
		failures += 1
