extends Node2D
class_name SeaPartyFollower

# Fish-form actor for non-Silas school members. The same instance follows
# Penni or approaches a target. An optional NPCData combat loadout creates
# its own battle/behavior without changing the shared sprite presentation.
@export_range(12.0, 96.0, 1.0) var sprite_width: float = 22.0
@export_range(35.0, 220.0, 1.0) var swim_speed: float = 105.0
@export_range(35.0, 250.0, 1.0) var combat_swim_speed: float = 140.0
@export_range(8.0, 30.0, 1.0) var combat_attack_range: float = 18.0
@export_group("Following Penni")
@export_range(16.0, 90.0, 1.0) var first_follow_distance: float = 30.0
@export_range(12.0, 50.0, 1.0) var follow_distance_per_slot: float = 22.0
@export_range(1.0, 12.0, 0.5) var follow_arrival_radius: float = 4.0

var battle: DivingCompanionBattle
var behavior: CompanionCombatBehavior
var npc_data: NPCData
var retreating: bool = false
var _player: Player
var _trail: SeaFollowTrail
var _index: int
var _sprite: Sprite2D
var _lunge_time: float = 0.0
var _hurt_time: float = 0.0


func setup(npc: NPCData, player: Player, index: int,
		trail: SeaFollowTrail = null) -> void:
	npc_data = npc
	_player = player
	_trail = trail
	_index = index
	_sprite = Sprite2D.new()
	_sprite.name = "FishSprite"
	_sprite.z_index = 6
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = npc.underwater_sprite
	if _sprite.texture != null:
		var width: float = npc.sea_visuals.follower_width if npc.sea_visuals != null else sprite_width
		_sprite.scale = Vector2.ONE * (width / maxf(float(_sprite.texture.get_width()), 1.0))
	add_child(_sprite)
	if npc.sea_battle_stats != null:
		battle = DivingCompanionBattle.new()
		battle.name = "CompanionBattle"
		battle.stats = npc.sea_battle_stats
		add_child(battle)
		if npc.sea_combat_behavior_script != null:
			behavior = npc.sea_combat_behavior_script.new() as CompanionCombatBehavior
		if behavior == null:
			behavior = CompanionCombatBehavior.new()
		behavior.name = "CombatBehavior"
		add_child(behavior)


func begin_retreat() -> void:
	retreating = true
	queue_redraw()


func _process(delta: float) -> void:
	if retreating or _player == null or not _player.swimming:
		return
	_lunge_time = maxf(0.0, _lunge_time - delta)
	_hurt_time = maxf(0.0, _hurt_time - delta)
	if _sprite != null:
		_sprite.modulate = Color(1.0, 0.55, 0.5) if _hurt_time > 0.0 else Color.WHITE
	var side: float = -1.0 if _player.last_direction >= 0.0 else 1.0
	var destination: Vector2 = _player.global_position + Vector2(
		side * (26.0 + 17.0 * _index), 10.0 + 9.0 * (_index % 2))
	if _trail != null:
		var facing: Vector2 = Vector2.RIGHT if _player.last_direction >= 0.0 else Vector2.LEFT
		destination = _trail.point_behind(
			first_follow_distance + follow_distance_per_slot * _index, facing)
	var speed: float = swim_speed
	if battle != null and battle.is_active():
		var fish: DivingWildFish = battle.target
		var approach: Vector2 = (_player.global_position - fish.global_position).normalized()
		if approach.length_squared() < 0.01:
			approach = Vector2.LEFT
		var lunge: float = 7.0 * _lunge_time / 0.15
		destination = fish.global_position + approach * maxf(0.0, combat_attack_range - lunge)
		speed = combat_swim_speed
	var before_x: float = global_position.x
	var arrival_radius: float = 1.0 if battle != null and battle.is_active() else follow_arrival_radius
	if global_position.distance_to(destination) > arrival_radius:
		global_position = global_position.move_toward(destination, speed * delta)
	if _sprite != null:
		if global_position.x < before_x - 0.01:
			_sprite.flip_h = true
		elif global_position.x > before_x + 0.01:
			_sprite.flip_h = false
		_sprite.rotation = sin(Time.get_ticks_msec() * 0.008 + _index) * (
			0.12 if battle != null and battle.is_active() else 0.06)
	queue_redraw()


func can_strike_target() -> bool:
	return battle != null and battle.is_active() and \
		global_position.distance_to(battle.target.global_position) <= combat_attack_range + 4.0


func on_battle_hit(on_fish: bool) -> void:
	if on_fish:
		_lunge_time = 0.15
	else:
		_hurt_time = 0.12


func _draw() -> void:
	if retreating or battle == null or not _player or not _player.swimming:
		return
	if battle.is_active() or battle.health < battle.stats.max_health:
		DivingCompanionBattle.draw_health_bar(
			self, Vector2(0.0, -22.0), battle.health_ratio())
