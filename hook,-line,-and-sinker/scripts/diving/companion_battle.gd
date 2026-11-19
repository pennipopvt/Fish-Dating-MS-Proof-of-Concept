extends Node
class_name DivingCompanionBattle

# Underwater auto-battle: the player sends their companion (Silas) at a wild
# fish to wear its health down before netting it. Both sides hit each other
# on their own speed timers. The player decides when to call him back:
# a fish at 0 health is knocked out and lost, and a companion at 0 health is
# exhausted until the player rests (GameManager.day_started -> rest()).

signal hit(on_fish: bool, damage: float)
signal started(fish: DivingWildFish)
signal fish_knocked_out(fish: DivingWildFish)
signal companion_knocked_out()
signal ended()

@export var stats: CompanionStats = preload("res://resources/companions/silas_battle.tres")

var health: float = 0.0
var exhausted: bool = false
var target: DivingWildFish
var target_data: FishData
var _companion_timer: float = 0.0
var _fish_timer: float = 0.0


func _ready() -> void:
	health = stats.max_health


static func damage(attack: float, defense: float) -> float:
	return maxf(1.0, attack - defense * 0.5)


static func attack_interval(speed: float) -> float:
	return 1.0 / maxf(speed, 0.05)


func is_active() -> bool:
	return target != null and is_instance_valid(target)


func can_fight() -> bool:
	return not exhausted and health > 0.0


func health_ratio() -> float:
	return clampf(health / maxf(stats.max_health, 1.0), 0.0, 1.0)


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
		var dealt: float = damage(stats.attack, target_data.defense)
		target.take_damage(dealt)
		hit.emit(true, dealt)
		if target.health <= 0.0:
			var fallen: DivingWildFish = target
			stop()
			fish_knocked_out.emit(fallen)
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
