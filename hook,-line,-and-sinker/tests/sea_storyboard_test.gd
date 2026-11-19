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
	var encounter: SeaEncounterSequence = sea.get_node("EncounterSequence") as SeaEncounterSequence
	var bubble: SeaSpeechBubble = main.get_node("SeaSpeechBubble") as SeaSpeechBubble
	_check(story.get("_speech_bubble") == bubble,
		"Main binds the exact speech-bubble instance into the sea story")
	_check(main.get("_sea_bubble_source") == "authored scene"
		or main.get("_sea_bubble_source") == "recovered PackedScene"
		or main.get("_sea_bubble_source") == "runtime fallback",
		"Main reports the actual origin of its initialized bubble")
	var debug_layer: CanvasLayer = main.get_node_or_null("SeaDebugLayer") as CanvasLayer
	_check(debug_layer != null and not debug_layer.visible,
		"F7 diagnostics start hidden and cannot obstruct the game")
	var skip_button: Button = main.get_node("SeaDebugLayer/Panel/SkipDialogue") as Button
	_check(skip_button != null and skip_button.text == "Skip Dialogue"
		and skip_button.pressed.is_connected(Callable(main.get_node("SeaDebugLayer"), "skip_dialogue")),
		"F7 provides a clickable dialogue skip connected to Main")
	_check((main.get_node("SeaDebugLayer/Panel") as Panel).mouse_filter == Control.MOUSE_FILTER_STOP,
		"Clicking the debug panel never casts the underwater net")
	var f7: InputEventKey = InputEventKey.new()
	f7.keycode = KEY_F7
	f7.pressed = true
	main.call("_input", f7)
	_check(debug_layer.visible
		and (main.get_node("SeaDebugLayer/Panel/Diagnostics") as Label).text.contains("Silas distance"),
		"F7 exposes live trigger and UI-state diagnostics")
	main.call("_input", f7)
	_check(not debug_layer.visible, "F7 also hides diagnostics")
	main.call("_input", f7)
	var bubble_key: InputEventKey = InputEventKey.new()
	bubble_key.keycode = KEY_B
	bubble_key.pressed = true
	main.call("_input", bubble_key)
	_check(bubble.is_call_shown(),
		"B while F7 is open tests UI without the story")
	bubble.hide_call()
	debug_layer.visible = false
	_check(story.call("_bubble") == bubble,
		"Story resolves the explicitly injected speech-bubble instance")
	bubble.remove_from_group("sea_speech_bubble")
	_check(story.call("_bubble") == bubble,
		"Speech bubble remains bound even when group registration changes")
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
		and cue.reel_sprite == null and cue.right_click_sprite == null,
		"Fallback art needs no imported files; Inspector sprites are replaceable")
	var first_fish: DivingWildFish = encounter.tutorial_fish
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
	encounter.set("_fish_focus_locked", true)
	encounter.set("_fish_focus_timer", 0.1)
	encounter.call("_check_first_fish_focus", 0.2)
	_check(not player.busy and not bool(encounter.get("_fish_focus_locked")),
		"Focus pause automatically releases; no invisible softlock")
	story.on_first_cast()
	_check(cue.current_action == &"cast" and cue.visible,
		"Casting fades out the click sprite rather than creating another HUD")
	_check(story.wants_scripted_hook(first_fish, first_fish), "First hook is story-owned")
	# The first fish must physically move inward over several scrolls.
	encounter.call("_start_tutorial_reel", first_fish)
	story.on_scripted_hook()
	_check(cue.current_action == &"reel" and cue.visible,
		"Hooking the first fish shows the scroll sprite")
	var start_distance: float = player.position.distance_to(first_fish.position)
	for i in range(3):
		encounter.call("_reel_scripted_target")
	_check(player.position.distance_to(first_fish.position) < start_distance,
		"Three reels actually pull the first fish closer")
	_check(not story.has_event(&"line_broken"),
		"Fish does not break the line on the first reel")
	var net: DivingNetProjectile = sea.get_node("NetProjectile") as DivingNetProjectile
	_check(net.line_tension > 0.0, "Reeling makes the line start to strain")
	for i in range(10):
		if encounter.reel_mode != &"tutorial_reel":
			break
		encounter.call("_reel_scripted_target")
	_check(encounter.reel_mode == &"tutorial_break",
		"Near Penni, the tutorial enters a brief line-break panic")
	var tension_before: float = net.line_tension
	encounter.call("_advance_scripted_break", 0.35)
	_check(net.line_tension > tension_before,
		"Tension rises rapidly while the fish panics")
	encounter.call("_advance_scripted_break", 0.4)
	_check(story.has_event(&"line_broken"),
		"Line breaks after actual reeling and the tension spike")
	_check(not story.consume_first_reel(),
		"The one-time scripted line break cannot repeat")
	_check(not player.busy, "Movement unlocks as the fish escapes")
	_check(not (bubble.get_node("Call") as Control).visible,
		"No premature Silas voice during the reel or escape")
	_check(not story.can_talk_to_silas(),
		"Silas encounter stays gated until the offscreen call")
	_check(not (sea.get("_wild_fish") as Array).has(first_fish)
		and encounter.tutorial_fish == null,
		"Escaping fish immediately leaves normal catch simulation")
	_check(not bool(encounter.first_fish_escape_finished),
		"Fish is still visible during the dash")
	await create_timer(1.0).timeout
	_check(bool(encounter.first_fish_escape_finished),
		"Fish finishes its leftward dash and disappears")
	# The next line is delivered by the existing DialogueManager as Penni,
	# not as Silas or a second popup system.
	if DialogueManager.is_active and DialogueManager.current_npc != null \
			and DialogueManager.current_npc.npc_id != &"penni_monologue":
		DialogueManager.end_conversation()
		story.on_first_fish_escaped()
	var reaction: DialogueLineData = DialogueManager.get_current_line()
	_check(reaction != null and reaction.speaker == DialogueLineData.Speaker.PLAYER
		and reaction.text == "Damn, it got away.",
		"Escaped fish triggers Penni's own dialogue and portrait")
	if DialogueManager.is_active:
		DialogueManager.advance()
	encounter.call("_check_escape_followup")
	_check(not story.has_event(&"help_called"),
		"Waiting after the fish escapes does not summon Silas's bubble")
	player.position.x = float(encounter.help_reveal_x) - 2.0
	encounter.call("_check_escape_followup")
	_check(story.has_event(&"help_called")
		and bool(story.get("_help_ui_pending")),
		"Silas trigger records help_called without depending on rendering")
	_check((bubble.get_node("Call") as Control).visible,
		"Offscreen Help me bubble appears only after following the fish")
	_check(bubble.get_node("Call/Direction") == null
		and bubble.get_node("Call/Tail") is TextureRect,
		"Silas speech bubble uses the circle marker, not a direction arrow")
	_check((bubble.get_node("Call/Frame") as NinePatchRect).texture != null
		and (bubble.get_node("Call/Tail") as TextureRect).texture != null,
		"User-supplied bubble and circle textures loaded")
	_check(bubble.get("_speaker") == sea.get_node("NPCs/Silas"),
		"Bubble tracks Silas's actual world actor")
	_check((bubble.get_node("Call/Tail") as TextureRect).visible,
		"Circle marker follows the speaker independently of the bubble")
	_check(bubble.get_viewport() == main.get_viewport(),
		"Speech bubble uses the original working Main CanvasLayer")
	_check((bubble.scale * sea.get_viewport().get_visible_rect().size).distance_to(
		(main.get_node("SubViewportContainer") as Control).get_global_rect().size) < 1.0,
		"Outer CanvasLayer renders in the native game's pixel grid")
	_check(bubble.is_call_shown(),
		"Silas event leaves an actually visible speech bubble")
	_check(bubble.is_call_active(), "Help call stays active between repeated cries")
	_check((bubble.get_node("Call/Message") as Label).visible_characters == 0,
		"First cry begins with zero revealed letters")
	bubble.call("_update_animation", 0.35)
	var partial_letters: int = (bubble.get_node("Call/Message") as Label).visible_characters
	var partial_width: float = (bubble.get_node("Call") as Control).size.x
	bubble.call("_update_animation", 0.85)
	_check((bubble.get_node("Call/Message") as Label).visible_characters > partial_letters
		and (bubble.get_node("Call") as Control).size.x >= partial_width,
		"Letters type in and the nine-slice grows with them")
	bubble.call("_update_animation", 5.0)
	_check(bubble.is_call_active() and not bubble.is_call_shown(),
		"First cry fades out, then waits before repeating")
	bubble.call("_update_animation", 7.0)
	_check(bubble.is_call_active() and bubble.is_call_shown(),
		"Silas's cry appears again without replaying the story event")
	bubble.call("_update_attached_position")
	var call: Control = bubble.get_node("Call") as Control
	var call_rect: Rect2 = call.get_rect()
	var screen_rect: Rect2 = Rect2(Vector2.ZERO, sea.get_viewport().get_visible_rect().size)
	_check(call_rect.position.x >= 0.0 and call_rect.end.x <= screen_rect.end.x
		and call_rect.position.y >= 0.0 and call_rect.end.y <= screen_rect.end.y,
		"Offscreen speech bubble stays within the game viewport")
	var marker: TextureRect = bubble.get_node("Call/Tail") as TextureRect
	var actual_marker_position: Vector2 = call.position + marker.position + marker.size * 0.5
	var silas: Node2D = sea.get_node("NPCs/Silas") as Node2D
	var expected_marker_position: Vector2 = silas.get_global_transform_with_canvas() * Vector2(0.0, -10.0)
	expected_marker_position += Vector2(7.0, -8.0)
	expected_marker_position.x = clampf(expected_marker_position.x, 7.0, screen_rect.size.x - 7.0)
	expected_marker_position.y = clampf(expected_marker_position.y, 7.0, screen_rect.size.y - 7.0)
	_check(actual_marker_position.distance_to(expected_marker_position) < 6.0,
		"Detached circle marker stays near Silas rather than connecting to the frame")
	_check(is_zero_approx(marker.rotation), "The circle marker never rotates into a long tail")
	_check(story.can_talk_to_silas(), "Silas can be found after hearing him")
	_check(not story.can_net_silas(), "Silas is not net-catchable before speaking")
	bubble.hide_call()
	story.call("_process", 1.0)
	_check(bubble.is_call_shown(),
		"Help popup retries after being unexpectedly hidden")
	# A player who simply swims past the first fish still hears Silas.
	bubble.hide_call()
	var session_events: Dictionary = story.get("_events")
	session_events.erase(&"line_broken")
	session_events.erase(&"help_called")
	encounter.set("_first_fish_escape_finished", false)
	var silas_actor: Node2D = sea.get_node("NPCs/Silas") as Node2D
	player.position = silas_actor.position + Vector2(40.0, 0.0)
	encounter.call("_check_escape_followup")
	_check(story.has_event(&"help_called") and bubble.is_call_shown(),
		"Silas speech remains discoverable when the first fish is skipped")
	_check((bubble.get_node("Call") as Control).size.x <= 132,
		"Speech bubble uses native game-pixel dimensions")
	# Deliberately remove the instance, reproducing the actual live bug.
	bubble.name = "SimulatedMissingBubble"
	bubble.hide_call()
	var recovered: SeaSpeechBubble = main.call("_ensure_sea_speech_bubble") as SeaSpeechBubble
	_check(recovered != null and recovered != bubble and recovered.is_node_ready(),
		"Main reconstructs speech UI when its authored instance is missing")
	_check(recovered.get_node_or_null("Call/Message") is Label
		and recovered.get_node_or_null("Call/Frame") is NinePatchRect,
		"Reconstructed bubble contains all expected UI children")
	var recovered_marker: TextureRect = recovered.get_node("Call/Tail") as TextureRect
	_check(recovered_marker.texture != null
		and recovered_marker.size == Vector2(recovered_marker.texture.get_size())
		and recovered_marker.scale == Vector2.ONE,
		"Recovered speaker marker also keeps native game-pixel density")
	recovered.show_call("Recovery test", false, 0.0)
	_check(recovered.is_call_shown(),
		"Recovered bubble actually becomes visible after show_call")
	main.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Sea storyboard events passed")
	quit(1 if failures > 0 else 0)

func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
