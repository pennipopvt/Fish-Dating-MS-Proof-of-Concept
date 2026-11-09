extends SceneTree

# Ensures uncollected upgrade purchases can be recreated on world reload.
# Run from Godot project root:
# godot --headless --path . -s res://tests/delivery_recovery_test.gd

const SHOP_SCRIPT = preload("res://scripts/shop_manager.gd")
const REEL: TradeData = preload("res://resources/trades/stronger_reel.tres")
const LINE: TradeData = preload("res://resources/trades/reinforced_line.tres")
const GIFT: TradeData = preload("res://resources/trades/spyglass.tres")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var shop: Node = SHOP_SCRIPT.new()
	var offers: Array[TradeData] = [REEL, LINE, GIFT]
	shop.trades = offers

	shop.pending_upgrade_ids = [&"stronger_reel", &"reinforced_line"]
	var deliveries: Array[ItemPickup] = shop.get_pending_upgrade_pickups()
	_expect(deliveries.size() == 2, "every pending upgrade is restored exactly once")
	_expect(deliveries[0] is UpgradePickup and deliveries[0].trade == REEL, "reel package is reconstructed")
	_expect(deliveries[1] is UpgradePickup and deliveries[1].trade == LINE, "line package is reconstructed")
	for pickup in deliveries:
		pickup.free()

	shop.pending_upgrade_ids = [&"stronger_reel", &"stronger_reel"]
	var duplicates: Array[ItemPickup] = shop.get_pending_upgrade_pickups()
	_expect(duplicates.size() == 1, "duplicate pending ID does not create duplicate packages")
	for pickup in duplicates:
		pickup.free()

	shop.pending_upgrade_ids = [&"spyglass"]
	var gifts: Array[ItemPickup] = shop.get_pending_upgrade_pickups()
	_expect(gifts.is_empty(), "untracked gift deliveries aren't recreated as upgrades")
	for pickup in gifts:
		pickup.free()

	shop.pending_upgrade_ids.clear()
	_expect(shop.get_pending_upgrade_pickups().is_empty(), "collected/reset upgrades no longer redeliver")
	shop.free()
	print("FAILED: %d" % failures if failures > 0 else "Delivery recovery checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
