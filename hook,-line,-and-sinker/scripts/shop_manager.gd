
extends Node

signal trade_completed(trade: TradeData)
signal shop_requested
signal shop_opened
signal shop_closed

var is_shop_open: bool = false

func request_shop() -> void:
	if not is_shop_open:
		shop_requested.emit()

func set_shop_open(opened: bool) -> void:
	if is_shop_open == opened:
		return
	is_shop_open = opened
	if opened:
		shop_opened.emit()
	else:
		shop_closed.emit()

@export var trades: Array[TradeData] = []

var money: int = 0


func can_trade(trade: TradeData) -> bool:
	if trade == null or not trades.has(trade):
		return false

	if trade.requirements.is_empty():
		return false

	# Validate the function before removing any items.
	if trade.reward_method != &"":
		if not String(trade.reward_method).begins_with("shop_reward_"):
			return false

		if not FishingManager.has_method(trade.reward_method):
			return false

		if trade.reward_amount <= 0:
			return false

	for requirement in trade.requirements:
		if requirement == null or requirement.item == null:
			return false

		if requirement.amount <= 0:
			return false

	var needed := get_required_counts(trade)

	for item_id in needed:
		if count_item(item_id) < needed[item_id]:
			return false

	return true


func make_trade(trade: TradeData) -> bool:
	if not can_trade(trade):
		return false

	# Consume the required fish.
	var needed := get_required_counts(trade)

	for item_id in needed:
		for i in range(needed[item_id]):
			var index := _find_item(
				FishingManager.current_storage,
				item_id
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


# Total amount needed per item_id, combining repeated requirements.
func get_required_counts(trade: TradeData) -> Dictionary:
	var needed: Dictionary = {}

	for requirement in trade.requirements:
		if requirement != null and requirement.item != null:
			var item_id: StringName = requirement.item.item_id
			needed[item_id] = needed.get(item_id, 0) + requirement.amount

	return needed


# How many of an item the player has in storage.
func count_item(item_id: StringName) -> int:
	var count := 0

	for item in FishingManager.current_storage:
		if item != null and item.item_id == item_id:
			count += 1

	return count


func _find_item(
	items: Array[ItemData],
	item_id: StringName
) -> int:
	for i in range(items.size()):
		if items[i] != null:
			if items[i].item_id == item_id:
				return i

	return -1
