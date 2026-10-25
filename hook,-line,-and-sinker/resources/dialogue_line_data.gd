class_name DialogueLineData
extends Resource

enum Speaker {
	PLAYER,
	NPC
}

@export var speaker: Speaker = Speaker.NPC
@export_multiline var text: String = ""
@export var expression: StringName = &"neutral"
