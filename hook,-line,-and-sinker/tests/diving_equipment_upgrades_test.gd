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

	var prices: Dictionary = {
		&"larger_tank": {&"mullet": 2},
		&"extended_net": {&"mullet": 1, &"porgy": 1},
		&"pressure_regulator": {&"goby": 1, &"flounder": 1},
	}
	for trade in [TANK, EXTENDED, REGULATOR]:
		_check(ShopManager.trades.has(trade), "Equipment upgrade is in the actual shop")
		_check(trade.one_time_purchase and trade.delivery_time == 1,
			"Equipment keeps one-time next-day delivery")
		var cost: Dictionary = {}
		for requirement in trade.requirements:
			cost[requirement.item.item_id] = requirement.amount
		_check(cost == prices[trade.trade_id], "Equipment uses the agreed barter price")

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
	net.direction = Vector2.LEFT
	net._orient_net_sprite()
	_check(not sprite.flip_h and is_zero_approx(sprite.rotation)
		and net._cord_endpoint().x > net.tip.x,
		"Leftward cast uses unflipped artwork and its original right-side handle")
	net.direction = Vector2.RIGHT
	net._orient_net_sprite()
	_check(not sprite.flip_h and absf(absf(sprite.rotation) - PI) < 0.01
		and net._cord_endpoint().x < net.tip.x,
		"Rightward cast rotates a half turn and keeps its handle attached")
	net.direction = Vector2.UP
	net._orient_net_sprite()
	_check(not sprite.flip_h and net._cord_endpoint().y > net.tip.y,
		"Upward cast rotates the net with its handle trailing downward")
	net.direction = Vector2.DOWN
	net._orient_net_sprite()
	_check(not sprite.flip_h and net._cord_endpoint().y < net.tip.y,
		"Downward cast rotates the net with its handle trailing upward")
	net.direction = Vector2(-1.0, -1.0).normalized()
	net._orient_net_sprite()
	var handle_offset: Vector2 = net._cord_endpoint() - net.tip
	_check(is_equal_approx(sprite.rotation, PI / 4.0)
		and handle_offset.x > 0.0 and handle_offset.y > 0.0,
		"Diagonal cast rotates the sprite and preserves the same handle location")

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
