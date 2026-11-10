extends SceneTree

# Debug test for bait-weighted catch odds. Not player-facing. Run from the Godot project folder:
#   godot --headless --path . -s res://tests/bait_odds_test.gd
# Exits with code 1 if any check fails.

const FishingManagerScript = preload("res://scripts/fishing_manager.gd")
const FISH_A: FishData = preload("res://resources/fish/easy_test_fish.tres")
const FISH_B: FishData = preload("res://resources/fish/hard_test_fish.tres")
const SILAS: FishData = preload("res://resources/fish/test_silas.tres")
const BAIT_A: BaitData = preload("res://resources/bait/bait_a.tres")
const BAIT_B: BaitData = preload("res://resources/bait/bait_b.tres")
const YELLOW: BaitData = preload("res://resources/bait/bait_yellow.tres")

const DRAWS: int = 20000
const EXPECTED_BASIC_EASY: float = 10.0 / (10.0 + 0.35)
const EXPECTED_HARD_HARD: float = 6.0 / (1.0 + 6.0)
const EXPECTED_YELLOW_SILAS: float = 5.0 / (1.0 + 0.65 + 5.0)
const TOLERANCE: float = 0.02

var _failures: int = 0

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var pool: Array[FishData] = [FISH_A, FISH_B]

	_check_odds("Easy Fish Bait", pool, BAIT_A, FISH_A, FISH_B, EXPECTED_BASIC_EASY, rng)
	_check_odds("Hard Fish Bait", pool, BAIT_B, FISH_B, FISH_A, EXPECTED_HARD_HARD, rng)

	var silas_pool: Array[FishData] = [FISH_A, FISH_B, SILAS]
	var yellow_odds: Dictionary[FishData, float] = FishingManagerScript.get_catch_odds(silas_pool, YELLOW)
	var basic_odds: Dictionary[FishData, float] = FishingManagerScript.get_catch_odds(silas_pool, BAIT_A)
	var hard_odds: Dictionary[FishData, float] = FishingManagerScript.get_catch_odds(silas_pool, BAIT_B)
	_expect(absf(yellow_odds.get(SILAS, 0.0) - EXPECTED_YELLOW_SILAS) < 0.0001, "yellow bait gives Silas roughly 75 percent chance")
	_expect(yellow_odds.get(SILAS, 0.0) > basic_odds.get(SILAS, 0.0), "yellow bait favors Silas over basic bait")
	_expect(yellow_odds.get(SILAS, 0.0) > hard_odds.get(SILAS, 0.0), "yellow bait favors Silas over hard bait")
	var yellow_counts := FishingManagerScript.simulate_catch_odds(silas_pool, YELLOW, DRAWS, rng)
	_expect(absf(_share(yellow_counts, SILAS.fish_id) - EXPECTED_YELLOW_SILAS) < TOLERANCE, "seeded yellow bait catches Silas at the intended rate")

	# Recruitment removes Silas from the catch pool, so this bait must
	# still work on ordinary fish after his route starts.
	var after_recruitment: Array[FishData] = [FISH_A, FISH_B]
	var ordinary_odds: Dictionary[FishData, float] = FishingManagerScript.get_catch_odds(after_recruitment, YELLOW)
	_expect(ordinary_odds.size() == 2 and not ordinary_odds.has(SILAS), "yellow bait works after Silas leaves the pond")

	var no_bait: Dictionary = FishingManagerScript.simulate_catch_odds(pool, null, DRAWS, rng)
	print("No bait: ", _format(no_bait))
	_expect(absf(_share(no_bait, FISH_A.fish_id) - 0.5) < TOLERANCE, "no bait is roughly 50/50")

	# Odds shown in the bait menu match the weights exactly
	var odds: Dictionary = FishingManagerScript.get_catch_odds(pool, BAIT_A)
	_expect(is_equal_approx(odds.get(FISH_A, 0.0), EXPECTED_BASIC_EASY) and is_equal_approx(odds.get(FISH_B, 0.0), 1.0 - EXPECTED_BASIC_EASY), "get_catch_odds matches bait weights")

	# Empty and malformed pools must return null, not crash
	var empty: Array[FishData] = []
	_expect(FishingManagerScript.pick_catch(empty, BAIT_A, rng) == null, "empty pool returns null")
	var no_states := FishData.new()
	no_states.fish_id = &"no_states"
	var broken: Array[FishData] = [null, no_states]
	_expect(FishingManagerScript.pick_catch(broken, BAIT_A, rng) == null, "pool of null/stateless fish returns null")
	var mixed: Array[FishData] = [null, no_states, FISH_B]
	_expect(FishingManagerScript.pick_catch(mixed, BAIT_A, rng) == FISH_B, "malformed entries are skipped")
	var zero_bait := BaitData.new()
	zero_bait.default_weight = 0.0
	_expect(FishingManagerScript.pick_catch(pool, zero_bait, rng) == null, "all-zero weights return null")

	print("FAILED: %d check(s)" % _failures if _failures > 0 else "All bait odds checks passed")
	quit(1 if _failures > 0 else 0)

func _check_odds(label: String, pool: Array[FishData], bait: BaitData, favored: FishData, other: FishData, expected_share: float, rng: RandomNumberGenerator) -> void:
	var counts: Dictionary = FishingManagerScript.simulate_catch_odds(pool, bait, DRAWS, rng)
	print(label, ": ", _format(counts))
	_expect(absf(_share(counts, favored.fish_id) - expected_share) < TOLERANCE, label + " favors " + favored.fish_id)
	_expect(counts.get(other.fish_id, 0) > 0, label + " can still catch " + other.fish_id)

func _share(counts: Dictionary, fish_id: StringName) -> float:
	return float(counts.get(fish_id, 0)) / DRAWS

func _format(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in counts:
		parts.append("%s %.1f%%" % [key, 100.0 * counts[key] / DRAWS])
	return ", ".join(parts)

func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		_failures += 1
