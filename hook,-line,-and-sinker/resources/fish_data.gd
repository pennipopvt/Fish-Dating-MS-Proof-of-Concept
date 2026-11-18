class_name FishData
extends Resource

@export var fish_id: StringName = &""
#Use item data if the fish is an item
@export var item_data: ItemData = null
##The scene for the fish's initial catch
@export var npc_data: PackedScene = null

@export_group("Visuals")
## Optional on-line sprite width in world pixels. Zero preserves the scene's
## existing sprite scale for other fish/resources.
@export_range(0.0, 128.0, 1.0) var hooked_sprite_width: float = 0.0

## Continuous pull rate between attacks in diving combat, as a fraction
## of available net length per second. FishEscapeState.escape_rate separately
## controls contested attack pulling and missed-parry dash speed.
@export_range(0.0, 0.2, 0.001) var passive_escape_rate: float = 0.015
@export_group("Tension")
## Tension added per reel scroll (the old scene value was 0.015).
@export_range(0.0, 1.0, 0.001) var reel_tension_gain: float = 0.015
## Total tension added over a missed-parry dash before the multiplier.
@export_range(0.0, 1.0, 0.01) var miss_tension_gain: float = 0.10
## Multiplies dash tension; also multiplies reel tension during an attack.
@export_range(0.0, 5.0, 0.05) var attack_tension_multiplier: float = 1.2

@export_group("Miss Dash")
## Seconds spent moving backward after a missed parry.
## Default is 0.25s; different fish can have different durations.
@export_range(0.05, 0.5, 0.01) var miss_dash_duration: float = 0.25
## Multiplier on the selected attack's escape_rate during a miss dash.
@export_range(1.0, 8.0, 0.25) var miss_dash_speed_multiplier: float = 3.0

@export_group("Stagger")
## Parry pressure needed to stagger this species. Carried over from the
## revised-fishing prototype; a single perfect parry is not a full stun.
@export_range(20.0, 300.0, 1.0) var stagger_resistance: float = 100.0

@export_group("Battle")
## Diving: health that a companion's auto-battle wears down before netting.
## Remaining health also weakens the fish's pull and tension in the reel fight.
@export_range(1.0, 500.0, 1.0) var max_health: float = 30.0
## Damage per hit against the companion, before its defense.
@export_range(0.0, 50.0, 0.5) var attack: float = 3.0
## Reduces each companion hit by half this value (min 1 damage).
@export_range(0.0, 50.0, 0.5) var defense: float = 2.0
## Attacks per second in the auto-battle.
@export_range(0.1, 5.0, 0.05) var speed: float = 1.0
## Reel-fight strength at full health (multiplies pulling, dash distance and
## tension). It falls toward DivingCombat.low_health_strength as health drops.
## 1.0 = beatable without a battle; much higher makes a fresh fish
## practically impossible to reel in until the companion wears it down.
@export_range(0.1, 6.0, 0.05) var full_health_strength: float = 1.0

@export_group("Attacks")
@export var states: Array[FishEscapeState] = []
