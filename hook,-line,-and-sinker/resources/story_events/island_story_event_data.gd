class_name IslandStoryEventData
extends Resource

# Author a one-time island story beat in the Inspector. The director schedules
# it, the existing DialogueManager plays it, and the system named by
# completion_effect retains ownership of the actual gameplay state.
@export var event_id: StringName = &""
@export var speaker: NPCData
@export_file("*.json") var dialogue_json: String = ""

@export_group("Eligibility")
@export_range(1, 999, 1) var earliest_day: int = 1
## Optional: require a resident, and wait this many calendar days since move-in.
@export var requires_resident: bool = false
@export_range(0, 999, 1) var days_after_resident: int = 0
@export var requires_first_dive_onboarding: bool = false

@export_group("Completion")
## An effect handled at a single boundary in the island director.
@export var completion_effect: StringName = &""
