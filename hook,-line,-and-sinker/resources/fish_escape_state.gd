class_name FishEscapeState
extends Resource

@export var state_name: String
## Fish movement speed in reel-progress units per second. Used for both
## contested close-parry pulling and the single missed-parry dash.
@export_range(0.0, 2.0, 0.01) var escape_rate: float
@export var state_length: float
@export_range(0,1) var state_probability: float

# Durations / windows are editable on each attack. Older fish resources
# retain their authored values.
@export_range(0.05, 2.0, 0.01) var windup_duration: float = 0.45
## Legacy value retained for saved fish resources; no longer used by parry timing.
@export_range(0.0, 1.0, 0.01) var grace_start: float = 0.24
@export_range(0.03, 0.5, 0.01) var counter_window: float = 0.16
## Legacy value retained for saved fish resources. Next attacks start
## immediately at pre-windup (there is no extra recovery phase).
@export_range(0.05, 2.0, 0.01) var recovery_duration: float = 0.4
@export_range(0.1, 4.0, 0.01) var stun_duration: float = 1.7
## Legacy value retained for old resources. Perfect parries now clear tension.
@export_range(0.0, 1.0, 0.01) var counter_tension_relief: float = 0.25

@export_group("Parry Combat")
## Short warning BEFORE windup. No reeling is allowed once this starts.
@export_range(0.05, 1.0, 0.01) var pre_windup_duration: float = 0.22
## Near-hit just before the attack begins (resisted reeling, no stun).
@export_range(0.0, 0.5, 0.01) var close_early_window: float = 0.10
## Near-hit just after the perfect window closes (resisted reeling).
@export_range(0.0, 0.5, 0.01) var close_late_window: float = 0.18
## Legacy field kept for older .tres files. A miss now moves exactly
## escape_rate * FishingController.miss_dash_duration; this is not used.
@export_range(0.0, 0.5, 0.01) var miss_progress_loss: float = 0.04
## Legacy value retained for older attack resources.
## Actual miss tension is now FishData.miss_tension_gain.
@export_range(0.0, 1.0, 0.01) var miss_tension_gain: float = 0.10
