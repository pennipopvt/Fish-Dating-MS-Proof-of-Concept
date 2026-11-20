extends Node
class_name DivingParty

# Diving owns this roster. Townhouse and date actors never participate.
signal party_changed
const MAX_COMPANIONS: int = 3
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const FULL_SCHOOL_THOUGHT: String = "Hmm... I think a larger fishing party might scare the fish away."

var _members: Array[NPCData] = []


func configure(story: SeaStoryDirector) -> void:
	if not story.silas_surface_reveal_finished.is_connected(_welcome_silas):
		story.silas_surface_reveal_finished.connect(_welcome_silas)
	if story.has_silas_flag(&"silas_surface_transformed"):
		_welcome_silas()


func _welcome_silas() -> void:
	invite(SILAS)


func invite(npc: NPCData) -> bool:
	if npc == null or npc.npc_id == &"":
		return false
	for member in _members:
		if member.npc_id == npc.npc_id:
			return true
	if _members.size() >= MAX_COMPANIONS:
		if DialogueManager.is_active:
			DialogueManager.conversation_finished.connect(_say_school_is_full, CONNECT_ONE_SHOT)
		else:
			_say_school_is_full()
		return false
	_members.append(npc)
	party_changed.emit()
	return true


func _say_school_is_full(_npc: NPCData = null) -> void:
	if not DialogueManager.is_active:
		DialogueManager.request_player_monologue([FULL_SCHOOL_THOUGHT])


func dismiss(npc_id: StringName) -> bool:
	for member in _members:
		if member.npc_id == npc_id:
			_members.erase(member)
			party_changed.emit()
			return true
	return false


func has_companion(npc_id: StringName) -> bool:
	for member in _members:
		if member.npc_id == npc_id:
			return true
	return false


func members() -> Array[NPCData]:
	return _members.duplicate()
