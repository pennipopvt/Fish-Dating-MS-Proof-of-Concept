class_name ShopInteractable
extends Interactable

@export var shop_menu: ShopMenu
@export var prompt: InteractPrompt

var _player_in_range := false


func _ready() -> void:
	super()

	if shop_menu != null:
		shop_menu.visibility_changed.connect(_update_prompt)


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
	if shop_menu == null:
		push_warning("ShopInteractable has no shop_menu assigned.")
		return

	shop_menu.open()


# Show the key prompt only while the player can open the shop.
func _update_prompt() -> void:
	if prompt == null:
		return

	var menu_open := shop_menu != null and shop_menu.visible

	if _player_in_range and not menu_open:
		prompt.pop_in()
	else:
		prompt.pop_out()
