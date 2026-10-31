class_name FishData
extends Resource

@export var fish_id: StringName = &""
#Use item data if the fish is an item
@export var item_data: ItemData = null
#Use NPC data if the fish is an NPC
@export var npc_data: NPCData = null

## Constant pull against reel progress, except while stunned.
@export_range(0.0, 0.2, 0.001) var passive_escape_rate: float = 0.015
## Additional tension while reeling against an active escape attack.
@export_range(0.0, 5.0, 0.05) var attack_tension_multiplier: float = 1.2

@export var states: Array[FishEscapeState] = []
