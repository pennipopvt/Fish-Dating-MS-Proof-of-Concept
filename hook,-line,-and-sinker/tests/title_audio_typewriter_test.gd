extends Node

# Run: godot --headless --path . res://tests/title_audio_typewriter_test.tscn
# Verifies the title/ambient audio and native typewriter presentation.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var title: GameTitleScreen = main.get_node("TitleScreen") as GameTitleScreen
	var opening: FishCoOpeningSequence = main.get_node("IntroLayer") as FishCoOpeningSequence
	var ambience: SeaAmbienceController = main.get_node("SeaAmbience") as SeaAmbienceController
	var ocean: AudioStreamPlayer = ambience.get_node("Ocean") as AudioStreamPlayer
	var below: AudioStreamPlayer = ambience.get_node("Underwater") as AudioStreamPlayer
	var music: UnderwaterMusicPlayer = main.get_node("AudioStreamPlayer2D") as UnderwaterMusicPlayer
	var ui: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI

	_check(title.visible and not music.playing and not DialogueManager.is_active,
		"Startup displays title without music or Fish Co dialogue")
	_check(ocean.playing and below.playing and ocean.stream is AudioStreamWAV
		and (ocean.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
		and (below.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"Both ambience WAVs loop while playback continues")

	ambience.crossfade_seconds = 0.0
	ambience.set_underwater(true)
	_check(is_equal_approx(ocean.volume_db, ambience.silent_volume_db)
		and is_equal_approx(below.volume_db, ambience.underwater_volume_db),
		"Underwater mix enables only the underwater ambience")
	ambience.set_underwater(false)
	_check(is_equal_approx(ocean.volume_db, ambience.ocean_volume_db)
		and is_equal_approx(below.volume_db, ambience.silent_volume_db),
		"Surface mix restores only ocean ambience")

	opening.title_pan_seconds = 0.0
	title.call("_on_play")
	await get_tree().process_frame
	_check(not title.visible and DialogueManager.is_active and ui.visible,
		"Play starts the existing dialogue after the camera pan")
	var line: DialogueLineData = DialogueManager.get_current_line()
	_check(ui.get_node("%TextLabel") is RichTextLabel
		and bool(ui.get("_typewriting")),
		"Dialogue uses RichTextLabel with enabled typewriter animation")
	ui.call("_advance")
	_check(DialogueManager.get_current_line() == line
		and not bool(ui.get("_typewriting")),
		"First Continue reveals text without advancing the conversation")

	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	main.queue_free()
	await get_tree().process_frame
	print("title_audio_typewriter_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, description: String) -> void:
	if ok:
		print("  ok   ", description)
	else:
		failures += 1
		push_error("  FAIL " + description)
