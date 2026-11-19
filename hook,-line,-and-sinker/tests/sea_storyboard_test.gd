extends SceneTree

# Small state-machine smoke test for the first fish and offscreen speech cue.
# Run: godot --headless --path . -s res://tests/sea_storyboard_test.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = MAIN.instantiate()
	get_root().add_child(main)
	await process_frame
	var sea: DivingWorld = main.get_node("SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var bubble: SeaSpeechBubble = main.get_node("SeaSpeechBubble") as SeaSpeechBubble
	var prompt: SeaInputPrompt = bubble.get_node("InputPrompt") as SeaInputPrompt
	var first_fish: DivingWildFish = sea.get("_tutorial_fish") as DivingWildFish
	_check(first_fish != null, "FirstFish spawn creates the tutorial target")
	_check(first_fish.trapped, "First tutorial fish waits in place for a cast")
	story.on_dive_entered()
	_check(prompt.visible and prompt.current_action == &"move",
		"Entering the sea shows the animated WASD prompt, not the corner text")
	story.on_first_fish_seen()
	_check(prompt.current_action == &"cast",
		"Noticing the fish replaces movement with the left-click cue")
	story.on_first_cast()
	_check(prompt.current_action == &"",
		"Casting dismisses the input cue without a timer")
	_check(story.wants_scripted_hook(first_fish, first_fish), "First hook is story-owned")
	story.on_scripted_hook()
	_check(prompt.current_action == &"reel",
		"Hooking the first fish introduces the scrolling cue")
	_check(story.consume_first_reel(), "First scroll triggers the one-time line break")
	_check(not story.consume_first_reel(), "The same line-break cue cannot repeat")
	_check(story.has_event(&"line_broken"), "The story event records its completion")
	_check(prompt.current_action == &"", "The reel cue hides after the line breaks")
	_check((bubble.get_node("Call") as Control).visible,
		"Offscreen Help me bubble appears after the break")
	_check(story.can_talk_to_silas(), "Silas can be found after the first escape")
	_check(not story.can_net_silas(), "Silas is not net-catchable before speaking")
	main.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Sea storyboard events passed")
	quit(1 if failures > 0 else 0)

func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
