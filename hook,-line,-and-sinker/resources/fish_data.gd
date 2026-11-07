class_name FishData
extends Resource

@export var fish_id: StringName = &""
#Use item data if the fish is an item
@export var item_data: ItemData = null
##The scene for the fish's initial catch
@export var npc_data: PackedScene = null

## Legacy setting retained so existing fish resources still load. In the
## parry/dash combat system fish do not drift backward automatically.
## Per-attack FishEscapeState.escape_rate controls contested pull and dash speed.
@export_range(0.0, 0.2, 0.001) var passive_escape_rate: float = 0.015
## Additional tension while reeling against an active escape attack.
@export_range(0.0, 5.0, 0.05) var attack_tension_multiplier: float = 1.2

@export_group("Miss Dash")
## Seconds spent moving backward after a missed parry.
## Default is 0.25s; different fish can have different durations.
@export_range(0.05, 0.5, 0.01) var miss_dash_duration: float = 0.25
## Multiplier on the selected attack's escape_rate during a miss dash.
@export_range(1.0, 8.0, 0.25) var miss_dash_speed_multiplier: float = 3.0

@export_group("Attacks")
@export var states: Array[FishEscapeState] = []
