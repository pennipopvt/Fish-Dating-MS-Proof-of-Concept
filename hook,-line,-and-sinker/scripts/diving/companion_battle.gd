extends Node
class_name DivingCompanionBattle

# Early companion-combat prototype. Target selection and autonomous attacks
# live here, separate from the existing net/reel/parry state machine.
signal target_changed(fish: DivingWildFish)
signal attack_landed(fish: DivingWildFish, damage: float)
signal fish_defeated(fish: DivingWildFish)
signal companion_hit()
signal companion_incapacitated()
signal companion_recovered()
signal cover_activated()

@export_range(10.0, 80.0, 1.0) var attack_range: float = 33.0
@export_range(10.0, 80.0, 1.0) var retaliation_range: float = 34.0
@export_range(1.0, 25.0, 0.5) var auto_attack_damage: float = 8.0
@export_range(0.5, 5.0, 0.1) var auto_attack_interval: float = 1.5
@export_range(0.5, 5.0, 0.1) var retaliation_interval: float = 2.3
@export_range(1.0, 30.0, 0.5) var retaliation_damage: float = 12.0
@export_range(20.0, 120.0, 1.0) var max_companion_health: float = 60.0
@export_range(3.0, 60.0, 1.0) var recovery_seconds: float = 18.0
@export_range(1.0, 10.0, 0.5) var cover_duration: float = 3.5
@export_range(5.0, 30.0, 1.0) var cover_cooldown: float = 14.0

var target: DivingWildFish
var companion_health: float = 60.0
var incapacitated_time: float = 0.0
var cover_time: float = 0.0
var _cover_cooldown_time: float = 0.0
var _attack_time: float = 0.7
var _retaliation_time: float = 1.4


func is_companion_available() -> bool:
	return incapacitated_time <= 0.0


func has_target() -> bool:
	return is_instance_valid(target) and not target.defeated


func set_target(fish: DivingWildFish) -> bool:
	if fish == null or not is_instance_valid(fish) or fish.defeated or fish.trapped or not is_companion_available():
		return false
	if target == fish:
		clear_target()
		return true
	clear_target()
	target = fish
	target.set_attack_target(true)
	_attack_time = 0.6
	_retaliation_time = 1.7
	target_changed.emit(target)
	return true


func clear_target() -> void:
	if is_instance_valid(target):
		target.set_attack_target(false)
	target = null
	target_changed.emit(null)


func rest_on_shore() -> void:
	clear_target()
	companion_health = max_companion_health
	incapacitated_time = 0.0
	cover_time = 0.0
	_cover_cooldown_time = 0.0


func tick(delta: float, companion_position: Vector2, companion_present: bool, paused: bool) -> void:
	_cover_cooldown_time = maxf(0.0, _cover_cooldown_time - delta)
	cover_time = maxf(0.0, cover_time - delta)
	if incapacitated_time > 0.0:
		incapacitated_time = maxf(0.0, incapacitated_time - delta)
		if incapacitated_time <= 0.0:
			companion_health = max_companion_health * 0.65
			companion_recovered.emit()
	if not companion_present or not is_companion_available():
		if has_target():
			clear_target()
		return
	if not has_target():
		if target != null:
			clear_target()
		return
	if paused:
		return
	if companion_position.distance_to(target.position) > attack_range:
		return

	_attack_time -= delta
	_retaliation_time -= delta
	if _attack_time <= 0.0:
		_attack_time = auto_attack_interval
		var victim: DivingWildFish = target
		var defeated_now: bool = victim.take_damage(auto_attack_damage)
		attack_landed.emit(victim, auto_attack_damage)
		if defeated_now:
			# No catches or inventory rewards from battle defeats. The player
			# must net the fish before its health is depleted.
			clear_target()
			fish_defeated.emit(victim)
			return

	if _retaliation_time > 0.0 or companion_position.distance_to(target.position) > retaliation_range:
		return
	_retaliation_time = retaliation_interval
	# Silas's signature defensive special triggers automatically when his
	# health gets low. No extra player button or ability menu required.
	if companion_health <= max_companion_health * 0.45 and _cover_cooldown_time <= 0.0:
		cover_time = cover_duration
		_cover_cooldown_time = cover_cooldown
		cover_activated.emit()
	if cover_time > 0.0:
		return
	companion_health = maxf(0.0, companion_health - retaliation_damage)
	companion_hit.emit()
	if companion_health <= 0.0:
		incapacitated_time = recovery_seconds
		clear_target()
		companion_incapacitated.emit()
