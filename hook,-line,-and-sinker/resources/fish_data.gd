class_name FishData
extends Resource

@export var fish_id: StringName = &""
#Use item data if the fish is an item
@export var item_data: ItemData = null
#Use NPC data if the fish is an NPC
@export var npc_data: NPCData = null

##the default escape rate fighting the player
@export var escape_rate: float

##the escape rate when a fish becomes desperate
@export var desperation_escape_rate: float

##how long it takes before a fish becomes desperate
@export var desp_time: float

@export var desp_length: float
