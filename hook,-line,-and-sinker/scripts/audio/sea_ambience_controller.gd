class_name SeaAmbienceController
extends Node

# Both looped WAV streams play continuously. Only their volumes change,
# so there is no restart/pop when switching between shore and the sea.
@export_group("Ambient Crossfade")
@export_range(0.0, 3.0, 0.05, "suffix:s") var crossfade_seconds: float = 0.7
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var ocean_volume_db: float = -8.0
@export_range(-40.0, 12.0, 1.0, "suffix:dB") var underwater_volume_db: float = -10.0
@export_range(-80.0, -40.0, 1.0, "suffix:dB") var silent_volume_db: float = -80.0

@onready var _ocean: AudioStreamPlayer = $Ocean
@onready var _underwater: AudioStreamPlayer = $Underwater
var _fade: Tween


func _ready() -> void:
	for player in [_ocean, _underwater]:
		if player.stream is AudioStreamWAV:
			# Duplicate the imported stream rather than modifying shared source.
			var looping: AudioStreamWAV = (player.stream as AudioStreamWAV).duplicate()
			looping.loop_mode = AudioStreamWAV.LOOP_FORWARD
			player.stream = looping
		player.play()
	_ocean.volume_db = ocean_volume_db
	_underwater.volume_db = silent_volume_db


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
