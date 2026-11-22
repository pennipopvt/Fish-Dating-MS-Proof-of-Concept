extends Node

# Editor motion paths have editable geometry, independent per-animation
# velocity graphs and exact starts/ends even for moving fish.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	_watchdog()
	_run.call_deferred()


func _watchdog() -> void:
	await get_tree().create_timer(15.0).timeout
	push_error("Editable sea motion test timed out")
	get_tree().quit(1)


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var motion_root: Node2D = sea.get_node("Points") as Node2D
	for name in ["PenniDiveJump", "PenniDiveDescent", "CompanionDiveJump",
			"CompanionDiveDescent", "PenniSurface", "CompanionSurface"]:
		var motion: SeaMotionPath = motion_root.get_node_or_null(name) as SeaMotionPath
		if motion == null:
			_check(false, name + " is missing from the sea scene")
			continue
		var child_path: Path2D = motion.get_node_or_null("Path") as Path2D
		_check(motion != null and motion.is_valid_motion()
			and motion.duration_seconds >= 0.1
			and motion.speed_curve != null
			and motion.speed_curve.get_point_count() >= 2
			and child_path != null and child_path.curve.get_point_count() >= 2,
			name + " has separate editor-editable path, duration and velocity curve")
	var motion: SeaMotionPath = motion_root.get_node("PenniDiveJump") as SeaMotionPath
	var shape: Path2D = motion.get_node("Path") as Path2D
	var curve: Curve2D = shape.curve
	var original_mid: Vector2 = curve.get_point_position(1)
	var before: Vector2 = motion.world_position_at(0.5)
	curve.set_point_position(1, original_mid + Vector2(0, -50))
	_check(motion.world_position_at(0.5).distance_to(before) > 4.0,
		"Dragging a Path2D control point changes the ACTUAL flight")
	curve.set_point_position(1, original_mid)

	var pace := Curve.new()
	pace.add_point(Vector2(0.0, 1.0))
	pace.add_point(Vector2(1.0, 0.0))
	motion.speed_curve = pace
	_check(motion.progress_at_time(0.0) == 0.0
		and motion.progress_at_time(1.0) == 1.0
		and motion.progress_at_time(0.5) > 0.55,
		"Speed Curve controls true velocity, not just a fixed Tween ease")

	var from := Vector2(137.0, 112.0)
	var to := Vector2(7.0, 161.0)
	_check(motion.world_position_at(0.0, from, to).distance_to(from) < 0.001
		and motion.world_position_at(1.0, from, to).distance_to(to) < 0.001,
		"Dynamic actor endpoints do not teleport at start or destination")
	var actor := Node2D.new()
	world.add_child(actor)
	await motion.animate(actor, from, to)
	_check(actor.global_position.distance_to(to) < 0.001,
		"Shared animation finishes at precisely the requested endpoint")
	actor.queue_free()

	var descent: SeaMotionPath = motion_root.get_node("PenniDiveDescent") as SeaMotionPath
	_check(descent.authored_end().y >= DivingWorld.SEA_TOP + 80.0
		and sea.call("_is_open_water", sea.to_local(descent.authored_end())),
		"Artist-authored underwater destination is safely deep and in open water")
	main.queue_free()
	await get_tree().process_frame
	print("sea_motion_path_test: PASS" if failures == 0 else
		"sea_motion_path_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
