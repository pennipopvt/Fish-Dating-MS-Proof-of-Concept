class_name CompanionStats
extends Resource

# Battle stats for an underwater companion's auto-battle against wild fish
# (DivingCompanionBattle). Fish use the matching fields on FishData.

@export var companion_name: String = "Silas"
@export_range(1.0, 500.0, 1.0) var max_health: float = 60.0
## Damage per hit against a fish, before the fish's defense.
@export_range(0.0, 50.0, 0.5) var attack: float = 6.0
## Reduces each fish hit by half this value (min 1 damage).
@export_range(0.0, 50.0, 0.5) var defense: float = 3.0
## Attacks per second.
@export_range(0.1, 5.0, 0.05) var speed: float = 1.0
## Health regained per second while not battling. No regen once knocked out:
## a knocked-out companion recovers only when the player rests.
@export_range(0.0, 10.0, 0.1) var regen_per_second: float = 0.5
