class_name SeaAmbienceController
extends Node

# Both looped WAV streams play continuously. Only their volumes change,
# so there is no restart/pop when switching between shore and the sea.
@export_group("Ambient Crossfade")
@export_range(0.0, 3.0, 0.05, "suffix:s") var crossfade_seconds: float = 0.7
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var ocean_volume_db: float = -2.0
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var underwater_volume_db: float = -3.0
@export_range(-80.0, -40.0, 1.0, "suffix:dB") var silent_volume_db: float = -80.0
@export_range(0.2, 3.0, 0.1, "suffix:s") var playback_check_seconds: float = 0.5

@onready var _ocean: AudioStreamPlayer = $Ocean
@onready var _underwater: AudioStreamPlayer = $Underwater
var _fade: Tween
var _playback_check_elapsed: float = 0.0
var _warned_missing_bus: bool = false


func _ready() -> void:
	_ocean.volume_db = ocean_volume_db
	_underwater.volume_db = silent_volume_db
	for player in [_ocean, _underwater]:
		if player.stream == null:
			push_warning("Missing ambience stream on " + String(player.name))
			continue
		# Keep the imported WAV attached to the node; replacing the stream
		# after scene autoplay can stop a previously running player.
		if player.stream is AudioStreamWAV:
			var wav: AudioStreamWAV = player.stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# Recover immediately if the imported file stops despite its loop flag.
		player.finished.connect(_on_ambience_finished.bind(player))
	_ensure_playing()
	_ensure_playing.call_deferred()


func _process(delta: float) -> void:
	# A lightweight safety check catches an unexpected stopped player (as
	# observed on the title screen) without retriggering playing audio.
	_playback_check_elapsed += delta
	if _playback_check_elapsed >= playback_check_seconds:
		_playback_check_elapsed = 0.0
		_ensure_playing()


func _on_ambience_finished(player: AudioStreamPlayer) -> void:
	# Imported ambience should loop seamlessly. If it ever finishes,
	# restart it instead of leaving the title screen silent.
	if player.stream != null and not player.playing:
		player.play()


func _ensure_playing() -> void:
	var has_ambience_bus: bool = AudioServer.get_bus_index(&"Ambience") >= 0
	if not has_ambience_bus and not _warned_missing_bus:
		push_warning("Ambience bus is missing. Check default_bus_layout.tres.")
		_warned_missing_bus = true
	for player in [_ocean, _underwater]:
		if player.stream == null:
			continue
		# Main installs the authored bus layout before child nodes initialize.
		# Reassign here too: Godot can fall back to Master if the bus wasn't
		# available when the scene's AudioStreamPlayer was deserialized.
		if has_ambience_bus and player.bus != &"Ambience":
			player.bus = &"Ambience"
		if not player.playing:
			player.play()


func set_underwater(enabled: bool) -> void:
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
