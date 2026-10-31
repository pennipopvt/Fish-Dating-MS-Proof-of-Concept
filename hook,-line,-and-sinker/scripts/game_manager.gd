extends Node

var time_of_day : Times = Times.MORNING
var player_actions : int = 3

enum Times {
	MORNING,
	AFTERNOON,
	NIGHT
}

# Menus in this group block player actions, not the running world.
func is_modal_ui_open() -> bool:
	for ui in get_tree().get_nodes_in_group(&"modal_ui"):
		if ui is CanvasItem and ui.visible:
			return true
	return false
