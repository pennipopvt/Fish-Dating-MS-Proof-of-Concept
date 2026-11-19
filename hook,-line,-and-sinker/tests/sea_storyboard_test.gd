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
	var prompt: TextureRect = bubble.get_node("InputSprite") as TextureRect
	_check(not prompt.visible and bubble.get_node_or_null("InputPrompt") == null,
		"Only a hidden sprite exists; no full-screen tutorial panel")
	_check(not prompt.visible and prompt.texture == null,
		"InputSprite starts hidden with no imported-file dependency")
	_check(bubble.movement_sprite == null and bubble.cast_sprite == null
		and bubble.reel_sprite == null,
		"No preloaded PNGs are needed for the placeholder artwork")
	var first_fish: DivingWildFish = sea.get("_tutorial_fish") as DivingWildFish
	_check(first_fish != null, "FirstFish spawn creates the tutorial target")
	_check(first_fish.trapped, "First tutorial fish waits in place for a cast")
	story.on_dive_entered()
	_check(prompt.visible and bubble.current_action == &"move"
		and prompt.texture is ImageTexture,
		"Entering the sea generates a transparent WASD image with no import")
	_check(story.on_first_fish_seen(), "First fish focus is allowed only if the icon is visible")
	_check(bubble.current_action == &"cast" and prompt.texture is ImageTexture,
		"Noticing the fish replaces WASD with a mouse-click image")
	# The movement pause always expires even if no mouse event arrives.
	var player: Player = main.get_node("SubViewportContainer/SubViewport/World/Player") as Player
	player.busy = true
	sea.set("_fish_focus_locked", true)
	sea.set("_fish_focus_timer", 0.1)
	sea.call("_check_first_fish_focus", 0.2)
	_check(not player.busy and not bool(sea.get("_fish_focus_locked")),
		"Focus pause automatically releases; no invisible softlock")
	story.on_first_cast()
	_check(bubble.current_action == &"",
		"Casting dismisses the input cue without a timer")
	_check(story.wants_scripted_hook(first_fish, first_fish), "First hook is story-owned")
	story.on_scripted_hook()
	_check(bubble.current_action == &"reel" and prompt.texture is ImageTexture,
		"Hooking the fish generates the scrolling cue")
	_check(story.consume_first_reel(), "First scroll triggers the one-time line break")
	_check(not story.consume_first_reel(), "The same line-break cue cannot repeat")
	_check(story.has_event(&"line_broken"), "The story event records its completion")
	_check(bubble.current_action == &"", "The reel cue hides after the line breaks")
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
