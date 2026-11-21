extends Node
class_name SeaPartyCommands

# Contextual right-click command queue. The party roster owns order; each
# companion owns its OWN battle/health/behavior and the world owns fish.
# This node only assigns, recalls and rotates available companions.
signal assigned(npc_id: StringName, fish: DivingWildFish)
signal returned(npc_id: StringName)

var _ordered: Array[StringName] = []
var _available: Array[StringName] = []
var _entries: Dictionary = {}
var _clearing: bool = false


func register_member(npc: NPCData, actor: Node2D,
		battle: DivingCompanionBattle, behavior: CompanionCombatBehavior) -> void:
	if npc == null or npc.npc_id == &"" or actor == null or battle == null or behavior == null:
		return
	if _entries.has(npc.npc_id):
		return
	_entries[npc.npc_id] = {"actor": actor, "battle": battle, "behavior": behavior}
	_ordered.append(npc.npc_id)
	_available.append(npc.npc_id)
	battle.ended.connect(_on_battle_ended.bind(npc.npc_id))


func unregister_member(npc_id: StringName) -> void:
	if not _entries.has(npc_id):
		return
	var battle: DivingCompanionBattle = _battle(npc_id)
	_entries.erase(npc_id)
	_ordered.erase(npc_id)
	_available.erase(npc_id)
	if is_instance_valid(battle):
		battle.stop()


func clear() -> void:
	_clearing = true
	for npc_id in _ordered:
		var battle: DivingCompanionBattle = _battle(npc_id)
		if is_instance_valid(battle):
			battle.stop()
	_entries.clear()
	_ordered.clear()
	_available.clear()
	_clearing = false


func available_ids() -> Array[StringName]:
	return _available.duplicate()


func party_order() -> Array[StringName]:
	return _ordered.duplicate()


func next_available_id() -> StringName:
	for npc_id in _available:
		if _entries.has(npc_id):
			var battle: DivingCompanionBattle = _battle(npc_id)
			if is_instance_valid(battle) and battle.can_fight() and not battle.is_active():
				return npc_id
	return &""


func battle_for(npc_id: StringName) -> DivingCompanionBattle:
	return _battle(npc_id)


func owner_of_target(fish: DivingWildFish) -> StringName:
	if not is_instance_valid(fish):
		return &""
	for npc_id in _ordered:
		var battle: DivingCompanionBattle = _battle(npc_id)
		if is_instance_valid(battle) and battle.is_active() and battle.target == fish:
			return npc_id
	return &""


func send_next(fish: DivingWildFish, data: FishData) -> bool:
	if not is_instance_valid(fish) or data == null or fish.trapped \
			or owner_of_target(fish) != &"":
		return false
	var npc_id: StringName = next_available_id()
	if npc_id == &"":
		return false
	var entry: Dictionary = _entries[npc_id]
	var battle: DivingCompanionBattle = entry["battle"] as DivingCompanionBattle
	var behavior: CompanionCombatBehavior = entry["behavior"] as CompanionCombatBehavior
	if not is_instance_valid(behavior) or not behavior.on_command(fish, data):
		return false
	# Silas may refuse fish below his safety threshold. A refusal handles
	# the input but does NOT consume a slot or skip him for a later member.
	if battle.is_active() and battle.target == fish:
		_available.erase(npc_id)
		assigned.emit(npc_id, fish)
	return true


func recall_target(fish: DivingWildFish) -> bool:
	var owner: StringName = owner_of_target(fish)
	if owner == &"":
		return false
	_battle(owner).stop()
	return true


func recall_all() -> bool:
	var had_orders: bool = false
	for npc_id in _ordered:
		var battle: DivingCompanionBattle = _battle(npc_id)
		if is_instance_valid(battle) and battle.is_active():
			had_orders = true
			battle.stop()
	# A full recall always resets queue order; individual returns are FIFO.
	_available = _ordered.duplicate()
	return had_orders


func step(delta: float) -> void:
	for npc_id in _ordered:
		if not _entries.has(npc_id):
			continue
		var entry: Dictionary = _entries[npc_id]
		var actor: Node2D = entry["actor"] as Node2D
		var behavior: CompanionCombatBehavior = entry["behavior"] as CompanionCombatBehavior
		if not is_instance_valid(actor) or not is_instance_valid(behavior):
			continue
		var in_range: bool = bool(actor.call("can_strike_target")) \
			if actor.has_method("can_strike_target") else false
		behavior.on_combat_update(delta, in_range)


func _battle(npc_id: StringName) -> DivingCompanionBattle:
	if not _entries.has(npc_id):
		return null
	return _entries[npc_id]["battle"] as DivingCompanionBattle


func _on_battle_ended(npc_id: StringName) -> void:
	if _clearing or not _entries.has(npc_id) or _available.has(npc_id):
		return
	_available.append(npc_id)
	returned.emit(npc_id)
