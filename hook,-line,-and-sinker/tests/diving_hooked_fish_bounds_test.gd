extends SceneTree

# Regression: a hooked fish is placed straight out from Penni at the fight's
# line length, so with Penni below it the fish used to rise above the
# waterline. It must stay in the sea and slide along the edge instead.
# DivingWorld uses autoloads, so run this with the temp-scene runner
# (see AGENTS.md), not with -s.
const BOUNDS := Rect2(Vector2(28.0, 166.0), Vector2(800.0, 400.0))  # top = waterline + margin
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Inside the sea: unchanged.
	var inside: Vector2 = DivingWorld.place_on_line_inside(
		Vector2(400.0, 400.0), Vector2.RIGHT, 100.0, BOUNDS)
	_check(inside.is_equal_approx(Vector2(500.0, 400.0)), "Fish in open water stays on the line")

	# Penni directly below the fish, line long enough to reach past the surface.
	var origin := Vector2(400.0, 220.0)
	var up: Vector2 = DivingWorld.place_on_line_inside(origin, Vector2.UP, 150.0, BOUNDS)
	_check(up.y >= BOUNDS.position.y - 0.01, "Fish pulled straight up stays below the waterline")
	_check(is_equal_approx(up.distance_to(origin), 150.0), "Sliding along the surface keeps the line length")

	# Pulling up and to the left slides left along the surface, not right.
	var up_left: Vector2 = DivingWorld.place_on_line_inside(
		origin, Vector2(-0.3, -1.0).normalized(), 150.0, BOUNDS)
	_check(is_equal_approx(up_left.y, BOUNDS.position.y) and up_left.x < origin.x,
		"Fish pulling up-left slides left along the surface")
	_check(is_equal_approx(up_left.distance_to(origin), 150.0), "Up-left slide keeps the line length")

	# Side wall: slides down the wall at the same length.
	var near_wall := Vector2(BOUNDS.end.x - 40.0, 300.0)
	var wall: Vector2 = DivingWorld.place_on_line_inside(near_wall, Vector2.RIGHT, 100.0, BOUNDS)
	_check(BOUNDS.grow(0.01).has_point(wall), "Fish pulled into a wall stays inside the sea")
	_check(is_equal_approx(wall.distance_to(near_wall), 100.0), "Wall slide keeps the line length")

	# Corner: no point at that length fits, so it stays inside, just closer.
	var corner_origin := Vector2(BOUNDS.end.x - 20.0, BOUNDS.position.y + 20.0)
	var corner: Vector2 = DivingWorld.place_on_line_inside(
		corner_origin, Vector2(1.0, -1.0).normalized(), 175.0, BOUNDS)
	_check(BOUNDS.grow(0.01).has_point(corner), "Fish in a corner stays inside the sea")

	print("diving_hooked_fish_bounds_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   " + label)
	else:
		failures += 1
		print("  FAIL " + label)
