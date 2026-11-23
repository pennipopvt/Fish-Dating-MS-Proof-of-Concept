class_name SeaAmbienceController
extends Node

# Both looped WAV streams play continuously. Only their volumes change,
# so there is no restart/pop when switching between shore and the sea.
@export_group("Ambient Crossfade")
@export_range(0.0, 3.0, 0.05, "suffix:s") var crossfade_seconds: float = 0.7
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var ocean_volume_db: float = -2.0
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var underwater_volume_db: float = -3.0
@export_range(-80.0, -40.0, 1.0, "suffix:dB") var silent_volume_db: float = -80.0

@onready var _ocean: AudioStreamPlayer = $Ocean
@onready var _underwater: AudioStreamPlayer = $Underwater
var _fade: Tween


func _ready() -> void:
	# Keep both players looping even if an older .wav.import is cached.
	# Author the initial mix before starting playback; scene autoplay is a
	# fallback if the controller is ever disconnected.
	_ocean.volume_db = ocean_volume_db
	_underwater.volume_db = silent_volume_db
	if AudioServer.get_bus_index(&"Ambience") < 0:
		push_warning("No Ambience bus in default_bus_layout.tres; using Master.")
		_ocean.bus = &"Master"
		_underwater.bus = &"Master"
	for player in [_ocean, _underwater]:
		if player.stream == null:
			push_warning("Missing ambience stream on " + String(player.name))
			continue
		if player.stream is AudioStreamWAV:
			# Both WAV imports are already configured to loop. Only adjust the
			# resource in place if an older local import still has looping off.
			# NEVER replace player.stream after scene autoplay has begun:
			# doing so can silence the player while its playing flag stays true.
			var wav: AudioStreamWAV = player.stream as AudioStreamWAV
			if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if not player.playing:
			player.play()
	# Retry on the first ready frame: some imports initialize their stream
	# only after the containing scene has finished entering the tree.
	_ensure_playing.call_deferred()


func _ensure_playing() -> void:
	for player in [_ocean, _underwater]:
		if player.stream != null and not player.playing:
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
