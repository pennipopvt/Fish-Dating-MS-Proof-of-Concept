extends SceneTree

# Rendering architecture regression without changing or repacking world art.
# Run from the Godot project root:
# godot --headless --path . -s res://tests/sea_water_reflection_test.gd
const WORLD: PackedScene = preload("res://prefabs/world.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node2D = WORLD.instantiate()
	var water: ColorRect = world.get_node("Water") as ColorRect
	var sea: Node2D = world.get_node("Sea") as Node2D
	var solids: TileMapLayer = sea.get_node("Solids") as TileMapLayer
	var penni: Player = world.get_node("Player") as Player
	var sprite: AnimatedSprite2D = penni.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var underwater_tint: ColorRect = penni.get_node("Camera2D/UnderwaterTint") as ColorRect
	var water_mat: ShaderMaterial = water.material as ShaderMaterial
	var solids_mat: ShaderMaterial = solids.material as ShaderMaterial
	_check(water.z_index > solids.z_index
		and water.z_index > sprite.z_index
		and water.z_index > 6
		and water.z_index < underwater_tint.z_index,
		"Water screen-texture pass is above terrain and all world actors but below the camera tint")
	_check(water_mat != null and water_mat.shader != null
		and water_mat.shader.code.contains("viewer_submersion")
		and water_mat.shader.code.contains("mix(1.0, deep_water_alpha, viewer_submersion)"),
		"Shore water is opaque regardless of pixel depth; diver submersion reveals the sea")
	_check(solids_mat != null and solids_mat.shader != null
		and solids_mat.shader.code.contains("MODEL_MATRIX")
		and solids_mat.shader.code.contains("discard")
		and solids.collision_enabled,
		"Seabed tiles are clipped visually at the shared waterline without removing physics")
	_check(world.get_node("Sky") is Control
		and absf(water.position.y - 140.0) < 0.01,
		"Sky and sea still share the original world-space water surface")
	world.free()
	print("FAILED: %d" % failures if failures > 0 else "Sea surface rendering architecture passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
