class_name BobberData
extends Resource

@export var bobber_id: StringName
@export var display_name: String = ""
@export var sprite: Texture2D
@export var source_npc_id: StringName

@export_group("Ability")
## Show the hooked fish's identity only once it bites.
@export var identifies_fish: bool = false
## Fraction of the selected fish attack's normal stun when the fish first bites.
## No parry event is emitted for this free opening.
@export_range(0.0, 1.0, 0.05) var opening_stun_fraction: float = 0.0
@export_multiline var ability_description: String = ""
