extends Node

const VISUAL_PREVIEW: PackedScene = preload("res://scenes/sea_visual_preview.tscn")
const BEAM_SCENE: PackedScene = preload("res://scenes/sea_sunbeam.tscn")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var preview: Node2D = VISUAL_PREVIEW.instantiate() as Node2D
	add_child(preview)
	await get_tree().process_frame
	var beam: SeaSunbeam = preview.get_node("SeaSunbeam") as SeaSunbeam
	var polygon: Polygon2D = beam.get_node("Beam") as Polygon2D
	var material: ShaderMaterial = polygon.material as ShaderMaterial
	var decoration: SeaDecoration = preview.get_node("SeaDecoration") as SeaDecoration
	_check(beam.get_node_or_null("StaticBody2D") == null and beam.z_index == 1,
		"Sunbeams are lightweight non-collidable visual objects")
	_check(polygon.polygon.size() == 4 and material != null,
		"Sunbeam editor geometry and shader material are generated")
	beam.beam_length = 230.0
	beam.beam_width = 110.0
	beam.strength = 0.35
	_check(is_equal_approx(polygon.polygon[2].y, 230.0)
		and is_equal_approx(float(material.get_shader_parameter("beam_width")), 110.0)
		and is_equal_approx(float(material.get_shader_parameter("strength")), 0.35),
		"Sunbeam length, width and brightness are editable per instance")
	var second: SeaSunbeam = BEAM_SCENE.instantiate() as SeaSunbeam
	preview.add_child(second)
	var second_material: ShaderMaterial = (
		second.get_node("Beam") as Polygon2D).material as ShaderMaterial
	_check(second_material != material and second_material != null,
		"Placed sunbeams have independent shader materials")
	beam.set_environment_light(0.0, Color("#ffe5ba"), 140.0)
	_check(is_zero_approx(float(material.get_shader_parameter("daylight_strength")))
		and is_equal_approx(float(material.get_shader_parameter("surface_world_y")), 140.0),
		"Clock-linked sunbeams dim at night and respect the waterline")
	beam.follow_day_night = false
	_check(is_equal_approx(float(material.get_shader_parameter("daylight_strength")), 1.0),
		"Manual beams can opt out of day/night fading")
	beam.follow_day_night = true

	_check(decoration.sprite_frames != null
		and decoration.sprite_frames.has_animation(&"placeholder")
		and decoration.sprite_frames.get_frame_count(&"placeholder") >= 1,
		"Shared animation library plays the artist's decoration frames")
	_check(decoration.get_node_or_null("CollisionShape2D") == null,
		"Decorations never block player, fish or the net")
	var copied_frames: SpriteFrames = decoration.sprite_frames.duplicate() as SpriteFrames
	copied_frames.add_animation(&"kelp_test")
	copied_frames.add_frame(&"kelp_test",
		copied_frames.get_frame_texture(&"placeholder", 0))
	decoration.sprite_frames = copied_frames
	decoration.animation = &"kelp_test"
	await get_tree().process_frame
	_check(decoration.animation == &"kelp_test" and decoration.is_playing(),
		"One decoration instance can select and play any named animation")
	_check(decoration.speed_scale == 1.0 and decoration.texture_filter ==
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"Native speed control and crisp pixel-art filtering are preserved")

	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var water: ColorRect = world.get_node("Water") as ColorRect
	var underwater: ColorRect = world.get_node("Player/Camera2D/UnderwaterTint") as ColorRect
	var tint_color: Color = (underwater.material as ShaderMaterial).get_shader_parameter("tint_color")
	var deep_alpha: float = float((water.material as ShaderMaterial).get_shader_parameter("deep_water_alpha"))
	_check(tint_color.a < 0.35 and deep_alpha <= 0.15,
		"Submerged water uses lighter tint layers without changing the waterline")
	# The same daylight signal updates a beam, without a second clock.
	world.set("_shown_progress", 0.4)
	world.call("_update_sunbeams")
	_check(float(material.get_shader_parameter("daylight_strength")) > 0.95,
		"Existing World day/night controller powers sunbeams in daylight")
	world.set("_shown_progress", 0.85)
	world.call("_update_sunbeams")
	_check(is_zero_approx(float(material.get_shader_parameter("daylight_strength"))),
		"Existing World day/night controller fades sunbeams at night")
	main.queue_free()
	preview.queue_free()
	await get_tree().process_frame
	print("sea_visual_systems_test: PASS" if failures == 0 else
		"sea_visual_systems_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
