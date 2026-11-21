extends CompanionCombatBehavior
class_name KudaCombatBehavior

# Kuda is deliberately lethal: unlike Silas, no safety threshold clamps
# damage or automatically recalls him. Low-health fish are in extra danger.
@export_range(0.0, 0.75, 0.05) var finisher_threshold: float = 0.35
@export_range(1.0, 2.5, 0.05) var finisher_damage_multiplier: float = 1.15


func modify_damage(target: DivingWildFish, amount: float) -> float:
	if target != null and target.health_ratio() <= finisher_threshold:
		return amount * finisher_damage_multiplier
	return amount
