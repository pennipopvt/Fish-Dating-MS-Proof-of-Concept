extends Node
class_name DivingParty

# Diving owns this roster. Townhouse and date actors never participate.
signal party_changed
const MAX_COMPANIONS: int = 3
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const FULL_SCHOOL_THOUGHT: String = "Hmm... I think a larger fishing party might scare the fish away."

var _members: Array[NPCData] = []


func configure(story: SeaStoryDirector) -> void:
	if not story.silas_surface_reveal_finished.is_connected(_welcome_silas):
		story.silas_surface_reveal_finished.connect(_welcome_silas)
	if story.has_silas_flag(&"silas_surface_transformed"):
		_welcome_silas()
	if story.has_kuda_flag(&"Recruited"):
		invite(KUDA)


func _welcome_silas() -> void:
	invite(SILAS)


func invite(npc: NPCData) -> bool:
	if npc == null or npc.npc_id == &"":
		return false
	# Refusal is temporary. Leave the existing roster membership intact so
	# the companion automatically rejoins when their morale recovers.
	if not AffectionManager.can_join_dive(npc.npc_id):
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
	# All existing callers use members() for the physical active dive (dock
	# entrance, followers and surfacing). Keep unwilling NPCs in the roster.
	var willing: Array[NPCData] = []
	for member in _members:
		if AffectionManager.can_join_dive(member.npc_id):
			willing.append(member)
	return willing


func roster_members() -> Array[NPCData]:
	return _members.duplicate()


func unwilling_members() -> Array[NPCData]:
	var unwilling: Array[NPCData] = []
	for member in _members:
		if not AffectionManager.can_join_dive(member.npc_id):
			unwilling.append(member)
	return unwilling
