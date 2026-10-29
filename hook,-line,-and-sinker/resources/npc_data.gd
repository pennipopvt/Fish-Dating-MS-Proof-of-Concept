class_name NPCData
extends Resource

@export var npc_id: StringName
@export var display_name: String = ""

@export_group("Appearance")
@export var portrait: Texture2D

@export_group("JSON Encounter Rules (first matching rule wins)")
@export var encounter_rules: Array[EncounterRuleData] = []

@export_group("Legacy Dialogue (optional)")
@export var defined_flags: Array[NPCFlagData] = []
@export var dialogue_rules: Array[NPCDialogueRuleData] = []
# Kept for backward compatibility with NPCs configured before encounter_rules.
@export_file("*.json") var dialogue_json_path: String = ""
