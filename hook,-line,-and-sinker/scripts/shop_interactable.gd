class_name ShopInteractable
extends Interactable

@export var prompt: InteractPrompt

@export_group("Delivery")
## Where purchased items land, relative to the terminal (to its right, clear
## of the bobber shelf).
@export var drop_offset := Vector2(26, 0)
## Extra items from the same trade line up along this step.
@export var drop_spacing := Vector2(18, 0)

@export_group("Notices")
## Where challenge notices point their tail, relative to the terminal
## (just above the interact prompt).
@export var notice_offset := Vector2(0, -29)

var _player_in_range := false
var _pending: Array[ItemPickup] = []  # bought while the menu is open


func _ready() -> void:
	super()
	ShopManager.delivery_point = self
	ShopManager.shop_opened.connect(_update_prompt)
	ShopManager.shop_closed.connect(_update_prompt)
	ShopManager.shop_closed.connect(_launch_drone)


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


# Called by ShopManager after a trade: a drone flies the pickups (items or
# upgrade packages) in and drops them next to the terminal. Items bought while the
# shop menu is open wait until it closes so the player sees the drone, and
# arrive together on one drone.
func deliver(pickups: Array[ItemPickup]) -> void:
	_pending.append_array(pickups)
	if not ShopManager.is_shop_open:
		_launch_drone()


func _launch_drone() -> void:
	if _pending.is_empty():
		return

	var pickups: Array[ItemPickup] = _pending.duplicate()
	_pending.clear()

	var positions: Array[Vector2] = []
	for i in pickups.size():
		positions.append(global_position + drop_offset + drop_spacing * i)

	var drone := DeliveryDrone.new()
	get_parent().add_child(drone)
	drone.deliver(pickups, positions)


func _exit_tree() -> void:
	if ShopManager.delivery_point == self:
		ShopManager.delivery_point = null
	for pickup in _pending:
		pickup.free()
	_pending.clear()
