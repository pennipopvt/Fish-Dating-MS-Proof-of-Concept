
class_name TradeData
extends Resource

@export var trade_id: StringName
@export var display_name: String = ""

@export_group("Requirements")
@export var required_items: Array[ItemData] = []

@export_group("Fishing Manager Reward")
@export var reward_method: StringName = &""
@export var reward_amount: int = 1
