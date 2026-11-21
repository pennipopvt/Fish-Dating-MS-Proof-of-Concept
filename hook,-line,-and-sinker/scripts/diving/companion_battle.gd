extends Node
class_name DivingCompanionBattle

# Reusable per-NPC battle: shared damage, timers, health and knockouts.
# Each NPC owns an instance; optional behavior hooks let the NPC decide how
# to fight without embedding any character-specific rules here.

signal hit(on_fish: bool, damage: float)
signal started(fish: DivingWildFish)
signal fish_knocked_out(fish: DivingWildFish)
signal companion_knocked_out()
signal ended()

@export var stats: CompanionStats
var behavior: CompanionCombatBehavior

var health: float = 0.0
var exhausted: bool = false
var target: DivingWildFish
var target_data: FishData
var _companion_timer: float = 0.0
var _fish_timer: float = 0.0


func _ready() -> void:
	if stats == null:
		push_error("CompanionBattle needs CompanionStats assigned in the NPC scene.")
		return
	health = stats.max_health


static func damage(attack: float, defense: float) -> float:
	return maxf(1.0, attack - defense * 0.5)


static func attack_interval(speed: float) -> float:
	return 1.0 / maxf(speed, 0.05)


func is_active() -> bool:
	return target != null and is_instance_valid(target)


func can_fight() -> bool:
	return stats != null and not exhausted and health > 0.0


func health_ratio() -> float:
	return clampf(health / maxf(stats.max_health, 1.0), 0.0, 1.0) if stats != null else 0.0


func start(fish: DivingWildFish, data: FishData) -> bool:
	if fish == null or not is_instance_valid(fish) or data == null or not can_fight():
		return false
	if is_active():
		stop()
	target = fish
	target_data = data
	fish.battling = true
	# The companion strikes first, half an interval in, so a command
	# feels responsive; the fish answers on its own full interval.
	_companion_timer = attack_interval(stats.speed) * 0.5
	_fish_timer = attack_interval(data.speed)
	started.emit(fish)
	return true


func stop() -> void:
	var was_active: bool = target != null
	if is_active():
		target.battling = false
	target = null
	target_data = null
	if was_active:
		ended.emit()


func rest() -> void:
	if stats == null:
		return
	health = stats.max_health
	exhausted = false


func step(delta: float, in_attack_range: bool = true) -> void:
	if target != null and not is_instance_valid(target):
		# The fish was freed elsewhere (caught, surfaced scene, etc.).
		stop()
	if not is_active():
		if not exhausted:
			health = minf(stats.max_health, health + stats.regen_per_second * delta)
		return
	# World combat is physical: timers start when Silas reaches the fish,
	# rather than damaging a target from anywhere in the sea.
	if not in_attack_range:
		return
	_companion_timer -= delta
	if _companion_timer <= 0.0:
		_companion_timer += attack_interval(stats.speed)
		var struck: DivingWildFish = target
		var dealt: float = damage(stats.attack, target_data.defense)
		if behavior != null:
			dealt = maxf(0.0, behavior.modify_damage(struck, dealt))
		if dealt > 0.0:
			struck.take_damage(dealt)
			struck.companion_weakened = true
			hit.emit(true, dealt)
		if behavior != null:
			behavior.on_hit(struck)
		# A behavior may have ended the fight during on_hit. Do not let
		# a stopped/retreating target attack or fall through to KO handling.
		if not is_active() or target != struck:
			return
		if struck.health <= 0.0:
			stop()
			fish_knocked_out.emit(struck)
			return
	_fish_timer -= delta
	if _fish_timer <= 0.0:
		_fish_timer += attack_interval(target_data.speed)
		var taken: float = damage(target_data.attack, stats.defense)
		health = maxf(0.0, health - taken)
		hit.emit(false, taken)
		if health <= 0.0:
			exhausted = true
			stop()
			companion_knocked_out.emit()


# Tiny pixel health bar, shared by wild fish and the companion.
static func draw_health_bar(canvas: CanvasItem, center: Vector2, ratio: float, width: float = 14.0) -> void:
	var r: float = clampf(ratio, 0.0, 1.0)
	var origin := Vector2(roundf(center.x - width * 0.5), roundf(center.y))
	canvas.draw_rect(Rect2(origin - Vector2.ONE, Vector2(width + 2.0, 4.0)), Color(0.04, 0.07, 0.10, 0.85))
	var fill := Color("#e5544b")
	if r > 0.6:
		fill = Color("#7bd36b")
	elif r > 0.3:
		fill = Color("#f0c24f")
	if r > 0.0:
		canvas.draw_rect(Rect2(origin, Vector2(maxf(1.0, roundf(width * r)), 2.0)), fill)
