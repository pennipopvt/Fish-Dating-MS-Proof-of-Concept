extends SceneTree

# Regression: a hooked fish is placed out from Penni at the fight's line
# length, so with Penni below it the fish used to rise above the waterline.
# HookedFishMover keeps it in open water: it slides along the waterline and
# rock/ground, left and right stay open, and when pinned in a corner it
# dashes back past Penni.
# godot --headless --path . -s res://tests/diving_hooked_fish_bounds_test.gd
const WATERLINE: float = 166.0
const GROUND: float = 400.0
const WALL_X: float = 500.0  # rock from here to the right
const DT: float = 1.0 / 60.0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _open(p: Vector2) -> bool:
	return p.y >= WATERLINE and p.y <= GROUND and p.x < WALL_X


func _mover() -> HookedFishMover:
	var m := HookedFishMover.new()
	m.is_open = _open
	return m


func _run() -> void:
	# Open water: the fish stays exactly on the line.
	var m := _mover()
	var fish: Vector2 = m.step(DT, Vector2(300, 300), Vector2(350, 300), 80.0)
	_check(fish.is_equal_approx(Vector2(380, 300)), "Fish in open water stays on the line")

	# Penni below the fish, line pulling it up through the surface.
	m = _mover()
	var penni := Vector2(200, 220)
	fish = Vector2(201, 200)
	var always_in_water := true
	for i in 60:
		fish = m.step(DT, penni, fish, 120.0)
		always_in_water = always_in_water and fish.y >= WATERLINE
	_check(always_in_water, "Fish pulled up never leaves the water")
	_check(is_equal_approx(fish.distance_to(penni), 120.0), "Sliding along the surface keeps the line length")

	# Left is open: no border on that side.
	m = _mover()
	fish = m.step(DT, Vector2(40, 300), Vector2(10, 300), 200.0)
	_check(fish.x < -100.0, "Fish can be pulled out past the left edge")

	# Pulled down into the ground: slides along it.
	m = _mover()
	penni = Vector2(200, 350)
	fish = Vector2(200, 390)
	for i in 60:
		fish = m.step(DT, penni, fish, 90.0)
	_check(fish.y <= GROUND and is_equal_approx(fish.distance_to(penni), 90.0),
		"Fish pulled down slides along the ground at the same length")

	# Pinned in the wall/surface corner: dashes back past Penni.
	m = _mover()
	penni = Vector2(470, 190)
	fish = Vector2(490, 170)
	var dashed := false
	var ever_blocked := false
	for i in 90:
		fish = m.step(DT, penni, fish, 60.0)
		dashed = dashed or m.is_dashing()
		ever_blocked = ever_blocked or not _open(fish)
	_check(dashed, "Fish pinned between wall and surface dashes")
	_check(fish.x < penni.x, "After the dash the fish is on the far side of Penni")
	_check(not ever_blocked, "Fish never sits inside rock or above the water")

	print("diving_hooked_fish_bounds_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   " + label)
	else:
		failures += 1
		print("  FAIL " + label)
