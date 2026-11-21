class_name RelationshipEventData
extends Resource

# Editor-authored incident, tracked per NPC. Text and reconciliation remain
# in the existing dialogue JSON rather than special-case NPC scripts.
@export var event_id: StringName = &""
## Optional priority encounter while active. Leave blank to use conditional
## greetings/choices in an NPC's everyday dialogue.
@export_file("*.json") var followup_dialogue_json: String = ""
@export_range(-100, 100, 1) var priority: int = 20
## Arbitrary action IDs (e.g. "overnight"). Owning systems decide what blocking
## means; no dialogue manager knows about romance or diving mechanics.
@export var blocks_actions: Array[StringName] = []
