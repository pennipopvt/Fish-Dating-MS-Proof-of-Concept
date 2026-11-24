extends Node

# Run: godot --headless --path . res://tests/web_music_playback_test.tscn
# Checks the web-specific audio routing and continuous music import settings.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var music: UnderwaterMusicPlayer = main.get_node("AudioStreamPlayer2D") as UnderwaterMusicPlayer
	var song: AudioStreamWAV = music.stream as AudioStreamWAV
	_check(song != null and song.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"Current From the Sea WAV loops forward when it reaches its end")
	_check(music.playback_type == AudioServer.PLAYBACK_TYPE_STREAM,
		"Music forces Stream playback to enable bus filters on web")
	var music_bus: int = AudioServer.get_bus_index(&"Music")
	var music_lowpass: AudioEffectLowPassFilter = null
	if music_bus >= 0:
		for i in AudioServer.get_bus_effect_count(music_bus):
			music_lowpass = AudioServer.get_bus_effect(music_bus, i) as AudioEffectLowPassFilter
			if music_lowpass != null:
				break
	_check(music.bus == &"Music" and music_lowpass != null,
		"Music stream routes through a real low-pass bus")
	if music_lowpass != null:
		music.filter_transition_seconds = 0.0
		music.set_underwater_filter(true)
		_check(is_equal_approx(music_lowpass.cutoff_hz, music.underwater_cutoff_hz),
			"Diving reduces music low-pass cutoff to underwater value")
		music.set_underwater_filter(false)
		_check(is_equal_approx(music_lowpass.cutoff_hz, music.above_water_cutoff_hz),
			"Returning to shore restores music high-frequency content")
	var swimmer: SwimSoundFader = main.get_node(
		"SubViewportContainer/SubViewport/World/Player/SwimSound") as SwimSoundFader
	var sfx_bus: int = AudioServer.get_bus_index(&"UnderwaterSFX")
	var swim_loop: AudioStreamWAV = swimmer.stream as AudioStreamWAV
	_check(swim_loop != null and swim_loop.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"Swimming sound WAV also loops continuously during sustained movement")
	_check(swimmer.playback_type == AudioServer.PLAYBACK_TYPE_STREAM
		and swimmer.bus == &"UnderwaterSFX",
		"Swim loop also streams through the underwater low-pass bus")
	_check(sfx_bus >= 0 and AudioServer.get_bus_effect_count(sfx_bus) > 0
		and AudioServer.get_bus_effect(sfx_bus, 0) is AudioEffectLowPassFilter,
		"Underwater SFX bus has its intended low-pass effect")
	var shore: AudioStreamPlayer = main.get_node("SeaAmbience/Ocean") as AudioStreamPlayer
	_check(shore.playback_type == AudioServer.PLAYBACK_TYPE_DEFAULT,
		"Unfiltered ambience keeps default low-latency web playback")
	_check(not music.playing, "No music plays over the title screen")
	main.call("_on_island_reached")
	_check(music.playing, "Reaching the island starts the music")
	music.stop()
	music.finished.emit()
	_check(music.playing, "Unexpected natural song ending restarts the track")

	main.queue_free()
	await get_tree().process_frame
	print("web_music_playback_test: PASS" if failures == 0 else
		"web_music_playback_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
