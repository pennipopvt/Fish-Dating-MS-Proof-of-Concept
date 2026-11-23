extends Node

# Run: godot --headless --path . res://tests/title_audio_typewriter_test.tscn
# Verifies the title/ambient audio and native typewriter presentation.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const OCEAN_AUDIO: AudioStream = preload("res://sounds/sfx/207553__bone666138__ocean-ambience-costal-with-foghorn.wav")
const UNDERWATER_AUDIO: AudioStream = preload("res://sounds/sfx/504641__fission9__underwater-ambience.wav")
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
	_check(AudioServer.get_bus_index(&"Music") >= 0
		and AudioServer.get_bus_index(&"Ambience") >= 0
		and AudioServer.get_bus_index(&"UnderwaterSFX") >= 0,
		"Audio buses are ready before the title, even if editor loaded Master only")
	_check(ocean.autoplay and below.autoplay,
		"Ambience stream players start even if controller initialization fails")
	_check(ocean.bus == &"Ambience" and below.bus == &"Ambience",
		"Runtime ambience players route to Ambience instead of falling back to Master")
	_check(ocean.stream == OCEAN_AUDIO and below.stream == UNDERWATER_AUDIO,
		"Ambience controller leaves autoplay streams attached instead of interrupting them")
	_check((ocean.stream as AudioStreamWAV).format != AudioStreamWAV.FORMAT_QOA
		and (below.stream as AudioStreamWAV).format != AudioStreamWAV.FORMAT_QOA,
		"Ambience WAVs import as PCM rather than QOA on Godot 4.7")
	_check(ocean.playing and below.playing and ocean.stream is AudioStreamWAV
		and (ocean.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
		and (below.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"Both ambience WAVs loop while playback continues")
	await get_tree().create_timer(1.1).timeout
	_check(ocean.playing and below.playing,
		"Title ambience remains playing after startup, not just for one frame")

	# Reproduce the actual Remote Inspector screenshot: a stopped player on
	# the Master bus even though Autoplay is enabled.
	ocean.stop()
	ocean.bus = &"Master"
	ambience.call("_ensure_playing")
	_check(ocean.playing and ocean.bus == &"Ambience",
		"Ambience controller revives stopped playback and fixes its bus")
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
	var rich_label: RichTextLabel = ui.get_node("%TextLabel") as RichTextLabel
	_check(rich_label.scroll_active and rich_label.scroll_following_visible_characters,
		"Long dialogue scrolls with the revealed letters instead of clipping")
	_check(ui.get_node_or_null("DialogueVoice") is AudioStreamPlayer
		and ui.get_node_or_null("VoicePlayback") is AudioStreamPlayer
		and is_equal_approx(ui.penni_pitch_variation, 0.08),
		"DialogueVoice owns Penni's pitch and a separate player applies speaker variation")
	# Regression: changing the INSPECTOR Pitch Scale must affect real playback.
	# Prior code set DialogueVoice.pitch_scale to an unrelated root export
	# every letter, silently discarding the editor's 1.2.
	var voice_node: AudioStreamPlayer = ui.get_node("DialogueVoice") as AudioStreamPlayer
	var playback: AudioStreamPlayer = ui.get_node("VoicePlayback") as AudioStreamPlayer
	voice_node.volume_db = -2.0
	voice_node.pitch_scale = 0.65
	ui.penni_pitch_variation = 0.0
	ui.set("_spoken_text", "A")
	ui.set("_current_line_player", true)
	ui.call("_play_letter_sound", 0)
	_check(is_equal_approx(voice_node.volume_db, -2.0)
		and is_equal_approx(voice_node.pitch_scale, 0.65),
		"Typing never overwrites DialogueVoice's editor volume or pitch")
	_check(is_equal_approx(playback.pitch_scale, 0.65)
		and is_equal_approx(playback.volume_db, -2.0)
		and playback.playing,
		"Actual Penni playback uses the edited DialogueVoice pitch and volume")
	voice_node.pitch_scale = 1.4
	ui.call("_play_letter_sound", 0)
	_check(is_equal_approx(playback.pitch_scale, 1.4),
		"Changing the authored pitch while running affects the next letter")
	var voice_config: NPCData = NPCData.new()
	voice_config.voice_pitch_scale = 1.3
	voice_config.voice_pitch_variation = 0.0
	ui.set("_current_line_player", false)
	ui.set("_current_voice_npc", voice_config)
	ui.call("_play_letter_sound", 0)
	_check(is_equal_approx(playback.pitch_scale, 1.3),
		"NPCData pitch overrides remain independent of Penni's pitch")
	ui.set("_current_line_player", true)
	ui.call("_play_letter_sound", 0)
	_check(is_equal_approx(playback.pitch_scale, 1.4),
		"Penni returns to her own Inspector pitch after an NPC speaks")
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
