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
	# Discard stale world packages after a debug reset or a second pickup.
	# A consumed/cancelled order must never silently re-apply an upgrade.
	if trade.one_time_purchase and not ShopManager.is_upgrade_ordered(trade):
		var stale_player := _player as Player
		if stale_player != null:
			stale_player.release_interactable(self)
		queue_free()
		return

	FishingManager.call(trade.reward_method, trade.reward_amount)
	ShopManager.mark_upgrade_delivered(trade)

	var player := _player as Player
	if player != null:
		player.show_pickup(get_icon())
		player.release_interactable(self)
	queue_free()
