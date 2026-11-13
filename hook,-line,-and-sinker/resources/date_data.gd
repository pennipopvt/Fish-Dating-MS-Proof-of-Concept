class_name DateData
extends Resource

# One date Penni can ask an NPC out on. DateManager loads every .tres in
# res://resources/dates/. The ask-out JSON offers it through a choice with
# required_flags ["date_ok_<date_id>"] and effects {"request_scene": "date:<date_id>"}.

enum When {
	NOW,        # Starts as soon as the NPC says yes.
	SCHEDULED,  # Booked for a period; Penni shows up at the place to start it.
}

@export var date_id: StringName
@export var display_name: String = ""
@export var npc: NPCData
# Matches DateLocation.location_id on a place in the world (e.g. beach, ship).
@export var location_id: StringName
@export_file("*.json") var dialogue_json: String = ""

@export_group("Timing")
# Periods the date can happen in. None ticked = any time.
@export_flags("Morning", "Afternoon", "Night") var periods: int = 0
@export var when: When = When.NOW
# NOW only: if the current period isn't allowed, skip the clock forward to the
# next allowed one (like resting). Off: the date can only be asked for during
# an allowed period.
@export var jump_clock: bool = true
# SCHEDULED only: 0 = the next allowed period from now (can be the current
# one), 1 = from tomorrow morning, and so on.
@export var days_ahead: int = 0

@export_group("Requirements (NPC flags)")
@export var required_flags: Array[StringName] = []
@export var forbidden_flags: Array[StringName] = []
@export var use_min_attraction: bool = false
@export var min_attraction: int = 0
# Off: the date disappears from the ask-out choices once done.
@export var repeatable: bool = false

@export_group("Result")
# Set when the date ends. Empty = "date_done_<date_id>".
@export var completed_flag: StringName
@export var flags_to_set: Array[StringName] = []
@export var attraction_change: int = 0
# Actions spent on top of the 1 every finished conversation already costs.
@export var extra_action_cost: int = 0


func get_completed_flag() -> StringName:
	return completed_flag if completed_flag != &"" else StringName("date_done_" + String(date_id))


func get_missed_flag() -> StringName:
	return StringName("date_missed_" + String(date_id))


# NPC flag the ask-out JSON checks to show this date's choice.
func get_available_flag() -> StringName:
	return StringName("date_ok_" + String(date_id))


func allows_period(period: int) -> bool:
	return periods == 0 or (periods & (1 << period)) != 0
