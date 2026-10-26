
extends Node

signal trade_completed(trade: TradeData)

@export var trades: Array[TradeData] = []

var money: int = 0


func can_trade(trade: TradeData) -> bool:
	if trade == null or not trades.has(trade):
		return false

	if trade.required_items.is_empty():
		return false

	if trade.reward_money < 0:
		return false

	for item in trade.reward_items:
		if item == null:
			return false

	# Validate the function before removing any items.
	if trade.reward_method != &"":
		if not String(trade.reward_method).begins_with("shop_reward_"):
			return false

		if not FishingManager.has_method(trade.reward_method):
			return false

		if trade.reward_amount <= 0:
			return false

	var available: Array[ItemData] = (
		FishingManager.current_storage.duplicate()
	)

	for required in trade.required_items:
		if required == null:
			return false

		var index := _find_item(available, required.item_id)

		if index == -1:
			return false

		available.remove_at(index)

	return true


func make_trade(trade: TradeData) -> bool:
	if not can_trade(trade):
		return false

	# Consume the required fish.
	for required in trade.required_items:
		var index := _find_item(
			FishingManager.current_storage,
			required.item_id
		)

		FishingManager.current_storage.remove_at(index)

	# Execute an optional FishingManager upgrade.
	if trade.reward_method != &"":
		FishingManager.call(
			trade.reward_method,
			trade.reward_amount
		)

	trade_completed.emit(trade)
	return true


func _find_item(
	items: Array[ItemData],
	item_id: StringName
) -> int:
	for i in range(items.size()):
		if items[i] != null:
			if items[i].item_id == item_id:
				return i

	return -1
