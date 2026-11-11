
extends Node

# Trades: takes fish out of FishingManager storage and hands out rewards.
# Talks outward only through signals: the terminal (ShopInteractable) listens
# to delivery_requested and drops the pickups; menus listen to the rest.

signal trade_completed(trade: TradeData)
signal upgrade_state_changed(trade: TradeData)
signal shop_requested
signal shop_opened
signal shop_closed
# A trade's rewards should be delivered into the world (drone at the terminal).
# With no listener, rewards apply immediately instead.
signal delivery_requested(pickups: Array[ItemPickup])

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
# An ordered upgrade is reserved until its delivered package is collected.
var pending_upgrade_ids: Array[StringName] = []

var money: int = 0


# True when something in the world delivers rewards (the terminal is loaded).
func has_delivery_point() -> bool:
	return delivery_requested.has_connections()


func is_upgrade_owned(trade: TradeData) -> bool:
	return trade != null and trade.one_time_purchase and FishingManager.has_upgrade(trade.trade_id)


func is_upgrade_ordered(trade: TradeData) -> bool:
	return trade != null and trade.one_time_purchase and pending_upgrade_ids.has(trade.trade_id)


# Called when the player picks up a delivered upgrade package (or right away
# with no terminal). Applies the FishingManager shop_reward_* method.
func collect_upgrade(trade: TradeData) -> void:
	if trade == null:
		return
	if trade.reward_method != &"" and FishingManager.has_method(trade.reward_method):
		FishingManager.call(trade.reward_method, trade.reward_amount)
	if trade.one_time_purchase:
		pending_upgrade_ids.erase(trade.trade_id)
		upgrade_state_changed.emit(trade)


# The manager owns purchase state; the world only owns physical pickups.
# Rebuild uncollected one-time upgrade packages when a world scene reloads.
# Item gifts are not reconstructed here (their delivery history is not tracked).
func get_pending_upgrade_pickups() -> Array[ItemPickup]:
	var pickups: Array[ItemPickup] = []
	var seen: Array[StringName] = []
	for id in pending_upgrade_ids:
		if seen.has(id) or FishingManager.has_upgrade(id):
			continue
		seen.append(id)
		for trade in trades:
			if trade == null or not trade.one_time_purchase or trade.trade_id != id:
				continue
			if trade.reward_method != &"":
				var package := UpgradePickup.new()
				package.trade = trade
				pickups.append(package)
			break
	return pickups


func can_trade(trade: TradeData) -> bool:
	if trade == null or not trades.has(trade):
		return false
	if is_upgrade_owned(trade) or is_upgrade_ordered(trade):
		return false

	if trade.requirements.is_empty():
		return false

	if is_trade_locked(trade):
		return false

	if trade.reward_item != null and trade.reward_item_amount <= 0:
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
		FishingManager.remove_from_storage(item_id, needed[item_id])

	if trade.one_time_purchase:
		pending_upgrade_ids.append(trade.trade_id)

	if has_delivery_point():
		# A drone drops everything next to the terminal. Items stay on the
		# ground until carried off by hand; upgrades arrive as a package that
		# applies when picked up.
		delivery_requested.emit(_make_pickups(trade))
	else:
		_apply_rewards(trade)

	trade_completed.emit(trade)
	return true


func _make_pickups(trade: TradeData) -> Array[ItemPickup]:
	var pickups: Array[ItemPickup] = []

	if trade.reward_method != &"":
		var package := UpgradePickup.new()
		package.trade = trade
		pickups.append(package)

	if trade.reward_item != null:
		for i in range(trade.reward_item_amount):
			var pickup := ItemPickup.new()
			pickup.item = trade.reward_item
			pickups.append(pickup)

	return pickups


# No terminal in the scene (e.g. tests): apply rewards immediately.
func _apply_rewards(trade: TradeData) -> void:
	collect_upgrade(trade)

	if trade.reward_item != null:
		FishingManager.add_to_storage(trade.reward_item, trade.reward_item_amount)


# Trades rewarded by an incomplete challenge are locked.
func is_trade_locked(trade: TradeData) -> bool:
	return ChallengeManager.is_trade_locked(trade)


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
	return FishingManager.count_in_storage(item_id)
