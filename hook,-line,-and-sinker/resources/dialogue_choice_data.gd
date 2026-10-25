class_name DialogueChoiceData
extends Resource

@export_multiline var text: String = ""

@export_group("Next Dialogue")
@export var next_dialogue: DialogueData

@export_group("Effects")
@export var attraction_change: int = 0
@export var flags_to_set: Array[NPCFlagData] = []
@export var flags_to_clear: Array[NPCFlagData] = []
