extends Node
class_name CompanionCombatBehavior

# Reusable lifecycle for an NPC's OWN combat component. Characters define
# their decisions in subclasses; the shared battle still owns hit timing,
# damage, health and attack resolution.
var actor: Node2D
var battle: DivingCompanionBattle


func _ready() -> void:
	actor = get_parent() as Node2D
	if actor == null:
		push_error("CompanionCombatBehavior needs a Node2D companion actor.")
		return
	battle = actor.get_node_or_null("CompanionBattle") as DivingCompanionBattle
	if battle == null:
		push_error("Companion actor needs its own CompanionBattle child.")
		return
	battle.behavior = self
	battle.ended.connect(on_combat_end)


func on_command(target: DivingWildFish, data: FishData) -> bool:
	return battle != null and battle.start(target, data)


func on_combat_update(delta: float, in_attack_range: bool) -> void:
	if battle != null:
		battle.step(delta, in_attack_range)


# General damage customization hook; only a subclass chooses what it means.
func modify_damage(_target: DivingWildFish, amount: float) -> float:
	return amount


func on_hit(_target: DivingWildFish) -> void:
	pass


func on_combat_end() -> void:
	pass
