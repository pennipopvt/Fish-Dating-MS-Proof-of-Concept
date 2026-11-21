class_name EncounterRuleData
extends Resource

# Place the most specific rules first in NPCData.encounter_rules.
@export_file("*.json") var json_path: String = ""
# Optional pool: if nonempty, pick one file when the rule first matches.
@export var json_pool: Array[String] = []
@export var required_flags: Array[StringName] = []
@export var forbidden_flags: Array[StringName] = []
@export var use_min_attraction: bool = false
@export var min_attraction: int = 0
## Minimum number of calendar day changes since receiving the correct gift.
## Zero preserves all existing encounter behavior.
@export_range(0, 30, 1) var min_days_after_gift: int = 0
