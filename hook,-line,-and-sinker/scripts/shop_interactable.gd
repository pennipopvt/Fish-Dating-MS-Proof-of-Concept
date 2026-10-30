class_name ShopInteractable
extends Interactable

@export var prompt: InteractPrompt

var _player_in_range := false


func _ready() -> void:
	super()
	ShopManager.shop_opened.connect(_update_prompt)
	ShopManager.shop_closed.connect(_update_prompt)


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


func interact(_player: Node2D) -> void:
	ShopManager.request_shop()


func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_in_range and not ShopManager.is_shop_open:
		prompt.pop_in()
	else:
		prompt.pop_out()
