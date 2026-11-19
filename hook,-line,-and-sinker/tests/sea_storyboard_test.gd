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
	_check(story.call("_bubble") == bubble,
		"Story resolves speech bubble directly from its own game SubViewport")
	bubble.remove_from_group("sea_speech_bubble")
	_check(story.call("_bubble") == bubble,
		"Bubble lookup is independent of global group registration")
	bubble.add_to_group("sea_speech_bubble")
	var cue: SeaTutorialCue = main.get_node(
		"SubViewportContainer/SubViewport/World/Player/Camera2D/SeaTutorialCue"
	) as SeaTutorialCue
	_check(cue != null and not cue.visible,
		"Camera has a hidden tutorial sprite before diving")
	_check(cue is Sprite2D and cue.get_parent() is Camera2D,
		"Sea controller creates a real Sprite2D under the Player camera")
	_check((cue.get_parent() as Camera2D).get_script() == null,
		"Existing player camera remains unscripted")
	_check(cue.get_parent().get_child_count() >= 2,
		"Tutorial cue is an ordinary child, not a required PackedScene")
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
	_check(not (bubble.get_node("Call") as Control).visible,
		"No premature Help me bubble on the first reel")
	_check(not story.can_talk_to_silas(),
		"Silas encounter stays gated until the offscreen call")
	sea.call("_start_first_fish_escape")
	_check(not (sea.get("_wild_fish") as Array).has(first_fish)
		and sea.get("_tutorial_fish") == null,
		"Escaping fish leaves normal swim/catch simulation immediately")
	_check(not bool(sea.get("_first_fish_escape_finished")),
		"Fish is still visible during the dash")
	await create_timer(1.0).timeout
	_check(bool(sea.get("_first_fish_escape_finished")),
		"Fish finishes its leftward dash and disappears")
	sea.call("_check_escape_followup")
	_check(not story.has_event(&"help_called"),
		"Waiting after the fish escapes does not summon Silas's bubble")
	player.position.x = float(sea.get("_help_reveal_x")) - 2.0
	sea.call("_check_escape_followup")
	_check(story.has_event(&"help_called"),
		"Swimming farther left triggers Silas's one-time help call")
	_check((bubble.get_node("Call") as Control).visible,
		"Offscreen Help me bubble appears only after following the fish")
	_check(bubble.get_node("Call/Direction") == null
		and bubble.get_node("Call/Tail") is TextureRect,
		"Silas speech bubble uses the supplied tail, not a separate arrow")
	_check((bubble.get_node("Call/Frame") as NinePatchRect).texture != null
		and (bubble.get_node("Call/Tail") as TextureRect).texture != null,
		"User-supplied bubble and tail textures loaded")
	_check(bubble.get("_speaker") == sea.get_node("NPCs/Silas"),
		"Bubble tracks Silas's actual world actor")
	_check((bubble.get_node("Call/Tail") as TextureRect).visible,
		"Tail shows while tracking Silas")
	_check(bubble.get_viewport() == main.get_viewport(),
		"Speech bubble uses the original working Main CanvasLayer")
	_check(bubble.scale == Vector2.ONE,
		"Silas bubble does not use fragile CanvasLayer scale transforms")
	_check(bubble.is_call_shown(),
		"Silas event leaves an actually visible speech bubble")
	bubble.call("_update_attached_position")
	var call: Control = bubble.get_node("Call") as Control
	var call_rect: Rect2 = call.get_rect()
	var screen_rect: Rect2 = (main.get_node("SubViewportContainer") as Control).get_global_rect()
	_check(call_rect.position.x >= 0.0 and call_rect.end.x <= screen_rect.end.x
		and call_rect.position.y >= 0.0 and call_rect.end.y <= screen_rect.end.y,
		"Offscreen speech bubble stays within the game viewport")
	var tail: TextureRect = bubble.get_node("Call/Tail") as TextureRect
	var base_position: Vector2 = tail.position + tail.pivot_offset + (
		Vector2(tail.size.x * 0.5, 0.0) - tail.pivot_offset
	).rotated(tail.rotation)
	var edge_distance: float = minf(
		minf(absf(base_position.x), absf(base_position.x - call.size.x)),
		minf(absf(base_position.y), absf(base_position.y - call.size.y))
	)
	_check(edge_distance <= 2.5,
		"The speech tail flat base connects at the outer bubble border")
	_check(story.can_talk_to_silas(), "Silas can be found after hearing him")
	_check(not story.can_net_silas(), "Silas is not net-catchable before speaking")
	# A player who simply swims past the first fish still hears Silas.
	bubble.hide_call()
	var session_events: Dictionary = story.get("_events")
	session_events.erase(&"line_broken")
	session_events.erase(&"help_called")
	sea.set("_first_fish_escape_finished", false)
	var silas_actor: Node2D = sea.get_node("NPCs/Silas") as Node2D
	player.position = silas_actor.position + Vector2(40.0, 0.0)
	sea.call("_check_escape_followup")
	_check(story.has_event(&"help_called") and bubble.is_call_shown(),
		"Silas speech remains discoverable when the first fish is skipped")
	_check((bubble.get_node("Call") as Control).size.x >= 300,
		"Restored bubble has the readable size used in working builds")
	main.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Sea storyboard events passed")
	quit(1 if failures > 0 else 0)

func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
