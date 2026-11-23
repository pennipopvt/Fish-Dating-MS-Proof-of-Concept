class_name SeaCompanionPassive
extends Resource

# Optional NPCData resource. Only the existing romance/party rules can enable
# it; specific abilities customize one of these two hooks.
@export var display_name: String = ""


func fish_identification(_species: FishData, _bag: SeaDiveInventory) -> String:
	return ""


func on_initial_net(_combat: DivingCombat) -> void:
	pass
