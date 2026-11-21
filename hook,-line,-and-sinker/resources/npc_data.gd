class_name NPCData
extends Resource

@export var npc_id: StringName
@export var display_name: String = ""

@export_group("Appearance")
@export var portrait: Texture2D
## Fish-form portrait for conversations while exploring underwater.
## Keep the human portrait untouched for scenes on land.
@export var underwater_sprite: Texture2D
## Fish-form world size and underwater conversation framing. Optional.
@export var sea_visuals: SeaCharacterVisuals

@export_group("Sea Companion Combat")
## Optional: a diving follower with stats also fights on its own. NPCs
## without these settings remain purely visual followers.
@export var sea_battle_stats: CompanionStats
## Must extend CompanionCombatBehavior. Defaults to lethal base behavior;
## Silas continues using his editor-authored specialized actor.
@export var sea_combat_behavior_script: Script

@export_group("Appearance")
@export var house: Texture2D
## Room doorway data. Does not control the diving party.
@export var door: DoorInfo
## Shown behind the shared first-person DialogueUI during room visits.
@export var room_background: Texture2D
@export var porn_sprite: Texture2D # Optional illustrated adult-scene background.

@export_group("Overnight Romance")
## The invitation is earned in ordinary dialogue, then acted on by returning at night.
@export var invitation_accepted_flag: StringName = &""
## An ID for the same illustrated scene, independent of its dialogue JSON.
@export var intimacy_scene_id: StringName = &""
## A short, consent-aware room conversation before the scene warning.
## Optional: no JSON retains the original direct-entry behavior.
@export_file("*.json") var overnight_prelude_json: String = ""
@export_file("*.json") var intimacy_dialogue_json: String = ""
## Played in the shared room UI the following morning, not outside the room.
@export_file("*.json") var morning_after_json: String = ""
## Quiet text between the illustrated encounter and the morning-after scene.
## Leave empty to use a neutral default line.
@export_multiline var overnight_transition_text: String = ""
@export var romance_complete_flag: StringName = &""
@export var romance_reward_id: StringName = &""

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
