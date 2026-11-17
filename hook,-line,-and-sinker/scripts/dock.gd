extends Interactable

#hello!
func spends_time() -> bool:
	return true

func interact(_player: Node2D) -> void:
	var fisher := _player as Player
	
	if(fisher == null):
		return
	
	# In the diving experiment, using the fishing dock is how you enter the
	# ocean. The normal fishing rod scene remains available for comparison.
	if fisher.busy:
		return
	var main_scene: Node = get_tree().current_scene
	if main_scene != null and main_scene.has_method("request_dive"):
		main_scene.call("request_dive", fisher, self)
	else:
		push_warning("Diving entry requires the diving-enabled main scene.")
