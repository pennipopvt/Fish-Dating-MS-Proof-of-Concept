class_name KudaScareTacticsPassive
extends SeaCompanionPassive

# Same phase and state as a full stagger break, but shorter and triggered
# once upon the initial successful net catch rather than by parrying.
@export_range(0.1, 1.0, 0.05) var opening_stun_fraction: float = 0.5


func on_initial_net(combat: DivingCombat) -> void:
	if combat != null:
		combat.apply_opening_stun(opening_stun_fraction)
