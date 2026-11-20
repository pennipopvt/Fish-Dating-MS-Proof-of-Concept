extends Node
class_name SeaOxygen

# Separate oxygen resource; never alter fish combat, the global clock,
# inventory or tutorial story flags from here.
signal oxygen_changed(ratio: float, enabled: bool)
signal oxygen_depleted

@export_range(15.0, 300.0, 1.0) var capacity_seconds: float = 120.0
@export_range(0.05, 0.5, 0.01) var warning_fraction: float = 0.25

var enabled: bool = false
var remaining_seconds: float = 120.0
var _exhausted: bool = false
var _paused: bool = false


func ratio() -> float:
	return clampf(remaining_seconds / maxf(capacity_seconds, 0.01), 0.0, 1.0)


func begin_dive(unlocked: bool) -> void:
	remaining_seconds = capacity_seconds
	_exhausted = false
	_paused = false
	enabled = unlocked
	oxygen_changed.emit(ratio(), enabled)


# First activation occurs only after Penni catches a fish Silas weakened.
func activate() -> void:
	if enabled:
		return
	enabled = true
	_paused = false
	_exhausted = false
	remaining_seconds = capacity_seconds
	oxygen_changed.emit(ratio(), true)


func step(delta: float) -> void:
	if not enabled or _paused or _exhausted or delta <= 0.0:
		return
	remaining_seconds = maxf(0.0, remaining_seconds - delta)
	oxygen_changed.emit(ratio(), true)
	if remaining_seconds <= 0.0:
		_exhausted = true
		oxygen_depleted.emit()


func pause() -> void:
	_paused = true


func end_dive() -> void:
	enabled = false
	_paused = false
	_exhausted = false
	remaining_seconds = capacity_seconds
	oxygen_changed.emit(1.0, false)
