extends Node
class_name SeaWorldDialogueQueue

# A presentation scheduler, NOT another dialogue or relationship manager.
# Story owners persist important flags before queuing. This only ensures that
# contextual underwater dialogue starts after ALL combat has ended.
signal world_event_started(event_id: StringName)
signal world_event_finished(event_id: StringName)

var _can_start: Callable
var _pending: Array[Dictionary] = []
var _active_id: StringName = &""
var _active_npc: NPCData = null
var _completed_this_dive: Dictionary = {}


func configure(safe_to_talk: Callable) -> void:
	_can_start = safe_to_talk
	if not DialogueManager.conversation_finished.is_connected(_on_conversation_finished):
		DialogueManager.conversation_finished.connect(_on_conversation_finished)


func enqueue(event_id: StringName, context: NPCData, json_path: String,
		cast: Array[NPCData] = [], priority: int = 0) -> bool:
	if event_id == &"" or context == null or json_path.is_empty() \
			or _completed_this_dive.has(event_id) or _active_id == event_id:
		return false
	for entry in _pending:
		if entry["id"] == event_id:
			return false
	_pending.append({
		"id": event_id, "context": context, "path": json_path,
		"cast": cast.duplicate(), "priority": priority
	})
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"]))
	return true


func pending_count() -> int:
	return _pending.size()


func clear_pending() -> void:
	_pending.clear()


func begin_new_dive() -> void:
	_pending.clear()
	_completed_this_dive.clear()
	_active_id = &""
	_active_npc = null


func _process(_delta: float) -> void:
	if _pending.is_empty() or _active_id != &"" or DialogueManager.is_active \
			or not _can_start.is_valid() or not bool(_can_start.call()):
		return
	var event: Dictionary = _pending.pop_front()
	var npc: NPCData = event["context"] as NPCData
	DialogueManager.request_conversation(npc, str(event["path"]), null,
		event["cast"] as Array[NPCData])
	if DialogueManager.is_active and DialogueManager.current_npc == npc:
		_active_id = event["id"]
		_active_npc = npc
		world_event_started.emit(_active_id)
	else:
		push_warning("Queued world dialogue could not start: " + str(event["id"]))


func _on_conversation_finished(npc: NPCData) -> void:
	if _active_id == &"" or npc != _active_npc:
		return
	var finished_id: StringName = _active_id
	_active_id = &""
	_active_npc = null
	_completed_this_dive[finished_id] = true
	world_event_finished.emit(finished_id)
