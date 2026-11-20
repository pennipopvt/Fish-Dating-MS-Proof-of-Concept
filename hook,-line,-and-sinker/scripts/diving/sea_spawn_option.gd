extends Resource
class_name SeaSpawnOption

# Inspector-editable weighting for one species in a habitat.
@export var species: FishData
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
# An authored minimum ensures the first contract cannot be blocked by RNG.
@export_range(0, 12, 1) var minimum_count: int = 0
# Probability changes are data, not species hard locks. Step 3 will
# trigger a new roll when the morning/afternoon/night period changes.
@export_range(0.0, 4.0, 0.1) var morning_factor: float = 1.0
@export_range(0.0, 4.0, 0.1) var afternoon_factor: float = 1.0
@export_range(0.0, 4.0, 0.1) var night_factor: float = 1.0


func effective_weight(period: int) -> float:
	var multiplier: float = 1.0
	match period:
		GameManager.Times.MORNING:
			multiplier = morning_factor
		GameManager.Times.AFTERNOON:
			multiplier = afternoon_factor
		GameManager.Times.NIGHT:
			multiplier = night_factor
	return maxf(0.0, weight * multiplier)
