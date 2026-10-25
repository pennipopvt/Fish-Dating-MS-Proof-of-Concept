
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
