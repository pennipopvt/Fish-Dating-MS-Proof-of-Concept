extends SceneTree

# Regression: Silas's cutout art is used during fishing and other fish
# retain the scene's existing scale.
# godot --headless --path . -s res://tests/silas_fish_sprite_test.gd

const FISHING_SCENE: PackedScene = preload("res://scenes/fishing_controller.tscn")
const SILAS: FishData = preload("res://resources/fish/silas.tres")
const SILAS_NPC: PackedScene = preload("res://prefabs/silas.tscn")
const SILAS_IDLE: Texture2D = preload("res://sprites/characters/silas_idle.png")
const SILAS_CAUGHT: Texture2D = preload("res://sprites/characters/silas_caught.png")
const EASY: FishData = preload("res://resources/fish/easy_test_fish.tres")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var silas_actor := SILAS_NPC.instantiate()
	var silas_sprite := silas_actor.get_node_or_null("Sprite") as AnimatedSprite2D
	_expect(silas_sprite != null, "Silas has an animated world sprite")
	if silas_sprite != null and silas_sprite.sprite_frames != null:
		var idle := silas_sprite.sprite_frames.get_frame_texture(&"default", 0) as AtlasTexture
		_expect(idle != null and idle.atlas == SILAS_IDLE, "Silas idle uses silas_idle.png")
		_expect(silas_sprite.sprite_frames.get_frame_texture(&"on_caught", 0) == SILAS_CAUGHT, "Silas caught pose uses silas_caught.png")
	silas_actor.free()

	var controller := FISHING_SCENE.instantiate()
	get_root().add_child(controller)
	var line: Node2D = controller.get_node("FishingLine")
	var hooked: Sprite2D = line.get_node("Fish")
	var original_scale := hooked.scale
	_expect(SILAS.item_data != null and SILAS.item_data.sprite != null, "Silas has fish art")
	_expect(SILAS.item_data.sprite.resource_path.ends_with("sprites/fish/silas_eel.png"), "Silas points to transparent eel")
	line.call("hook", SILAS)
	_expect(hooked.texture == SILAS.item_data.sprite, "Silas eel appears when hooked")
	_expect(is_equal_approx(hooked.scale.x * hooked.texture.get_width(), SILAS.hooked_sprite_width), "Silas appears at authored width")
	line.call("hook", EASY)
	_expect(hooked.scale.is_equal_approx(original_scale), "Other fish retain original size")
	controller.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Silas fish sprite tests passed")
	quit(1 if failures > 0 else 0)

func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
