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
	var cue: SeaTutorialCue = main.get_node(
		"SubViewportContainer/SubViewport/World/Player/Camera2D/SeaTutorialCue"
	) as SeaTutorialCue
	_check(cue != null and not cue.visible,
		"Camera has a hidden tutorial sprite before diving")
	_check(cue.z_index > 80 and not cue.z_as_relative,
		"Control cue renders above the underwater tint in the game viewport")
	_check(cue.movement_sprite == null and cue.cast_sprite == null
		and cue.reel_sprite == null,
		"Fallback art needs no imported files; Inspector sprites are replaceable")
	var first_fish: DivingWildFish = sea.get("_tutorial_fish") as DivingWildFish
	_check(first_fish != null, "FirstFish spawn creates the tutorial target")
	_check(first_fish.trapped, "First tutorial fish waits in place for a cast")
	story.on_dive_entered()
	_check(cue.visible and cue.current_action == &"move",
		"Entering the sea shows WASD on the Player camera")
	_check(story.on_first_fish_seen(), "First fish focus is allowed only if the icon is visible")
	_check(cue.current_action == &"cast" and cue.visible,
		"Fish discovery replaces WASD with click in the same camera viewport")
	# The movement pause always expires even if no mouse event arrives.
	var player: Player = main.get_node("SubViewportContainer/SubViewport/World/Player") as Player
	player.busy = true
	sea.set("_fish_focus_locked", true)
	sea.set("_fish_focus_timer", 0.1)
	sea.call("_check_first_fish_focus", 0.2)
	_check(not player.busy and not bool(sea.get("_fish_focus_locked")),
		"Focus pause automatically releases; no invisible softlock")
	story.on_first_cast()
	_check(cue.current_action == &"cast" and cue.visible,
		"Casting fades out the click sprite rather than creating another HUD")
	_check(story.wants_scripted_hook(first_fish, first_fish), "First hook is story-owned")
	story.on_scripted_hook()
	_check(cue.current_action == &"reel" and cue.visible,
		"Hooking the first fish shows the scroll sprite")
	_check(story.consume_first_reel(), "First scroll triggers the one-time line break")
	_check(not story.consume_first_reel(), "The same line-break cue cannot repeat")
	_check(story.has_event(&"line_broken"), "The story event records its completion")
	_check(cue.visible, "The reel cue fades out after the line breaks")
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
