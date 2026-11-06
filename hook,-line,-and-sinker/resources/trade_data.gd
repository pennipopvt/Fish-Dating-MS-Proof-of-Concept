
class_name TradeData
extends Resource

@export var trade_id: StringName
@export var display_name: String = ""
@export var icon: Texture2D

@export_group("Requirements")
@export var requirements: Array[TradeRequirement] = []

@export_group("Fishing Manager Reward")
@export var reward_method: StringName = &""
@export var reward_amount: int = 1

@export_group("Item Reward")
## Added to the player's storage on purchase, e.g. a gift for an NPC.
@export var reward_item: ItemData = null
@export_range(1, 99) var reward_item_amount: int = 1
