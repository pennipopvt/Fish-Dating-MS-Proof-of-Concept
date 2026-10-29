class_name EncounterRuleData
extends Resource

# Place the most specific rules first in NPCData.encounter_rules.
@export_file("*.json") var json_path: String = ""
@export var required_flags: Array[StringName] = []
@export var forbidden_flags: Array[StringName] = []
@export var use_min_attraction: bool = false
@export var min_attraction: int = 0
