class_name IslandStoryEventData
extends Resource

# Inspector-authored island story beat. StoryManager owns when it runs;
# NPCManager/DialogueManager retain flags and dialogue progression.
@export var event_id: StringName = &""
@export var speaker: NPCData
@export_file("*.json") var dialogue_json: String = ""

@export_group("Eligibility")
@export_range(1, 999, 1) var earliest_day: int = 1
@export var requires_resident: bool = false
@export_range(0, 999, 1) var days_after_resident: int = 0
@export var requires_first_dive_onboarding: bool = false
@export var speaker_must_be_resident: bool = false
@export var required_flags: Array[StringName] = []
@export var forbidden_flags: Array[StringName] = []
@export_range(0, 30, 1) var min_days_after_gift: int = 0
@export var respect_overnight_boundaries: bool = false

@export_group("Morning Presentation")
## Morning-only events queue on day_started, not when a flag changes midday.
@export var morning_only: bool = false
## Spawn the NPC's existing land sprite at World/MorningStoryEntry.
@export var stage_land_actor: bool = false
@export_range(4.0, 120.0, 1.0) var approach_distance: float = 26.0
@export_range(10.0, 200.0, 1.0) var approach_speed: float = 65.0

@export_group("Completion")
## 0 = one-time. Positive = may be offered again after this many days
## while prerequisites still match (e.g., when Penni declined an invitation).
@export_range(0, 30, 1) var retry_after_days: int = 0
@export var completion_effect: StringName = &""
