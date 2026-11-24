extends Node

# Run: godot --headless --path . res://tests/viewport_layout_test.tscn
# The actual World is rendered in a dynamically sized game SubViewport.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var container: SubViewportContainer = main.get_node("SubViewportContainer") as SubViewportContainer
	var game_view: SubViewport = container.get_node("SubViewport") as SubViewport
	var world: Node2D = game_view.get_node("World") as Node2D
	var sky: Control = world.get_node("SkyLayer/Sky") as Control
	var gradient: ColorRect = sky.get_node("SkyGradient") as ColorRect
	var stars: ColorRect = sky.get_node("NightStars") as ColorRect
	var clouds: Node2D = sky.get_node("Clouds") as Node2D
	var background: ColorRect = world.get_node("UnderwaterBackgroundLayer/UnderwaterBackground") as ColorRect
	var tint: ColorRect = world.get_node("CameraController/Camera2D/UnderwaterTint") as ColorRect
	var sun: Sprite2D = sky.get_node("Sun") as Sprite2D
	var moon: ColorRect = sky.get_node("Moon") as ColorRect
	var water: ColorRect = world.get_node("Water") as ColorRect

	# Stop the container from overriding our explicit test dimensions.
	container.stretch = false
	for target: Vector2i in [
		Vector2i(320, 180), Vector2i(480, 270),
		Vector2i(480, 180), Vector2i(240, 240), Vector2i(320, 180)
	]:
		game_view.size = target
		await get_tree().process_frame
		await get_tree().process_frame
		world.call("_process", 0.0)
		var dimensions := Vector2(target)
		var surface_screen_y: float = water.get_global_transform_with_canvas().origin.y
		var expected_clip: float = clampf(ceilf(surface_screen_y), 0.0, dimensions.y)
		_check(is_equal_approx(sky.size.x, dimensions.x)
			and is_equal_approx(sky.size.y, expected_clip),
			"Sky reaches both horizontal edges and clips at the real waterline: %s" % target)
		_check(gradient.size == dimensions and stars.size == dimensions
			and background.size == dimensions and tint.size == dimensions,
			"Gradient, stars, opaque sea and tint fill the complete game viewport: %s" % target)
		_check(is_equal_approx(float(clouds.get("spawn_width")), dimensions.x),
			"Clouds cover the resized game viewport: %s" % target)
		var tint_mat: ShaderMaterial = tint.material as ShaderMaterial
		_check(is_equal_approx(float(tint_mat.get_shader_parameter("surface_y_uv")),
			surface_screen_y / dimensions.y),
			"Underwater haze clips at the right normalized waterline: %s" % target)
		world.call("_show_discs_at", 0.40, true)
		var right_extent: float = dimensions.x - 28.0
		_check(sun.position.x >= 28.0 and sun.position.x <= right_extent
			and moon.position.x >= 0.0 and moon.position.x <= dimensions.x,
			"Sun and moon positions fit the resized sky: %s" % target)

	main.queue_free()
	await get_tree().process_frame
	print("viewport_layout_test: PASS" if failures == 0 else
		"viewport_layout_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
