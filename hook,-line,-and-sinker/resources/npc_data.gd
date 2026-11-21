class_name NPCData
extends Resource

@export var npc_id: StringName
@export var display_name: String = ""

@export_group("Appearance")
@export var portrait: Texture2D
## Fish-form portrait for conversations while exploring underwater.
## Keep the human portrait untouched for scenes on land.
@export var underwater_sprite: Texture2D
@export var house: Texture2D
## Room doorway data. Does not control the diving party.
@export var door: DoorInfo
## Shown behind the shared first-person DialogueUI during room visits.
@export var room_background: Texture2D
@export var porn_sprite: Texture2D # Optional illustrated adult-scene background.

# Scores for bold / playful / reassuring answers at jealousy tiers 0, 1, 2, 3.
# Edit these arrays on each NPC resource to express their personality.
@export_group("Date Personality (Jealousy Tiers 0-3)")
@export var date_bold_scores: Array[int] = [6, 5, -4, -6]
@export var date_playful_scores: Array[int] = [3, 2, 0, -2]
@export var date_reassure_scores: Array[int] = [1, 1, 1, 1]


func date_score_for_style(style: String, jealousy_tier: int) -> int:
	var scores: Array[int] = []
	match style:
		"bold":
			scores = date_bold_scores
		"playful":
			scores = date_playful_scores
		"reassure":
			scores = date_reassure_scores
		_:
			return 0
	return scores[clampi(jealousy_tier, 0, scores.size() - 1)] if not scores.is_empty() else 0

@export_group("JSON Encounter Rules (first matching rule wins)")
@export var encounter_rules: Array[EncounterRuleData] = []

@export_group("Gift dialogue")
@export var desired_gift: ItemData
@export_file("*.json") var correct_gift_json: String = ""
@export var incorrect_gift_json_pool: Array[String] = []
@export var gift_completed_flag: StringName = &"gift_complete"

@export_group("Legacy Dialogue (optional)")
@export var defined_flags: Array[NPCFlagData] = []
@export var dialogue_rules: Array[NPCDialogueRuleData] = []
# Kept for backward compatibility with NPCs configured before encounter_rules.
@export_file("*.json") var dialogue_json_path: String = ""
