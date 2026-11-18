extends SceneTree

# Old prototype is now just the editable sea preview.
const PREVIEW: PackedScene = preload("res://scenes/diving_prototype.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var root: Node = PREVIEW.instantiate()
	get_root().add_child(root)
	await process_frame
	var sea: DivingWorld = root.get_node("Sea") as DivingWorld
	var ok: bool = sea != null and sea.scene_file_path == "res://scenes/sea_area.tscn"
	ok = ok and not sea.has_node("Player") and not sea.has_node("Combat")
	ok = ok and sea.get_node("Solids") is TileMapLayer
	root.queue_free()
	print("Blank sea preview passed" if ok else "Blank sea preview failed")
	quit(0 if ok else 1)
