class_name UnderwaterMusicPlayer
extends AudioStreamPlayer2D

# The Music bus and its low-pass effect are authored in default_bus_layout.tres.
# This existing AudioStreamPlayer2D continues playing the SAME track; only
# its bus filter cutoff changes when SeaDiveTransition crosses the surface.
@export_group("Underwater Music Filter")
@export_range(100.0, 6000.0, 50.0) var underwater_cutoff_hz: float = 900.0
@export_range(1000.0, 20500.0, 100.0) var above_water_cutoff_hz: float = 20500.0
# The authored PenniDiveJump lasts 0.8s by default. Finish the fade into
# the underwater mix before its waterline/splash portion.
@export_range(0.0, 3.0, 0.05) var filter_transition_seconds: float = 0.4

var _low_pass: AudioEffectLowPassFilter
var _cutoff_tween: Tween


func _ready() -> void:
	# A correctly looped WAV should never finish. This also recovers from a
	# backend unexpectedly finishing a long music stream (including on web).
	finished.connect(_on_unexpected_music_end)
	var bus_index: int = AudioServer.get_bus_index(bus)
	if bus_index < 0:
		push_warning("Underwater music needs the authored Music audio bus.")
		return
	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect: AudioEffectLowPassFilter = AudioServer.get_bus_effect(
			bus_index, effect_index) as AudioEffectLowPassFilter
		if effect != null:
			_low_pass = effect
			break
	if _low_pass == null:
		push_warning("Music bus is missing its Low-Pass Filter effect.")
		return
	_low_pass.cutoff_hz = above_water_cutoff_hz


func set_underwater_filter(is_underwater: bool) -> void:
	if _low_pass == null:
		return
	if _cutoff_tween != null and _cutoff_tween.is_running():
		_cutoff_tween.kill()
	var target_hz: float = underwater_cutoff_hz if is_underwater else above_water_cutoff_hz
	if filter_transition_seconds <= 0.0:
		_low_pass.cutoff_hz = target_hz
		return
	_cutoff_tween = create_tween()
	_cutoff_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cutoff_tween.tween_property(_low_pass, "cutoff_hz", target_hz,
		filter_transition_seconds)


func _on_unexpected_music_end() -> void:
	# Only natural track endings emit finished; stop() does not.
	# This is a fallback, not the primary seamless loop mechanism.
	if is_inside_tree() and not playing:
		play()
