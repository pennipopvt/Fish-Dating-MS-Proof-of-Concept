class_name DialogueData
extends Resource

@export var dialogue_id: StringName

@export_group("Dialogue")
@export var lines: Array[DialogueLineData] = []

@export_group("Choices")
@export var choices: Array[DialogueChoiceData] = []
