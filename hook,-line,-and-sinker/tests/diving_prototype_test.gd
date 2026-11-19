extends SceneTree

# The old prototype is only a preview of the real Sea, not another level.
const PREVIEW: PackedScene = preload("res://scenes/diving_prototype.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var root: Node = PREVIEW.instantiate()
	get_root().add_child(root)
	await process_frame
	var sea: DivingWorld = root.get_node("Sea") as DivingWorld
	var ok: bool = sea != null and sea.scene_file_path == "res://scenes/sea_area.tscn"
	ok = ok and not sea.has_node("Player")
	ok = ok and sea.get_node("Solids") is TileMapLayer
	ok = ok and sea.get_node("StoryDirector") is SeaStoryDirector
	root.queue_free()
	print("Sea preview passed" if ok else "Sea preview failed")
	quit(0 if ok else 1)
