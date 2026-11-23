class_name DialogueLineData
extends Resource

enum Speaker {
	PLAYER,
	NPC
}

@export var speaker: Speaker = Speaker.NPC
## Optional NPC ID from the conversation's cast; empty means current_npc.
@export var speaker_id: StringName = &""
@export_multiline var text: String = ""
@export var expression: StringName = &"neutral"
