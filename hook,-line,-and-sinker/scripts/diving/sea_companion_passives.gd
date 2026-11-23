class_name SeaCompanionPassives
extends Node

# Owns which romance-unlocked companion passives are present in THIS dive.
# This deliberately doesn't add another party, romance or combat state.
@export_group("Identification Display")
@export var label_offset: Vector2 = Vector2(-42.0, -33.0)
@export_range(6, 18, 1, "suffix:px") var label_font_size: int = 8

var _fish_catalog: Dictionary = {}
var _bag: SeaDiveInventory
var _active: Dictionary = {}


func configure(fish_catalog: Dictionary, bag: SeaDiveInventory) -> void:
	_fish_catalog = fish_catalog
	_bag = bag
	if not FishingManager.fish_caught.is_connected(_on_fish_caught):
		FishingManager.fish_caught.connect(_on_fish_caught)
	if not FishingManager.storage_changed.is_connected(refresh_labels):
		FishingManager.storage_changed.connect(refresh_labels)
	if not QuotaManager.quota_changed.is_connected(refresh_labels):
		QuotaManager.quota_changed.connect(refresh_labels)
	if bag != null and not bag.carried_changed.is_connected(_on_carried_changed):
		bag.carried_changed.connect(_on_carried_changed)
	refresh_labels()


func add_member(npc: NPCData) -> void:
	if npc == null or npc.sea_passive == null:
		return
	if not AffectionManager.has_completed_romance(npc.npc_id):
		return
	if _active.has(npc.npc_id):
		return
	_active[npc.npc_id] = npc.sea_passive
	refresh_labels()


func remove_member(npc_id: StringName) -> void:
	if _active.erase(npc_id):
		refresh_labels()


func clear_party() -> void:
	_active.clear()
	refresh_labels()


func has_passive(npc_id: StringName) -> bool:
	return _active.has(npc_id)


func on_initial_net(combat: DivingCombat) -> void:
	if combat == null or not combat.is_active():
		return
	for entry in _active.values():
		var ability: SeaCompanionPassive = entry as SeaCompanionPassive
		if ability != null:
			ability.on_initial_net(combat)


func refresh_labels() -> void:
	for fish in _fish_catalog:
		if not is_instance_valid(fish):
			continue
		var data: FishData = _fish_catalog.get(fish) as FishData
		var label_text: String = ""
		for entry in _active.values():
			var ability: SeaCompanionPassive = entry as SeaCompanionPassive
			if ability == null:
				continue
			var candidate: String = ability.fish_identification(data, _bag)
			if not candidate.is_empty():
				label_text = candidate
				break
		(fish as DivingWildFish).set_identification(label_text, label_offset, label_font_size)


func _on_fish_caught(_species: FishData) -> void:
	refresh_labels()


func _on_carried_changed(_count: int) -> void:
	refresh_labels()
