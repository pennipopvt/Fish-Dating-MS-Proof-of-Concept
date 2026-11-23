extends Node

# Run: godot --headless --path . res://tests/diving_equipment_upgrades_test.tscn
# The shop remains barter-and-delivery based; verify both actual equipment
# effects and the sprite-edge cord alignment in isolation.
const TANK: TradeData = preload("res://resources/trades/larger_tank.tres")
const EXTENDED: TradeData = preload("res://resources/trades/extended_net.tres")
const REGULATOR: TradeData = preload("res://resources/trades/pressure_regulator.tres")
const NET_TEXTURE: Texture2D = preload("res://sprites/ui/net.png")

var failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	FishingManager.reset_session_upgrades()

	for trade in [TANK, EXTENDED, REGULATOR]:
		_check(ShopManager.trades.has(trade), "Preview upgrade is offered in the actual terminal shop")
		_check(trade.one_time_purchase and trade.delivery_time == 1,
			"Upgrade uses the existing one-time next-day delivery workflow")
		_check(trade.requirements.size() == 1 and trade.requirements[0].item.item_id == &"mullet"
			and trade.requirements[0].amount == 1, "Preview price is one mullet")

	var oxygen := SeaOxygen.new()
	add_child(oxygen)
	var net := DivingNetProjectile.new()
	var sprite := Sprite2D.new()
	sprite.name = "NetSprite"
	sprite.texture = NET_TEXTURE
	sprite.hframes = 4
	net.add_child(sprite)
	add_child(net)

	oxygen.begin_dive(true)
	_check(is_equal_approx(oxygen.remaining_seconds, 120.0),
		"Starting oxygen capacity remains 120 seconds")
	_check(is_equal_approx(oxygen.drain_multiplier_at_depth(634.0), 1.8),
		"Base deep-water drain stays at 1.8x")
	_check(is_equal_approx(net.effective_max_range(), 110.0),
		"Base throw range is unchanged")

	FishingManager.shop_reward_larger_tank(TANK.reward_amount)
	FishingManager.shop_reward_extended_net(EXTENDED.reward_amount)
	FishingManager.shop_reward_pressure_regulator(REGULATOR.reward_amount)
	oxygen.begin_dive(true)
	_check(is_equal_approx(oxygen.remaining_seconds, 150.0)
		and is_equal_approx(oxygen.ratio(), 1.0),
		"Larger Tank refills to a new capacity of 150 seconds")
	_check(is_equal_approx(net.effective_max_range(), 130.0),
		"Extended Net reaches 130 pixels without mutating editor base")
	_check(is_equal_approx(oxygen.drain_multiplier_at_depth(154.0), 1.0)
		and is_equal_approx(oxygen.drain_multiplier_at_depth(634.0), 1.6),
		"Pressure Regulator leaves surface drain at 1x, lowers deepest drain to 1.6x")

	net.tip = Vector2(100.0, 50.0)
	sprite.position = net.tip
	net.direction = Vector2.RIGHT
	sprite.flip_h = false
	_check(net._cord_endpoint().x > net.tip.x,
		"Cord attaches on right edge of forward-facing net sprite")
	net.direction = Vector2.LEFT
	sprite.flip_h = true
	_check(net._cord_endpoint().x < net.tip.x,
		"Cord attaches on mirrored left edge when thrown left")

	FishingManager.shop_reward_larger_tank(999)
	FishingManager.shop_reward_extended_net(999)
	FishingManager.shop_reward_pressure_regulator(99)
	_check(is_equal_approx(oxygen.effective_capacity_seconds(), 150.0)
		and is_equal_approx(net.effective_max_range(), 130.0),
		"Collecting upgrades again cannot stack their bonuses")
	FishingManager.reset_session_upgrades()
	_check(is_equal_approx(oxygen.effective_capacity_seconds(), 120.0)
		and is_equal_approx(net.effective_max_range(), 110.0)
		and is_equal_approx(oxygen.drain_multiplier_at_depth(634.0), 1.8),
		"Reset restores each equipment baseline")

	net.queue_free()
	oxygen.queue_free()
	print("diving_equipment_upgrades_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, description: String) -> void:
	if ok:
		print("  ok   ", description)
	else:
		failures += 1
		push_error("  FAIL " + description)
