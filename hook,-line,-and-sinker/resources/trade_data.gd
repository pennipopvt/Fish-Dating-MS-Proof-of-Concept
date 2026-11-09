
class_name TradeData
extends Resource

@export var trade_id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## If true, this upgrade can only be ordered once, including while awaiting delivery.
@export var one_time_purchase: bool = false
@export var icon: Texture2D

@export_group("Requirements")
@export var requirements: Array[TradeRequirement] = []

@export_group("Fishing Manager Reward")
@export var reward_method: StringName = &""
@export var reward_amount: int = 1
## World sprite for the drone-delivered upgrade package; defaults to a crate.
@export var delivery_sprite: Texture2D = null

@export_group("Item Reward")
## Delivered by drone next to the terminal on purchase, e.g. a gift for an NPC.
@export var reward_item: ItemData = null
@export_range(1, 99) var reward_item_amount: int = 1
