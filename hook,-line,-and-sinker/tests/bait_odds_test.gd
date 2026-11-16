extends SceneTree

# Bait-weighted species odds and the three bait identities.
# godot --headless --path . -s res://tests/bait_odds_test.gd

const FishingManagerScript = preload("res://scripts/fishing_manager.gd")
const MULLET: FishData = preload("res://resources/fish/mullet.tres")
const PORGY: FishData = preload("res://resources/fish/porgy.tres")
const NEEDLEFISH: FishData = preload("res://resources/fish/needlefish.tres")
const TUNA: FishData = preload("res://resources/fish/tuna.tres")
const GOBY: FishData = preload("res://resources/fish/goby.tres")
const FLOUNDER: FishData = preload("res://resources/fish/flounder.tres")
const SILAS: FishData = preload("res://resources/fish/silas.tres")
const KUDA: FishData = preload("res://resources/fish/kuda.tres")
const BLUE: BaitData = preload("res://resources/bait/bait_a.tres")
const ORANGE: BaitData = preload("res://resources/bait/bait_b.tres")
const YELLOW: BaitData = preload("res://resources/bait/bait_yellow.tres")

const DRAWS := 20000
const TOLERANCE := 0.025
var _failures := 0


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var pool: Array[FishData] = [MULLET, PORGY, NEEDLEFISH, TUNA, GOBY, FLOUNDER]
	var blue_odds := FishingManagerScript.get_catch_odds(pool, BLUE)
	var orange_odds := FishingManagerScript.get_catch_odds(pool, ORANGE)
	var yellow_odds := FishingManagerScript.get_catch_odds(pool, YELLOW)
	_expect(BLUE.display_name == "Blue Bait", "Default bait is Blue Bait")
	_expect(ORANGE.display_name == "Orange Bait", "Aggressive bait is Orange Bait")
	_expect(YELLOW.display_name == "Yellow Bait", "Bottom feeder bait stays Yellow Bait")
	_expect(blue_odds[MULLET] > orange_odds[MULLET] and blue_odds[PORGY] > yellow_odds[PORGY],
		"Blue bait primarily catches calm mullet and porgy")
	_expect(orange_odds[NEEDLEFISH] > blue_odds[NEEDLEFISH] and orange_odds[TUNA] > yellow_odds[TUNA],
		"Orange bait targets needlefish and tuna")
	_expect(yellow_odds[GOBY] > blue_odds[GOBY] and yellow_odds[FLOUNDER] > orange_odds[FLOUNDER],
		"Yellow bait targets goby and flounder")
	_expect(pool.size() == 6 and blue_odds.size() == 6 and orange_odds.size() == 6
		and yellow_odds.size() == 6, "All six regular species are eligible to be hooked")
	_check_pair("Blue / calm fish", BLUE, MULLET, PORGY, 8.0 / 14.0, rng)
	_check_pair("Orange / aggressive fish", ORANGE, NEEDLEFISH, TUNA, 7.0 / 12.0, rng)
	_check_pair("Yellow / bottom fish", YELLOW, GOBY, FLOUNDER, 7.0 / 13.0, rng)
	var npc_pool: Array[FishData] = pool.duplicate()
	npc_pool.append(SILAS)
	npc_pool.append(KUDA)
	var blue_npcs := FishingManagerScript.get_catch_odds(npc_pool, BLUE)
	var orange_npcs := FishingManagerScript.get_catch_odds(npc_pool, ORANGE)
	var yellow_npcs := FishingManagerScript.get_catch_odds(npc_pool, YELLOW)
	_expect(yellow_npcs[SILAS] > blue_npcs[SILAS] and yellow_npcs[SILAS] > orange_npcs[SILAS],
		"Silas prefers yellow bait")
	_expect(orange_npcs[KUDA] > blue_npcs[KUDA] and orange_npcs[KUDA] > yellow_npcs[KUDA],
		"Kuda prefers orange bait")
	var no_bait: Array[FishData] = [MULLET, TUNA]
	var odds := FishingManagerScript.get_catch_odds(no_bait, null)
	_expect(is_equal_approx(odds[MULLET], 0.5), "No bait gives two fish equal odds")
	var empty: Array[FishData] = []
	_expect(FishingManagerScript.pick_catch(empty, BLUE, rng) == null, "Empty pool returns null")
	var no_states := FishData.new()
	no_states.fish_id = &"no_states"
	var malformed: Array[FishData] = [null, no_states, TUNA]
	_expect(FishingManagerScript.pick_catch(malformed, BLUE, rng) == TUNA,
		"Invalid entries are skipped")
	var zero_bait := BaitData.new()
	zero_bait.default_weight = 0.0
	_expect(FishingManagerScript.pick_catch(no_bait, zero_bait, rng) == null,
		"No weights means no fish")
	print("bait_odds_test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_pair(label: String, bait: BaitData, first: FishData, second: FishData,
		expected_share: float, rng: RandomNumberGenerator) -> void:
	var pair: Array[FishData] = [first, second]
	var odds := FishingManagerScript.get_catch_odds(pair, bait)
	_expect(absf(odds[first] - expected_share) < 0.001, label + " weights normalize correctly")
	var counts := FishingManagerScript.simulate_catch_odds(pair, bait, DRAWS, rng)
	var observed := float(counts.get(first.fish_id, 0)) / DRAWS
	_expect(absf(observed - expected_share) < TOLERANCE, label + " seeded draw matches weights")


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		_failures += 1
