
extends Node

signal fish_hooked(item: FishData)
signal fish_caught(item: FishData)
signal fish_lost(item: FishData)
signal bait_changed(bait: BaitData)
signal parry_resolved(result: StringName)
signal upgrades_changed
# Any add/remove in current_storage (catches, trades, deliveries).
signal storage_changed
signal team_changed

# Upgrade ownership, unlocks and equipped bait are session-only for now.
const HARD_BAIT_ID: StringName = &"bait_b"
const YELLOW_BAIT_ID: StringName = &"bait_yellow"
const BASIC_BAIT_ID: StringName = &"bait_a"
const STRONGER_REEL_ID: StringName = &"stronger_reel"
const REINFORCED_LINE_ID: StringName = &"reinforced_line"
const HARD_BAIT_UPGRADE_ID: StringName = &"hard_fish_bait"
const YELLOW_BAIT_UPGRADE_ID: StringName = &"yellow_bait"
const EXTRA_CAST_UPGRADE_ID: StringName = &"increase_casts"

# Revised fishing: recruited NPC fish are the party, not bait/bobber equipment.
# The first party member is always the active lure; everyone else is reserve.
const SILAS_FISH_ID: StringName = &"test_silas"
const SILAS_NPC_ID: StringName = &"test_npc"
const FIRST_SILAS_CAST: int = 6
const SILAS_LURE_WEIGHTS := {
	&"barracuda": 3.5, &"mullet": 0.6, &"porgy": 0.5,
	&"needlefish": 7.0, &"tuna": 5.0, &"goby": 0.1,
	&"flounder": 0.3, &"test_silas": 0.2
}
var total_casts: int = 0
var party: Array[FishData] = []
var lure_fish_id: StringName = &""

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
# Flat equipment bonuses that apply after fish-specific combat calculations.
var reel_progress_bonus: float = 0.0
var reel_tension_reduction: float = 0.0
var miss_tension_reduction: float = 0.0

@export_category("Fishing Stats")
# A fishing session is exactly one action, with this many consecutive casts.
# Starts at one; the Increase Casts upgrade can add more to that action.
@export_range(1, 20, 1) var casts_per_action: int = 1
var _starting_casts_per_action: int = 1

func _ready() -> void:
	_starting_casts_per_action = maxi(casts_per_action, 1)
	reset_session_upgrades()

# One canonical reset for session-only equipment/bait. Dev tools call this
# instead of duplicating upgrade field names and accidentally leaving bonuses.
func reset_session_upgrades() -> void:
	owned_upgrade_ids.clear()
	unlocked_bait_ids.clear()
	unlocked_bait_ids.append(BASIC_BAIT_ID)
	reel_progress_bonus = 0.0
	reel_tension_reduction = 0.0
	miss_tension_reduction = 0.0
	casts_per_action = _starting_casts_per_action
	equipped_bait = _find_bait(BASIC_BAIT_ID)
	bait_changed.emit(equipped_bait)
	upgrades_changed.emit()


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
	reel_progress_bonus = 0.01  # +1 percentage point per reel scroll
	upgrades_changed.emit()


func shop_reward_reinforced_line(amount: int) -> void:
	if amount <= 0 or has_upgrade(REINFORCED_LINE_ID):
		return
	owned_upgrade_ids.append(REINFORCED_LINE_ID)
	reel_tension_reduction = 0.005  # -0.5 percentage points per reel scroll
	miss_tension_reduction = 0.04  # -4 percentage points per missed dash
	upgrades_changed.emit()


func shop_reward_upgrade_casts(amount: int) -> void:
	if amount <= 0 or has_upgrade(EXTRA_CAST_UPGRADE_ID):
		return
	owned_upgrade_ids.append(EXTRA_CAST_UPGRADE_ID)
	shop_reward_add_casts(amount)


func shop_reward_add_casts(amount: int) -> void:
	if amount <= 0:
		return

	casts_per_action += amount
	upgrades_changed.emit()

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
	# Silas cannot appear accidentally before the introductory sixth cast.
	# If that encounter is lost, the next cast tries again until he's caught.
	var eligible: Array[FishData] = []
	var silas: FishData = null
	for fish in possible_catches:
		if fish == null:
			continue
		if fish.fish_id == SILAS_FISH_ID:
			silas = fish
			continue
		# Keep the introductory mystery focused on Silas: other NPCs only
		# enter the pool after the first Silas catch.
		if fish.npc_data != null and not _silas_already_caught():
			continue
		eligible.append(fish)
	if silas != null and not _silas_already_caught():
		if total_casts >= FIRST_SILAS_CAST:
			return silas
	else:
		if silas != null:
			eligible.append(silas)
	return _pick_lure_catch(eligible)


func _silas_already_caught() -> bool:
	if has_companion(SILAS_FISH_ID):
		return true
	for fish in catch_dex:
		if fish != null and fish.fish_id == SILAS_FISH_ID:
			return true
	return false


func _pick_lure_catch(pool: Array[FishData]) -> FishData:
	var lure: FishData = get_lure_companion()
	# In the solo tutorial there is no bait: all other species are equally likely.
	if lure == null or lure.fish_id != SILAS_FISH_ID:
		return pick_catch(pool, null)
	var total := 0.0
	var weights: Dictionary[FishData, float] = {}
	for fish in pool:
		if fish == null or fish.states.is_empty():
			continue
		var weight: float = float(SILAS_LURE_WEIGHTS.get(fish.fish_id, 1.0))
		if weight > 0.0:
			weights[fish] = weights.get(fish, 0.0) + weight
			total += weight
	if total <= 0.0:
		return null
	var roll: float = randf() * total
	for fish in weights:
		roll -= weights[fish]
		if roll <= 0.0:
			return fish
	return weights.keys().back()


func register_recruited_companion(fish: FishData) -> void:
	if fish == null or fish.npc_data == null:
		return
	for member in party:
		if member.fish_id == fish.fish_id:
			return
	party.append(fish)
	if lure_fish_id == &"":
		lure_fish_id = fish.fish_id
	team_changed.emit()


func get_lure_companion() -> FishData:
	for member in party:
		if member != null and member.fish_id == lure_fish_id:
			return member
	return null


func has_companion(id: StringName) -> bool:
	for member in party:
		if member != null and member.fish_id == id:
			return true
	return false


func has_spyglass() -> bool:
	return has_companion(SILAS_FISH_ID)


func set_lure_companion(id: StringName) -> bool:
	for member in party:
		if member != null and member.fish_id == id:
			if lure_fish_id == id:
				return true
			lure_fish_id = id
			party.erase(member)
			party.push_front(member)
			team_changed.emit()
			return true
	return false


func reset_team_for_debug() -> void:
	party.clear()
	lure_fish_id = &""
	total_casts = 0
	team_changed.emit()

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

# ---- Storage -------------------------------------------------------------
# Change current_storage through these so storage_changed fires.

func add_to_storage(item: ItemData, amount: int = 1) -> void:
	if item == null or amount <= 0:
		return
	for i in amount:
		current_storage.append(item)
	storage_changed.emit()


# How many of an item the player has in storage.
func count_in_storage(item_id: StringName) -> int:
	var count := 0
	for item in current_storage:
		if item != null and item.item_id == item_id:
			count += 1
	return count


# Removes amount items with this id. Removes nothing and returns false if
# there aren't enough.
func remove_from_storage(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0 or count_in_storage(item_id) < amount:
		return false
	# Oldest first.
	var left := amount
	var i := 0
	while left > 0 and i < current_storage.size():
		var item: ItemData = current_storage[i]
		if item != null and item.item_id == item_id:
			current_storage.remove_at(i)
			left -= 1
		else:
			i += 1
	storage_changed.emit()
	return true


# Call when a fish has been hooked and the player must start reeling
func hook_fish(item: FishData) -> void:
	fish_hooked.emit(item)

# Called for any successful catch, including NPC fish. NPC catches count
# toward challenges/dex, but they do not become an item in storage.
func catch_fish(item: FishData, store_item: bool = true) -> void:
	if item == null:
		return
	if store_item and item.item_data != null:
		add_to_storage(item.item_data)

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
