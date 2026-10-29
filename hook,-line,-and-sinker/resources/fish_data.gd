class_name FishData
extends Resource

@export var fish_id: StringName = &""
#Use item data if the fish is an item
@export var item_data: ItemData = null
#Use NPC data if the fish is an NPC
@export var npc_data: NPCData = null

@export var escape_rate: float
