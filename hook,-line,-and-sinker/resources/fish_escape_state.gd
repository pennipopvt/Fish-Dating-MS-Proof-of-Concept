class_name FishEscapeState
extends Resource

@export var state_name: String
@export var escape_rate: float
@export var state_length: float
@export_range(0,1) var state_probability: float

# Attack phases. Older fish .tres resources retain their existing values.
@export_range(0.05, 2.0, 0.01) var windup_duration: float = 0.45
@export_range(0.0, 1.0, 0.01) var grace_start: float = 0.24
@export_range(0.03, 0.5, 0.01) var counter_window: float = 0.16
@export_range(0.05, 2.0, 0.01) var recovery_duration: float = 0.4
@export_range(0.1, 4.0, 0.01) var stun_duration: float = 1.7
@export_range(0.0, 1.0, 0.01) var counter_tension_relief: float = 0.25
