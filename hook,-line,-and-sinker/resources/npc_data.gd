class_name NPCData
extends Resource

@export var npc_id: StringName
@export var display_name: String = ""

@export_group("Appearance")
@export var portrait: Texture2D

@export_group("Flags")
@export var defined_flags: Array[NPCFlagData] = []

@export_group("Dialogue")
@export var dialogue_rules: Array[NPCDialogueRuleData] = []
# Optional. When set, loads a JSON dialogue graph instead of legacy dialogue_rules.
@export_file("*.json") var dialogue_json_path: String = ""
