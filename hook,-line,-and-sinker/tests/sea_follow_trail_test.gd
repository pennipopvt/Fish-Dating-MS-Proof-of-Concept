extends Node

# Verify delayed party positions follow the curved swim path, not a static
# side offset that flips when Penni turns around.
var failures: int = 0


func _ready() -> void:
	var trail := SeaFollowTrail.new()
	trail.reset(Vector2.ZERO)
	for x in [6, 12, 18, 24, 30]:
		trail.record(Vector2(x, 0))
	for y in [8, 16, 24, 32, 40]:
		trail.record(Vector2(30, y))
	_check(trail.point_behind(20.0).distance_to(Vector2(30, 20)) < 0.01,
		"A close follower remains around the corner on the vertical trail")
	_check(trail.point_behind(55.0).distance_to(Vector2(15, 0)) < 0.01,
		"A distant follower is still approaching the same corner horizontally")
	_check(trail.point_behind(100.0).distance_to(Vector2(-30, 0)) < 0.01,
		"An initial short trail extends behind the original starting point")
	trail.record(Vector2(500, 500))
	_check(trail.point_behind(0.0) == Vector2(500, 500),
		"Teleporting resets the trail instead of dragging companions across the map")
	trail.reset(Vector2(25, 60))
	_check(trail.point_behind(20.0, Vector2.LEFT) == Vector2(45, 60),
		"New dives start with a valid fallback behind Penni's facing")
	print("sea_follow_trail_test: PASS" if failures == 0 else
		"sea_follow_trail_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
