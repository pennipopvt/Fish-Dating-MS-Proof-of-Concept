extends CompanionCombatBehavior
class_name SilasCombatBehavior

# All nonlethal limits and refusals belong to Silas, never the base class.
signal fish_spared(fish: DivingWildFish)
signal attack_refused(fish: DivingWildFish)

@export_range(0.05, 1.0, 0.05) var safety_health_ratio: float = 0.5


func on_command(target: DivingWildFish, data: FishData) -> bool:
	if target != null and target.health_ratio() <= safety_health_ratio + 0.0001:
		# Refusing a new order also recalls Silas if he was targeting another fish.
		if battle != null and battle.is_active():
			battle.stop()
		attack_refused.emit(target)
		return true
	return super.on_command(target, data)


func on_combat_update(delta: float, in_attack_range: bool) -> void:
	if battle != null and battle.is_active() \
			and battle.target.health_ratio() <= safety_health_ratio + 0.0001:
		_spare_fish(battle.target)
		return
	super.on_combat_update(delta, in_attack_range)


func modify_damage(target: DivingWildFish, amount: float) -> float:
	# Apply this BEFORE damage, so even one strong hit cannot kill a fish.
	var lowest_allowed_health: float = target.max_health * safety_health_ratio
	return minf(amount, maxf(0.0, target.health - lowest_allowed_health))


func on_hit(target: DivingWildFish) -> void:
	if target.health_ratio() <= safety_health_ratio + 0.0001:
		_spare_fish(target)


func _spare_fish(target: DivingWildFish) -> void:
	if battle == null or not battle.is_active() or battle.target != target:
		return
	battle.stop()
	fish_spared.emit(target)
