
extends Node

signal fish_hooked(item: FishData)
signal fish_caught(item: FishData)
signal fish_lost(item: FishData)
signal bait_changed(bait: BaitData)

@export var possible_catches: Array[FishData] = []
@export var current_storage: Array[ItemData] = []

@export_category("Bait")
@export var available_baits: Array[BaitData] = []
# Applies to the next cast. A fish that's already decided is never swapped.
@export var equipped_bait: BaitData = null

@export_category("Fishing Stats")
@export var max_casts_per_session: int = 3

func shop_reward_add_casts(amount: int) -> void:
	if amount <= 0:
		return

	max_casts_per_session += amount

func equip_bait(bait: BaitData) -> void:
	if bait == equipped_bait:
		return

	equipped_bait = bait
	bait_changed.emit(bait)

# Get a random fish from the current pool, weighted by the equipped bait.
# Returns null if the pool has no catchable fish.
func get_random_catch() -> FishData:
	return pick_catch(possible_catches, equipped_bait)

# Single rule for which species a cast hooks. Static so tests can run it without the autoload.
# No bait = every valid fish equally likely.
static func pick_catch(pool: Array[FishData], bait: BaitData, rng: RandomNumberGenerator = null) -> FishData:
	var candidates: Array[FishData] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for fish in pool:
		# Skip malformed entries; the controller needs at least one escape state
		if fish == null or fish.states.is_empty():
			continue
		var weight: float = bait.get_weight(fish) if bait != null else 1.0
		if is_nan(weight) or weight <= 0.0:
			continue
		candidates.append(fish)
		weights.append(weight)
		total += weight

	if candidates.is_empty():
		return null

	var roll: float = (rng.randf() if rng != null else randf()) * total
	for i in candidates.size():
		roll -= weights[i]
		if roll < 0.0:
			return candidates[i]
	return candidates.back()

# Debug: draw many times and count results per fish_id ("none" for empty draws).
static func simulate_catch_odds(pool: Array[FishData], bait: BaitData, draws: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var counts: Dictionary = {}
	for i in draws:
		var fish: FishData = pick_catch(pool, bait, rng)
		var key: StringName = fish.fish_id if fish != null else &"none"
		counts[key] = counts.get(key, 0) + 1
	return counts

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
