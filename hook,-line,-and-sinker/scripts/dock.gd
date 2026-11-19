extends Interactable

# The dock keeps its ordinary interaction logic. The shared InteractPrompt
# only stays persistently visible during the very first diving tutorial.
@onready var _prompt: InteractPrompt = $InteractPrompt

var _first_dive_prompt: bool = false
var _dive_unlocked: bool = false
var _player_in_range: bool = false


func _ready() -> void:
	super()
	_update_prompt()


func spends_time() -> bool:
	return true


func set_first_dive_prompt(enabled: bool) -> void:
	_first_dive_prompt = enabled
	if enabled:
		_dive_unlocked = true
	_update_prompt()


func mark_dive_started() -> void:
	_first_dive_prompt = false
	_dive_unlocked = true
	_update_prompt()


func _on_body_entered(body: Node2D) -> void:
	super(body)
	if body is Player:
		_player_in_range = true
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	super(body)
	if body is Player:
		_player_in_range = false
		_update_prompt()


func _update_prompt() -> void:
	if not is_instance_valid(_prompt):
		return
	if _first_dive_prompt or (_dive_unlocked and _player_in_range):
		_prompt.pop_in()
	else:
		_prompt.pop_out()


func interact(_player: Node2D) -> void:
	var fisher := _player as Player
	if fisher == null or fisher.busy:
		return
	# The existing main scene owns the dive gating and confirmation;
	# this dock is only responsible for proximity and forwarding the action.
	var main_scene: Node = get_tree().current_scene
	if main_scene != null and main_scene.has_method("request_dive"):
		main_scene.call("request_dive", fisher, self)
	else:
		push_warning("Diving entry requires the diving-enabled main scene.")
