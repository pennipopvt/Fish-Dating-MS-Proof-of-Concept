class_name UpgradePickup
extends ItemPickup

# A drone-delivered package for a FishingManager upgrade trade (e.g. extra
# casts). The upgrade applies when the player picks it up; the package shows
# overhead for a moment and doesn't take the player's hands.

const CRATE := preload("res://sprites/placeholders/delivery_crate.png")

@export var trade: TradeData


func get_icon() -> Texture2D:
	if trade != null and trade.delivery_sprite != null:
		return trade.delivery_sprite
	return CRATE


func interact(_player: Node2D) -> void:
	if trade == null or trade.reward_method == &"":
		return

	FishingManager.call(trade.reward_method, trade.reward_amount)

	var player := _player as Player
	if player != null:
		player.show_pickup(get_icon())
		player.release_interactable(self)
	queue_free()
