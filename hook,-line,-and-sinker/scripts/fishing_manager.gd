
extends Node

signal fish_hooked(item: FishData)
signal fish_caught(item: FishData)
signal fish_lost(item: FishData)
signal bait_changed(bait: BaitData)
signal parry_resolved(result: StringName)
signal upgrades_changed

# Upgrade ownership, unlocks and equipped bait are session-only for now.
const HARD_BAIT_ID: StringName = &"bait_b"
const YELLOW_BAIT_ID: StringName = &"bait_yellow"
const BASIC_BAIT_ID: StringName = &"bait_a"
const STRONGER_REEL_ID: StringName = &"stronger_reel"
const REINFORCED_LINE_ID: StringName = &"reinforced_line"
const HARD_BAIT_UPGRADE_ID: StringName = &"hard_fish_bait"
const YELLOW_BAIT_UPGRADE_ID: StringName = &"yellow_bait"

@export var possible_catches: Array[FishData] = []
@export var current_storage: Array[ItemData] = []

@export var catch_dex: Array[FishData] = []
@export var catch_lifetime: Dictionary[FishData,int]

@export_category("Bait")
@export var available_baits: Array[BaitData] = []
# Applies to the next cast. A fish that's already decided is never swapped.
@export var equipped_bait: BaitData = null
var unlocked_bait_ids: Array[StringName] = [BASIC_BAIT_ID]
var owned_upgrade_ids: Array[StringName] = []
var reel_strength_multiplier: float = 1.0
var tension_gain_multiplier: float = 1.0

@export_category("Fishing Stats")
@export var max_casts_per_session: int = 3

func _ready() -> void:
	# A fresh launch starts with no purchases or bonus bait unlocked.
	# The fishing manager is an autoload and keeps these during this run.
	owned_upgrade_ids.clear()
	unlocked_bait_ids.clear()
	unlocked_bait_ids.append(BASIC_BAIT_ID)
	reel_strength_multiplier = 1.0
	tension_gain_multiplier = 1.0
	equipped_bait = _find_bait(BASIC_BAIT_ID)


func _find_bait(id: StringName) -> BaitData:
	for bait in available_baits:
		if bait != null and bait.bait_id == id:
			return bait
	return null


func get_unlocked_baits() -> Array[BaitData]:
	var unlocked: Array[BaitData] = []
	for bait in available_baits:
		if bait != null and unlocked_bait_ids.has(bait.bait_id):
			unlocked.append(bait)
	return unlocked


func has_upgrade(id: StringName) -> bool:
	return owned_upgrade_ids.has(id)


# Upgrade packages are applied when picked up from the drone's delivery.
# Idempotent so taking a package twice cannot stack the effect.
func shop_reward_unlock_hard_bait(amount: int) -> void:
	if amount <= 0 or has_upgrade(HARD_BAIT_UPGRADE_ID):
		return
	if _find_bait(HARD_BAIT_ID) == null:
		return
	owned_upgrade_ids.append(HARD_BAIT_UPGRADE_ID)
	if not unlocked_bait_ids.has(HARD_BAIT_ID):
		unlocked_bait_ids.append(HARD_BAIT_ID)
	bait_changed.emit(equipped_bait)
	upgrades_changed.emit()


# Unlocks the Silas-favoring bait after its shop delivery is collected.
func shop_reward_unlock_yellow_bait(amount: int) -> void:
	if amount <= 0 or has_upgrade(YELLOW_BAIT_UPGRADE_ID):
		return
	if _find_bait(YELLOW_BAIT_ID) == null:
		return
	owned_upgrade_ids.append(YELLOW_BAIT_UPGRADE_ID)
	if not unlocked_bait_ids.has(YELLOW_BAIT_ID):
		unlocked_bait_ids.append(YELLOW_BAIT_ID)
	bait_changed.emit(equipped_bait)
	upgrades_changed.emit()


func shop_reward_stronger_reel(amount: int) -> void:
	if amount <= 0 or has_upgrade(STRONGER_REEL_ID):
		return
	owned_upgrade_ids.append(STRONGER_REEL_ID)
	reel_strength_multiplier = 1.25
	upgrades_changed.emit()


func shop_reward_reinforced_line(amount: int) -> void:
	if amount <= 0 or has_upgrade(REINFORCED_LINE_ID):
		return
	owned_upgrade_ids.append(REINFORCED_LINE_ID)
	tension_gain_multiplier = 0.8
	upgrades_changed.emit()


func shop_reward_add_casts(amount: int) -> void:
	if amount <= 0:
		return

	max_casts_per_session += amount

func equip_bait(bait: BaitData) -> void:
	if bait == null or not available_baits.has(bait) or not unlocked_bait_ids.has(bait.bait_id):
		return
	if bait == equipped_bait:
		return

	equipped_bait = bait
	bait_changed.emit(bait)

# Remove a recruited NPC from the pool, including duplicate entries or
# multiple FishData resources using the same NPC scene. Ordinary fish and
# NPCs whose recruitment was declined remain available.
func remove_recruited_catch(recruited_fish: FishData) -> void:
	if recruited_fish == null or recruited_fish.npc_data == null:
		return
	for index in range(possible_catches.size() - 1, -1, -1):
		var candidate: FishData = possible_catches[index]
		if candidate != null and candidate.npc_data != null:
			if candidate == recruited_fish or candidate.npc_data == recruited_fish.npc_data:
				possible_catches.remove_at(index)


# Get a random fish from the current pool, weighted by the equipped bait.
# Returns null if the pool has no catchable fish.
func get_random_catch() -> FishData:
	return pick_catch(possible_catches, equipped_bait)

# Chance of each fish in the current pool with this bait (null = no bait).
func get_bait_odds(bait: BaitData) -> Dictionary[FishData, float]:
	return get_catch_odds(possible_catches, bait)

# Single rule for which species a cast hooks. Static so tests can run it without the autoload.
# No bait = every valid fish equally likely.
static func pick_catch(pool: Array[FishData], bait: BaitData, rng: RandomNumberGenerator = null) -> FishData:
	var weights: Dictionary[FishData, float] = _catch_weights(pool, bait)
	if weights.is_empty():
		return null

	var total: float = 0.0
	for weight in weights.values():
		total += weight

	var roll: float = (rng.randf() if rng != null else randf()) * total
	for fish in weights:
		roll -= weights[fish]
		if roll < 0.0:
			return fish
	return weights.keys().back()

# Chance (0-1) of each catchable fish in the pool with this bait, in pool order.
static func get_catch_odds(pool: Array[FishData], bait: BaitData) -> Dictionary[FishData, float]:
	var odds: Dictionary[FishData, float] = _catch_weights(pool, bait)
	var total: float = 0.0
	for weight in odds.values():
		total += weight
	for fish in odds:
		odds[fish] /= total
	return odds

# Positive weight per valid fish. A fish listed twice in the pool counts twice.
static func _catch_weights(pool: Array[FishData], bait: BaitData) -> Dictionary[FishData, float]:
	var weights: Dictionary[FishData, float] = {}
	for fish in pool:
		# Skip malformed entries; the controller needs at least one escape state
		if fish == null or fish.states.is_empty():
			continue
		var weight: float = bait.get_weight(fish) if bait != null else 1.0
		if is_nan(weight) or weight <= 0.0:
			continue
		weights[fish] = weights.get(fish, 0.0) + weight
	return weights

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

# Called for any successful catch, including NPC fish. NPC catches count
# toward challenges/dex, but they do not become an item in storage.
func catch_fish(item: FishData, store_item: bool = true) -> void:
	if item == null:
		return
	if store_item and item.item_data != null:
		current_storage.append(item.item_data)

	if(!catch_dex.has(item)):
		catch_dex.append(item)
	
	if(catch_lifetime.has(item)):
		catch_lifetime[item] += 1
	else:
		catch_lifetime[item] = 1
		
	#print("CATCH DEX", catch_dex)
	#print("LIFETIME CATCHES", catch_lifetime)
	
	# ChallengeManager listens for FishData, not ItemData.
	# Emitting item_data here silently broke typed catch notifications.
	fish_caught.emit(item)

# Call when the player has failed to catch the fish
func lose_fish(item: FishData) -> void:
	fish_lost.emit(item)
