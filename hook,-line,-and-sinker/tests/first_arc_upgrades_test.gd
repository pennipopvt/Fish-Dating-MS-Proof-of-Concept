extends SceneTree

# Covers first-arc upgrades and their session-only progress.
# Run from Godot project folder:
# godot --headless --path . -s res://tests/first_arc_upgrades_test.gd

const FISHING_SCRIPT = preload("res://scripts/fishing_manager.gd")
const CHALLENGE_MANAGER_SCRIPT = preload("res://scripts/challenge_manager.gd")
const BASIC: BaitData = preload("res://resources/bait/bait_a.tres")
const HARD: BaitData = preload("res://resources/bait/bait_b.tres")
const YELLOW: BaitData = preload("res://resources/bait/bait_yellow.tres")
const EASY_FISH: FishData = preload("res://resources/fish/easy_test_fish.tres")
const HARD_FISH: FishData = preload("res://resources/fish/hard_test_fish.tres")
const BAIT_TRADE: TradeData = preload("res://resources/trades/hard_fish_bait.tres")
const YELLOW_TRADE: TradeData = preload("res://resources/trades/yellow_bait.tres")
const REEL_TRADE: TradeData = preload("res://resources/trades/stronger_reel.tres")
const LINE_TRADE: TradeData = preload("res://resources/trades/reinforced_line.tres")
const PARRY_CHALLENGE: ChallengeData = preload("res://resources/challenges/perfect_parry_streak.tres")
const CATCH_CHALLENGE: ChallengeData = preload("res://resources/challenges/hot_streak.tres")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fish: Variant = FISHING_SCRIPT.new()
	var baits: Array[BaitData] = [BASIC, HARD, YELLOW]
	fish.available_baits = baits
	fish.equipped_bait = BASIC
	_expect(fish.get_unlocked_baits().size() == 1, "only easy fish bait is available initially")
	fish.equip_bait(HARD)
	_expect(fish.equipped_bait == BASIC, "hard bait cannot be equipped before purchase")
	fish.equip_bait(YELLOW)
	_expect(fish.equipped_bait == BASIC, "yellow bait cannot be equipped before purchase")
	_expect(not fish.get_unlocked_baits().has(YELLOW), "yellow bait is absent from the starting bait menu")
	_expect(BAIT_TRADE.icon == HARD.icon and BAIT_TRADE.delivery_sprite == HARD.icon, "new hard bait icon used in shop and delivery")
	_expect(YELLOW.icon != null and YELLOW_TRADE.icon == YELLOW.icon, "yellow icon appears in both bait menu and shop")
	_expect(YELLOW_TRADE.delivery_sprite == YELLOW.icon, "yellow icon appears on delivery")
	_expect(REEL_TRADE.icon != null and REEL_TRADE.delivery_sprite == REEL_TRADE.icon, "new reel strength icon used in shop and delivery")
	_expect(LINE_TRADE.icon != null and LINE_TRADE.delivery_sprite == LINE_TRADE.icon, "new tension icon used in shop and delivery")

	var two_fish_pool: Array[FishData] = [EASY_FISH, HARD_FISH]
	var basic_odds: Dictionary[FishData, float] = FISHING_SCRIPT.get_catch_odds(two_fish_pool, BASIC)
	var hard_odds: Dictionary[FishData, float] = FISHING_SCRIPT.get_catch_odds(two_fish_pool, HARD)
	_expect(hard_odds.get(HARD_FISH, 0.0) > basic_odds.get(HARD_FISH, 0.0), "hard bait significantly raises hard-fish odds")

	_expect(BAIT_TRADE.one_time_purchase and BAIT_TRADE.requirements[0].amount == 2, "hard bait costs two easy fish")
	_expect(YELLOW_TRADE.one_time_purchase and YELLOW_TRADE.requirements[0].amount == 2 and YELLOW_TRADE.requirements[0].item.item_id == EASY_FISH.item_data.item_id, "yellow bait costs two easy fish only once")
	_expect(fish.has_method(YELLOW_TRADE.reward_method), "yellow bait delivery calls a valid reward method")
	_expect(REEL_TRADE.one_time_purchase and REEL_TRADE.requirements[0].amount == 1, "stronger reel costs one easy fish")
	_expect(LINE_TRADE.one_time_purchase and LINE_TRADE.requirements[0].item.item_id == HARD_FISH.item_data.item_id, "reinforced line costs one hard fish")
	_expect(PARRY_CHALLENGE.unlocks_trade(REEL_TRADE), "perfect parry challenge unlocks stronger reel")
	_expect(CATCH_CHALLENGE.unlocks_trade(LINE_TRADE), "three-catch challenge unlocks reinforced line")

	var streak := ChallengeData.new()
	streak.requirement_type = ChallengeData.RequirementType.CONSECUTIVE_PERFECT_PARRIES
	streak.target_amount = 3
	streak.record_parry(&"perfect")
	streak.record_parry(&"perfect")
	_expect(streak.progress == 2, "two perfect parries build a streak")
	streak.record_catch(EASY_FISH)
	_expect(streak.progress == 2, "catching a fish does not reset the perfect-parry streak")
	streak.record_parry(&"close")
	_expect(streak.progress == 0, "close parry resets the streak")
	streak.record_parry(&"perfect")
	streak.record_parry(&"miss")
	_expect(streak.progress == 0, "miss resets the streak")
	streak.record_parry(&"perfect")
	streak.record_parry(&"perfect")
	_expect(streak.record_parry(&"perfect"), "third perfect parry completes the challenge")

	# Delivered upgrades apply within this session; no disk save occurs.
	fish.shop_reward_unlock_yellow_bait(1)
	_expect(fish.get_unlocked_baits().has(YELLOW), "yellow bait unlocks after collecting delivery")
	fish.equip_bait(YELLOW)
	_expect(fish.equipped_bait == YELLOW, "yellow bait equips at the tackle box")
	fish.shop_reward_unlock_yellow_bait(1)
	_expect(fish.owned_upgrade_ids.count(&"yellow_bait") == 1, "yellow bait cannot be unlocked twice")
	fish.shop_reward_unlock_hard_bait(1)
	_expect(fish.get_unlocked_baits().has(HARD), "hard bait unlocks when the upgrade is collected")
	fish.equip_bait(HARD)
	_expect(fish.equipped_bait == HARD, "hard bait is equippable after delivery")
	fish.shop_reward_stronger_reel(1)
	fish.shop_reward_reinforced_line(1)
	_expect(is_equal_approx(fish.reel_progress_bonus, 0.01), "reel adds 1 percentage point per scroll")
	_expect(is_equal_approx(fish.reel_tension_reduction, 0.005), "line subtracts 0.5 percentage points per scroll")
	_expect(is_equal_approx(fish.miss_tension_reduction, 0.04), "line subtracts 4 percentage points per missed dash")
	fish.shop_reward_stronger_reel(1)
	fish.shop_reward_reinforced_line(1)
	_expect(is_equal_approx(fish.reel_progress_bonus, 0.01) and is_equal_approx(fish.reel_tension_reduction, 0.005) and is_equal_approx(fish.miss_tension_reduction, 0.04), "upgrade methods cannot stack rewards")

	# A fresh manager represents a new game launch. All upgrades and bait
	# choices must reset, even if the previous session owned everything.
	var fresh: Variant = FISHING_SCRIPT.new()
	fresh.available_baits = baits
	fresh.equipped_bait = HARD
	fresh._ready()
	_expect(fresh.get_unlocked_baits().size() == 1, "new session has only basic bait")
	_expect(fresh.equipped_bait == BASIC, "new session equips basic bait")
	_expect(not fresh.has_upgrade(&"hard_fish_bait"), "hard bait must be re-earned on relaunch")
	_expect(not fresh.has_upgrade(&"yellow_bait"), "yellow bait must be re-earned on relaunch")
	_expect(not fresh.get_unlocked_baits().has(YELLOW), "yellow bait is hidden again after relaunch")
	_expect(not fresh.has_upgrade(&"stronger_reel"), "stronger reel must be re-earned on relaunch")
	_expect(not fresh.has_upgrade(&"reinforced_line"), "reinforced line must be re-earned on relaunch")
	_expect(is_zero_approx(fresh.reel_progress_bonus), "reel bonus resets to zero")
	_expect(is_zero_approx(fresh.reel_tension_reduction), "reel tension reduction resets to zero")
	_expect(is_zero_approx(fresh.miss_tension_reduction), "miss tension reduction resets to zero")
	fish.free()
	fresh.free()

	# A new ChallengeManager also clears any old progress in its resources.
	# This checks session startup without creating or reading a save file.
	var old_progress := ChallengeData.new()
	old_progress.challenge_id = &"test_session_reset"
	old_progress.target_amount = 3
	old_progress.progress = 3
	old_progress.completed = true
	old_progress.completed_at = 123456
	var session_challenges: Array[ChallengeData] = [old_progress]
	var achievement_manager: Variant = CHALLENGE_MANAGER_SCRIPT.new()
	achievement_manager.challenges = session_challenges
	achievement_manager._ready()
	_expect(old_progress.progress == 0, "achievements start at zero in new sessions")
	_expect(not old_progress.completed, "previous completion does not carry into new sessions")
	_expect(old_progress.completed_at == 0, "previous completion time is cleared")
	achievement_manager._on_fish_caught(EASY_FISH)
	_expect(old_progress.progress == 1, "achievement tracking still works during the session")
	achievement_manager.free()

	print("FAILED: %d" % failures if failures > 0 else "All first-arc upgrade checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
