class_name NPCDialogueRuleData
extends Resource

@export var dialogue: DialogueData

@export_group("Conditions")
@export var required_flags: Array[NPCFlagData] = []
@export var forbidden_flags: Array[NPCFlagData] = []
