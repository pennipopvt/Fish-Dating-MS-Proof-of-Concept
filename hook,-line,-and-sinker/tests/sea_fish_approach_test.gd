extends SceneTree

# Focused test for editor-tuned fish standoff without touching reel combat.
# godot --headless --path . -s res://tests/sea_fish_approach_test.gd
const FISH: Texture2D = preload("res://sprites/fish/mullet.png")
const SEA: PackedScene = preload("res://scenes/sea_area.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fish: DivingWildFish = DivingWildFish.new()
	get_root().add_child(fish)
	fish.setup(&"mullet", FISH, Vector2(-360.0, 245.0),
		Rect2(-800.0, 150.0, 1000.0, 450.0), 3102)
	fish.preferred_player_distance = 52.0
	fish.flee_radius = 76.0
	fish.flee_speed = 112.0
	var player_position: Vector2 = fish.position + Vector2(-30.0, 0.0)
	var initial_distance: float = fish.position.distance_to(player_position)
	fish.swim(0.25, player_position, false)
	var after_flee: float = fish.position.distance_to(player_position)
	_check(after_flee > initial_distance + 19.5,
		"Close wary fish can retreat faster than Penni's 78px/s swim")

	fish.trapped = true
	var held_position: Vector2 = fish.position
	fish.swim(0.5, player_position, false)
	_check(fish.position == held_position,
		"Fish already hooked or trapped do not swim away")
	fish.trapped = false

	# Zero preferred distance restores the original, slower retreat.
	fish.preferred_player_distance = 0.0
	fish.position = Vector2(-360.0, 245.0)
	fish.swim(0.25, player_position, false)
	_check(fish.position.distance_to(player_position) - initial_distance < 19.5,
		"Fish with no preferred spacing can be approached more closely")

	var sea: Node2D = SEA.instantiate() as Node2D
	get_root().add_child(sea)
	var tutorial: DivingFishSpawn = sea.get_node("FishSpawns/FirstFish") as DivingFishSpawn
	var ordinary: DivingFishSpawn = sea.get_node("FishSpawns/MulletAfterSilas") as DivingFishSpawn
	_check(is_zero_approx(tutorial.preferred_player_distance)
		and tutorial.is_first_dive_fish and not ordinary.is_first_dive_fish,
		"First dive fish is assigned by Inspector role, not spawn node name")
	_check(is_equal_approx(ordinary.preferred_player_distance, 52.0)
		and is_equal_approx(ordinary.alert_distance, 76.0)
		and is_equal_approx(ordinary.flee_speed, 112.0),
		"Ordinary fish loads all three Inspector tuning values")
	
	sea.queue_free()
	fish.queue_free()
	await process_frame
	print("FAILED: %d" % failures if failures > 0 else "Sea approach tuning tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
