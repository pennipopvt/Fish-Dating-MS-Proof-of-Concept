class_name BaitData
extends Resource

@export var bait_id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D = null
@export_multiline var description: String = ""
# Relative catch weight per FishData.fish_id. Fish not listed use default_weight.
# A weight of 0 or less means this bait can never catch that fish.
@export var catch_weights: Dictionary[StringName, float] = {}
@export var default_weight: float = 1.0

func get_weight(fish: FishData) -> float:
	if fish == null:
		return 0.0
	return catch_weights.get(fish.fish_id, default_weight)
