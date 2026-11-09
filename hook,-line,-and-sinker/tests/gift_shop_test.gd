extends SceneTree

# Check FISH CO. gifts and the matching pickup and shop artwork.
# godot --headless --path . -s res://tests/gift_shop_test.gd

const SHOP_SCENE: PackedScene = preload("res://scenes/shop_manager.tscn")
const SPYGLASS_TRADE: TradeData = preload("res://resources/trades/spyglass.tres")
const NECKLACE_TRADE: TradeData = preload("res://resources/trades/pearl_necklace_gift.tres")
const STATUE_TRADE: TradeData = preload("res://resources/trades/statue_gift.tres")
const SPYGLASS_ITEM: ItemData = preload("res://resources/items/spyglass.tres")
const NECKLACE_ITEM: ItemData = preload("res://resources/items/pearl_necklace_item.tres")
const STATUE_ITEM: ItemData = preload("res://resources/items/statue.tres")
const HARD_FISH: ItemData = preload("res://resources/items/hard_test_fish_item.tres")
const EASY_FISH: ItemData = preload("res://resources/items/easy_test_fish_item.tres")
const SILAS: NPCData = preload("res://resources/npcs/test_npc.tres")

const SPYGLASS_ART: Texture2D = preload("res://sprites/gifts/gift_spyglass.png")
const NECKLACE_ART: Texture2D = preload("res://sprites/gifts/gift_necklace.png")
const STATUE_ART: Texture2D = preload("res://sprites/gifts/gift_statue.png")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var shop: Node = SHOP_SCENE.instantiate()
	var trades: Array = shop.get("trades")
	_expect(trades.has(SPYGLASS_TRADE), "Spyglass is in the shop")
	_expect(trades.has(NECKLACE_TRADE), "Pearl Necklace is in the shop")
	_expect(trades.has(STATUE_TRADE), "Statue is in the shop")
	_expect(SPYGLASS_TRADE.requirements.size() == 1 and SPYGLASS_TRADE.requirements[0].item == HARD_FISH and SPYGLASS_TRADE.requirements[0].amount == 2, "Spyglass costs exactly two hard fish")
	_expect(NECKLACE_TRADE.requirements.size() == 2, "Existing necklace cost is unchanged")
	_expect(STATUE_TRADE.requirements.size() == 1 and STATUE_TRADE.requirements[0].item == EASY_FISH and STATUE_TRADE.requirements[0].amount == 1, "Statue costs one easy fish")
	_expect(SPYGLASS_TRADE.icon == SPYGLASS_ART and SPYGLASS_ITEM.sprite == SPYGLASS_ART, "Spyglass item and shop use gift sprite")
	_expect(NECKLACE_TRADE.icon == NECKLACE_ART and NECKLACE_ITEM.sprite == NECKLACE_ART, "Necklace item and shop use gift sprite")
	_expect(STATUE_TRADE.icon == STATUE_ART and STATUE_ITEM.sprite == STATUE_ART, "Statue item and shop use gift sprite")
	_expect(SPYGLASS_TRADE.reward_item == SPYGLASS_ITEM, "Spyglass delivery contains updated item")
	_expect(NECKLACE_TRADE.reward_item == NECKLACE_ITEM, "Necklace delivery contains updated item")
	_expect(STATUE_TRADE.reward_item == STATUE_ITEM, "Statue delivery contains updated item")
	_expect(SILAS.desired_gift == SPYGLASS_ITEM, "Silas still wants the Spyglass")
	shop.free()
	print("FAILED: %d" % failures if failures > 0 else "All gift shop checks passed")
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + description)
	if not ok:
		failures += 1
