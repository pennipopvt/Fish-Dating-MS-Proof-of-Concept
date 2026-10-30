extends SceneTree

# Debug test for bait-weighted catch odds. Not player-facing. Run from the Godot project folder:
#   godot --headless --path . -s res://tests/bait_odds_test.gd
# Exits with code 1 if any check fails.

const FishingManagerScript = preload("res://scripts/fishing_manager.gd")
const FISH_A: FishData = preload("res://resources/fish/placeholder_fish_a.tres")
const FISH_B: FishData = preload("res://resources/fish/placeholder_fish_b.tres")
const BAIT_A: BaitData = preload("res://resources/bait/bait_a.tres")
const BAIT_B: BaitData = preload("res://resources/bait/bait_b.tres")

const DRAWS: int = 20000
const EXPECTED_FAVORED: float = 0.75
const TOLERANCE: float = 0.02

var _failures: int = 0

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var pool: Array[FishData] = [FISH_A, FISH_B]

	_check_odds("Bait A", pool, BAIT_A, FISH_A, FISH_B, rng)
	_check_odds("Bait B", pool, BAIT_B, FISH_B, FISH_A, rng)

	var no_bait: Dictionary = FishingManagerScript.simulate_catch_odds(pool, null, DRAWS, rng)
	print("No bait: ", _format(no_bait))
	_expect(absf(_share(no_bait, FISH_A.fish_id) - 0.5) < TOLERANCE, "no bait is roughly 50/50")

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

func _check_odds(label: String, pool: Array[FishData], bait: BaitData, favored: FishData, other: FishData, rng: RandomNumberGenerator) -> void:
	var counts: Dictionary = FishingManagerScript.simulate_catch_odds(pool, bait, DRAWS, rng)
	print(label, ": ", _format(counts))
	_expect(absf(_share(counts, favored.fish_id) - EXPECTED_FAVORED) < TOLERANCE, label + " favors " + favored.fish_id)
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
