
extends Node

signal fish_hooked(item: FishData)
signal fish_caught(item: FishData)
signal fish_lost(item: FishData)

@export var possible_catches: Array[FishData] = []
@export var current_storage: Array[ItemData] = []

@export_category("Fishing Stats")
@export var max_casts_per_session: int = 3

func shop_reward_add_casts(amount: int) -> void:
	if amount <= 0:
		return

	max_casts_per_session += amount

# Get a random fish from the current pool of fish
func get_random_catch() -> FishData:
	if possible_catches.is_empty():
		return null

	return possible_catches.pick_random()

# Call when a fish has been hooked and the player must start reeling
func hook_fish(item: FishData) -> void:
	fish_hooked.emit(item)

# Call when the player has successfully caught the fish
func catch_fish(item: FishData) -> void:
	current_storage.append(item.item_data)
	fish_caught.emit(item.item_data)

# Call when the player has failed to catch the fish
func lose_fish(item: FishData) -> void:
	fish_lost.emit(item)
