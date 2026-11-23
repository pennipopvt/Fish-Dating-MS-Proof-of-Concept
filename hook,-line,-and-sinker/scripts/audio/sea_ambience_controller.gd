class_name SeaAmbienceController
extends Node

# Both ambient OGG streams loop continuously; only their
# volumes change during a dive. Restart a stream only if playback stopped.
@export_group("Playback Recovery")
@export_range(0.25, 5.0, 0.25, "suffix:s") var playback_check_seconds: float = 1.0

@export_group("Ambient Crossfade")
@export_range(0.0, 3.0, 0.05, "suffix:s") var crossfade_seconds: float = 0.7
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var ocean_volume_db: float = -2.0
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var underwater_volume_db: float = -3.0
@export_range(-80.0, -40.0, 1.0, "suffix:dB") var silent_volume_db: float = -80.0

@onready var _ocean: AudioStreamPlayer = $Ocean
@onready var _underwater: AudioStreamPlayer = $Underwater
var _fade: Tween
var _warned_missing_bus: bool = false
var _playback_guard: Timer


func _ready() -> void:
	_ocean.volume_db = ocean_volume_db
	_underwater.volume_db = silent_volume_db
	# Both streams loop through their import settings. Do not edit stream
	# resources after the child AudioStreamPlayers have already autoplayed.
	_ensure_playing()
	# Stream playback can unexpectedly stop after a device/import reset.
	# Keep one lightweight guard instead of starting sounds every frame.
	_playback_guard = Timer.new()
	_playback_guard.name = "AmbiencePlaybackGuard"
	_playback_guard.wait_time = playback_check_seconds
	_playback_guard.timeout.connect(_ensure_playing)
	add_child(_playback_guard)
	_playback_guard.start()
	_check_startup_audio.call_deferred()


func _ensure_playing() -> void:
	var has_bus: bool = AudioServer.get_bus_index(&"Ambience") >= 0
	if not has_bus and not _warned_missing_bus:
		push_warning("Ambience bus missing; temporarily routing sound to Master.")
		_warned_missing_bus = true
	for player in [_ocean, _underwater]:
		if player.stream == null:
			push_error("Missing ambience audio on " + String(player.name))
			continue
		player.bus = &"Ambience" if has_bus else &"Master"
		if not player.playing:
			player.play()


func _check_startup_audio() -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	for player in [_ocean, _underwater]:
		if player.stream != null and not player.playing:
			push_error("Ambience %s stopped after starting (length %.2fs). Check stream looping/import settings." % [
				String(player.name), player.stream.get_length()
			])


func set_underwater(enabled: bool) -> void:
	# A dive/surface transition must never crossfade into a stopped stream.
	_ensure_playing()
	if _fade != null and _fade.is_running():
		_fade.kill()
	var ocean_target: float = silent_volume_db if enabled else ocean_volume_db
	var underwater_target: float = underwater_volume_db if enabled else silent_volume_db
	if crossfade_seconds <= 0.0:
		_ocean.volume_db = ocean_target
		_underwater.volume_db = underwater_target
		return
	_fade = create_tween()
	_fade.set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade.tween_property(_ocean, "volume_db", ocean_target, crossfade_seconds)
	_fade.tween_property(_underwater, "volume_db", underwater_target, crossfade_seconds)
