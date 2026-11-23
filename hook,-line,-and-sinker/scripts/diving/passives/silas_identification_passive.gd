class_name SilasIdentificationPassive
extends SeaCompanionPassive

# Reveal already-caught species. Mark quota species only while the quota
# needs more than Penni currently has in storage + the diving bag.
@export var unknown_name: String = "???"
@export var quota_star: String = "★"


func fish_identification(species: FishData, bag: SeaDiveInventory) -> String:
	if species == null or species.item_data == null:
		return ""
	var item_id: StringName = species.item_data.item_id
	var name: String = String(item_id).capitalize() if FishingManager.catch_dex.has(species) else unknown_name
	var carried: int = bag.count_species(item_id) if bag != null else 0
	var needed: int = maxi(0, QuotaManager.get_remaining(item_id)
		- FishingManager.count_in_storage(item_id) - carried)
	return (quota_star + " " if needed > 0 else "") + name
