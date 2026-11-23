class_name SwimSoundFader
extends AudioStreamPlayer

# Dedicated gain envelope for Penni's swimming loop. Volume and Pitch Scale
# are authored on this AudioStreamPlayer in prefabs/player.tscn, not on Player.
@export_group("Swim Fades")
@export_range(0.0, 2.0, 0.05, "suffix:s") var fade_in_seconds: float = 0.35
@export_range(0.0, 2.0, 0.05, "suffix:s") var fade_out_seconds: float = 0.45

const SILENT_DB: float = -80.0

var _normal_volume_db: float
var _is_active: bool = false
var _fade: Tween


func _ready() -> void:
	# Capture the scene-authored volume once. Fade automation uses this level,
	# never a hardcoded loudness or another duplicate Player export.
	_normal_volume_db = volume_db
	volume_db = SILENT_DB
	if playing:
		stop()


func set_swimming_active(active: bool) -> void:
	# Called each frame but only transition when the movement state changes.
	if active == _is_active:
		return
	_is_active = active
	if _fade != null and _fade.is_running():
		_fade.kill()
	if active:
		if not playing:
			volume_db = SILENT_DB
			play()
		_fade_to(_normal_volume_db, fade_in_seconds)
	elif playing:
		_fade_to(SILENT_DB, fade_out_seconds, true)


func _fade_to(target_db: float, duration: float, stop_at_end: bool = false) -> void:
	if duration <= 0.0:
		volume_db = target_db
		if stop_at_end and not _is_active:
			stop()
		return
	_fade = create_tween()
	_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade.tween_property(self, "volume_db", target_db, duration)
	if stop_at_end:
		_fade.finished.connect(_finish_fade_out)


func _finish_fade_out() -> void:
	# A new movement input kills the prior fade, keeping the same loop alive.
	if not _is_active:
		stop()
		volume_db = SILENT_DB


func get_authored_volume_db() -> float:
	return _normal_volume_db


func is_swimming_active() -> bool:
	return _is_active
