extends Node
class_name SeaOxygen

# Separate oxygen resource; never alter fish combat, the global clock,
# inventory or tutorial story flags from here.
signal oxygen_changed(ratio: float, enabled: bool)
signal oxygen_depleted

@export_range(15.0, 300.0, 1.0) var capacity_seconds: float = 120.0
@export_range(0.05, 0.5, 0.01) var warning_fraction: float = 0.25

@export_group("Depth Drain")
# World-space y=154 is the current sea's waterline. Exposed separately
# from the editor guide so designers can adjust the water level later.
@export var waterline_y: float = 154.0
# Smooth linear ramp from surface consumption to the capped deep rate.
@export_range(100.0, 1200.0, 10.0) var depth_ramp_pixels: float = 480.0
@export_range(1.0, 3.0, 0.05) var deepest_drain_multiplier: float = 1.8

var enabled: bool = false
var remaining_seconds: float = 120.0
var _exhausted: bool = false
var _paused: bool = false


# This Inspector-edited capacity is the base tank, not the upgrade itself.
func effective_capacity_seconds() -> float:
	return maxf(capacity_seconds + FishingManager.oxygen_capacity_bonus_seconds, 0.01)


func ratio() -> float:
	return clampf(remaining_seconds / effective_capacity_seconds(), 0.0, 1.0)


func begin_dive(unlocked: bool) -> void:
	remaining_seconds = effective_capacity_seconds()
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
	remaining_seconds = effective_capacity_seconds()
	oxygen_changed.emit(ratio(), true)


# One oxygen resource owns the depth formula. World supplies position only;
# other systems and existing tests can omit it for surface-rate depletion.
func drain_multiplier_at_depth(world_y: float) -> float:
	var depth_fraction: float = clampf(
		(world_y - waterline_y) / maxf(depth_ramp_pixels, 1.0), 0.0, 1.0)
	var deep_extra_drain: float = maxf(0.0, deepest_drain_multiplier - 1.0)
	deep_extra_drain *= 1.0 - FishingManager.depth_drain_reduction_fraction
	return lerpf(1.0, 1.0 + deep_extra_drain, depth_fraction)


func step(delta: float, world_y: float = 154.0) -> void:
	if not enabled or _paused or _exhausted or delta <= 0.0:
		return
	remaining_seconds = maxf(0.0,
		remaining_seconds - delta * drain_multiplier_at_depth(world_y))
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
	remaining_seconds = effective_capacity_seconds()
	oxygen_changed.emit(1.0, false)
