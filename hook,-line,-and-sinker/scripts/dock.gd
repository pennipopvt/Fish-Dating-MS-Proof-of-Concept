extends Interactable

#hello!
func interact(_player: Node2D) -> void:
	var fisher := _player as Player
	
	if(fisher == null):
		return
	
	print("fishing time!")
	if(!fisher.busy) :
		fisher.fishing_controller.begin_fishing()
